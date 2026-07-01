@file:Suppress("DEPRECATION")   // the value-less BLE read/write APIs cover minSdk 29 (typed ones are API 33+)

package com.learningischange.tidbitstrivia.net

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.ParcelUuid
import java.util.ArrayDeque
import java.util.UUID

/**
 * Transport adapter #3: **Bluetooth LE (GATT)** — the truly universal link. No
 * Wi-Fi, no router, no server, no shared network of any kind: two phones in a
 * field can play. Standard GATT is cross-platform (Android BLE ↔ iOS Core
 * Bluetooth), so the same `NightMessage` state machine + AES-GCM framing ride
 * over it. BLE is low-bandwidth, but the night is small once it's the only
 * payload, and each frame is MTU-chunked and reassembled by `NightFramer` — the
 * chunk boundaries are invisible to the app because framing is a byte stream.
 *
 * Host = GATT server (advertises + serves multiple centrals); joiner = central
 * (scans for the room code in the advertisement, connects). Confidentiality is
 * the app-layer AES-GCM (an OPEN GATT link is fine — one less cross-vendor knob).
 *
 * DEVICE-GATED: emulators have no real BLE radio, so this is compile-verified
 * only. Needs BLUETOOTH_ADVERTISE / _CONNECT / _SCAN (Android 12+, runtime).
 */
object BleUuids {
    val service: UUID = UUID.fromString("7d1b0001-6b2f-4b3a-9c1e-7a1d0f7e0001")
    val toHost: UUID = UUID.fromString("7d1b0002-6b2f-4b3a-9c1e-7a1d0f7e0001")   // central → peripheral (write)
    val toPeer: UUID = UUID.fromString("7d1b0003-6b2f-4b3a-9c1e-7a1d0f7e0001")   // peripheral → central (notify)
    val cccd: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
}

private const val CHUNK = 180   // conservative payload/notification size before MTU negotiation

fun hasBle(context: Context): Boolean {
    val mgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    return mgr?.adapter?.isEnabled == true &&
        context.packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_BLUETOOTH_LE)
}

// ---- Host: GATT server + advertiser ----

@SuppressLint("MissingPermission")   // permissions are requested by the UI before hosting
class BleHostTransport(private val context: Context) : NightHostTransport {
    private val mgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private var server: BluetoothGattServer? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var notifyChar: BluetoothGattCharacteristic? = null
    private val peers = HashMap<String, BleServerPeer>()

    override fun start(roomCode: String, onPeer: (NightPeer) -> Unit, onFrame: (NightPeer, ByteArray) -> Unit, onDrop: (NightPeer) -> Unit) {
        val toHost = BluetoothGattCharacteristic(BleUuids.toHost,
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_WRITE)
        val toPeer = BluetoothGattCharacteristic(BleUuids.toPeer,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY, BluetoothGattCharacteristic.PERMISSION_READ)
        toPeer.addDescriptor(BluetoothGattDescriptor(BleUuids.cccd,
            BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE))
        notifyChar = toPeer

        val gattServer = mgr.openGattServer(context, object : BluetoothGattServerCallback() {
            override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    val peer = peers.getOrPut(device.address) { BleServerPeer(device) }
                    onPeer(peer)
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    peers.remove(device.address)?.let { onDrop(it) }
                }
            }
            override fun onCharacteristicWriteRequest(device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
                                                      preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?) {
                if (characteristic.uuid == BleUuids.toHost && value != null) {
                    peers[device.address]?.let { onFrame(it, value) }   // NightFramer reassembles the stream
                }
                if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
            override fun onDescriptorWriteRequest(device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
                                                  preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?) {
                if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
            override fun onNotificationSent(device: BluetoothDevice, status: Int) {
                peers[device.address]?.onSent()
            }
        }) ?: return
        server = gattServer
        val service = BluetoothGattService(BleUuids.service, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(toHost); service.addCharacteristic(toPeer)
        gattServer.addService(service)

        // Advertise the service + the room code (in the service data) so a scanner picks the room.
        advertiser = mgr.adapter.bluetoothLeAdvertiser
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true).build()
        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(BleUuids.service))
            .addServiceData(ParcelUuid(BleUuids.service), roomCode.uppercase().toByteArray())
            .build()
        advertiseCallback = object : AdvertiseCallback() {}
        advertiser?.startAdvertising(settings, data, advertiseCallback)
    }

    override fun stop() {
        advertiseCallback?.let { runCatching { advertiser?.stopAdvertising(it) } }; advertiseCallback = null
        peers.values.forEach { it.close() }; peers.clear()
        runCatching { server?.close() }; server = null
    }

    private inner class BleServerPeer(val device: BluetoothDevice) : NightPeer {
        override val id = device.address
        private val queue = ArrayDeque<ByteArray>()
        private var busy = false
        override fun send(frame: ByteArray) {
            synchronized(queue) { frame.chunked(CHUNK).forEach { queue.add(it) }; if (!busy) pump() }
        }
        fun onSent() { synchronized(queue) { busy = false; pump() } }
        private fun pump() {
            val ch = notifyChar ?: return
            val next = queue.poll() ?: return
            busy = true; ch.value = next
            runCatching { server?.notifyCharacteristicChanged(device, ch, false) }
        }
        override fun close() { runCatching { server?.cancelConnection(device) } }
    }
}

