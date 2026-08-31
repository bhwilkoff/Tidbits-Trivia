# Windows dev box — one-time setup

A real Windows 10/11 machine on the LAN, driven the same way the Apple TV and the
Pixel are: deploy, launch, photograph, grade.

**Nothing needs downloading.** Windows 10 (1809+) and Windows 11 ship OpenSSH
Server as a built-in optional feature. Turning it on is the whole install.

---

## What this changes

Decision 045 concluded there was no Windows machine, so `windows-latest` **is**
the box and every Windows change is observed through CI artifacts — a push and a
~4-minute workflow per look. That was correct while it was true.

A real box changes the ITERATION loop, not the gate:

| | before | now |
|---|---|---|
| See a UI change | push → CI → download artifact (~4 min) | `python3 tools/win_run.py` (~30 s) |
| Prove it ships | `windows-latest` CI | **unchanged — still `windows-latest`** |

"It works on the machine in the den" is not "it works on a clean runner." That
machine has your fonts, your DPI, your GPU and your installed runtimes. CI stays
the thing that decides whether a change is good.

---

## 1. Enable OpenSSH Server

In an **Administrator** PowerShell on the Windows box:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service   -Name sshd -StartupType Automatic
Start-Service -Name sshd

# The installer usually adds this; harmless if it already exists.
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' `
  -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

Then note the address and username:

```powershell
(Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -like '10.*' }).IPAddress
$env:USERNAME
```

## 2. Install the harness public key

This is the key generated for this purpose. The private half never leaves the
Mac, and no password is ever typed, stored, or seen by the tooling.

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII1T4N2mDSugy84NYuuZccPy452lfwjCD1f5zq9zL7mt tidbits-win-harness
```

**The trap:** for an account in the Administrators group, Windows OpenSSH ignores
`~/.ssh/authorized_keys` and reads `C:\ProgramData\ssh\administrators_authorized_keys`
instead — with strict ACLs. A key in the "obvious" place simply never works, with
no error that says so.

**If the account is an administrator** (the usual case), in Administrator PowerShell:

```powershell
$key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII1T4N2mDSugy84NYuuZccPy452lfwjCD1f5zq9zL7mt tidbits-win-harness'
$f = 'C:\ProgramData\ssh\administrators_authorized_keys'
Add-Content -Path $f -Value $key
icacls $f /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F'
```

**If it is a standard account:**

```powershell
$key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII1T4N2mDSugy84NYuuZccPy452lfwjCD1f5zq9zL7mt tidbits-win-harness'
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh" | Out-Null
Add-Content -Path "$env:USERPROFILE\.ssh\authorized_keys" -Value $key
```

## 3. Point the harness at it

On the Mac:

```bash
export TIDBITS_WIN_HOST='<username>@10.0.0.<n>'
python3 tools/winbox.py --check
```

A healthy check prints the OS caption, version, computer name and 64-bit flag.

Add the export to your shell profile so it survives a new terminal.

---

## Using it

```bash
python3 tools/win_run.py --deploy            # publish on the Mac, copy, sweep
python3 tools/win_run.py --only home,records # just those surfaces
python3 tools/winbox.py --shot /tmp/win.png  # launch and photograph once
```

The app is published **self-contained** (`PublishSingleFile`, `win-x64`), so the
box needs no .NET SDK — it is a device, not a build server. Publishing happens on
the Mac, which is also how the CI-only pipeline ever worked.

---

## Things that will bite

- **Admin key path.** See above. This is the single most common reason a correct
  key is refused.
- **`BatchMode=yes` is deliberate.** The tooling must fail loudly rather than sit
  on a password prompt forever. If auth is not working you get an immediate
  error, not a hang.
- **The capture is the whole desktop, not the window.** On macOS a window-region
  grab repeatedly photographed whatever was in front of the app; there is no
  reason to expect Windows to be kinder, and what the machine is showing is the
  evidence either way.
- **A dark frame is reported as a measurement** — percent black and mean luma —
  never as "the screen was off". Asserting a cause from an empty OCR result is
  how a working iPhone got written up as asleep.
- **MSIX vs single-file.** `windows-store.yml` publishes multi-file because MSIX
  and `PublishSingleFile` are incompatible; this harness uses the single-file
  build for iteration only. Do not unify them.
