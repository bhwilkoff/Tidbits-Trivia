package com.learningischange.tidbitstrivia.notifications

import com.google.firebase.messaging.FirebaseMessagingService
import com.learningischange.tidbitstrivia.data.PlayerIdentity

/**
 * Catches a ROTATED FCM token (Firebase reissues on reinstall, restore and clear-data) and
 * re-uploads it, so a reminder never goes to a dead handle. Displaying the notification
 * itself is FCM's default behaviour for a message with a `notification` payload — which is
 * what `tools/send_reminders.py` sends — so there is nothing to do in onMessageReceived.
 */
class AppFirebaseMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        PlayerIdentity.savePushToken(token, "android")
    }
}