// ---- Client: scanner + central ----

@SuppressLint("MissingPermission")
class BleClientTransport(private val context: Context) : NightClientTransport {
    private val mgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private var scanner: BluetoothLeScanner? = null
    private var scanCallback: ScanCallback? = null
    private var gatt: BluetoothGatt? = null
    private var peer: BleCentralPeer? = null

    override fun connect(roomCode: String, onConnected: (NightPeer) -> Unit, onFrame: (ByteArray) -> Unit, onDropped: () -> Unit, onStatus: (String) -> Unit) {
        val code = roomCode.uppercase()
        onStatus("Looking nearby (Bluetooth)…")
        scanner = mgr.adapter.bluetoothLeScanner
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(BleUuids.service)).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val sd = result.scanRecord?.getServiceData(ParcelUuid(BleUuids.service))?.toString(Charsets.UTF_8)?.uppercase()
                if (sd != code || gatt != null) return
                runCatching { scanner?.stopScan(this) }
                onStatus("Connecting…")
                connectGatt(result.device, onConnected, onFrame, onDropped, onStatus)
            }
        }
        scanner?.startScan(listOf(filter), settings, scanCallback)
    }

    private fun connectGatt(device: BluetoothDevice, onConnected: (NightPeer) -> Unit, onFrame: (ByteArray) -> Unit, onDropped: () -> Unit, onStatus: (String) -> Unit) {
        gatt = device.connectGatt(context, false, object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) g.requestMtu(517)
                else if (newState == BluetoothProfile.STATE_DISCONNECTED) { peer = null; onDropped() }
            }
            override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) { g.discoverServices() }
            override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                val svc = g.getService(BleUuids.service) ?: return
                val notify = svc.getCharacteristic(BleUuids.toPeer) ?: return
                g.setCharacteristicNotification(notify, true)
                notify.getDescriptor(BleUuids.cccd)?.let {
                    it.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    g.writeDescriptor(it)
                }
                val write = svc.getCharacteristic(BleUuids.toHost) ?: return
                val p = BleCentralPeer(g, write); peer = p
                onConnected(p)
            }
            override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
                if (characteristic.uuid == BleUuids.toPeer) onFrame(characteristic.value ?: return)
            }
            override fun onCharacteristicWrite(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
                peer?.onWritten()
            }
        })
    }

    override fun disconnect() {
        scanCallback?.let { runCatching { scanner?.stopScan(it) } }; scanCallback = null
        peer?.close(); peer = null
        runCatching { gatt?.close() }; gatt = null
    }

    private inner class BleCentralPeer(val g: BluetoothGatt, val write: BluetoothGattCharacteristic) : NightPeer {
        override val id = g.device.address
        private val queue = ArrayDeque<ByteArray>()
        private var busy = false
        override fun send(frame: ByteArray) {
            synchronized(queue) { frame.chunked(CHUNK).forEach { queue.add(it) }; if (!busy) pump() }
        }
        fun onWritten() { synchronized(queue) { busy = false; pump() } }
        private fun pump() {
            val next = queue.poll() ?: return
            busy = true; write.value = next
            write.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            runCatching { g.writeCharacteristic(write) }
        }
        override fun close() { runCatching { g.disconnect() } }
    }
}

/** Split a frame into BLE-sized chunks (the byte stream is reassembled by NightFramer). */
private fun ByteArray.chunked(size: Int): List<ByteArray> {
    if (this.size <= size) return listOf(this)
    val out = ArrayList<ByteArray>((this.size + size - 1) / size)
    var i = 0
    while (i < this.size) { val end = minOf(i + size, this.size); out.add(copyOfRange(i, end)); i = end }
    return out
}
