package com.workspace.client.k7m4

import android.content.Intent
data class OrderReminder(
    val key: String,
    val title: String,
    val triggerAtMillis: Long,
    val deadlineAtMillis: Long,
    val kind: String,
    val label: String,
) {
    companion object {
        fun fromIntent(intent: Intent): OrderReminder? {
            val key = intent.getStringExtra("key").orEmpty()
            val title = intent.getStringExtra("title").orEmpty()
            val kind = intent.getStringExtra("kind").orEmpty()
            val label = intent.getStringExtra("label").orEmpty()
            val triggerAt = intent.getLongExtra("triggerAtMillis", -1L)
            val deadlineAt = intent.getLongExtra("deadlineAtMillis", -1L)
            if (
                key.isBlank() ||
                title.isBlank() ||
                kind.isBlank() ||
                label.isBlank() ||
                triggerAt <= 0L ||
                deadlineAt <= 0L
            ) {
                return null
            }

            return OrderReminder(
                key = key,
                title = title,
                triggerAtMillis = triggerAt,
                deadlineAtMillis = deadlineAt,
                kind = kind,
                label = label,
            )
        }

    }
}
