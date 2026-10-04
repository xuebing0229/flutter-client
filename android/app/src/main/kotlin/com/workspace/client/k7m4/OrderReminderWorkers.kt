package com.workspace.client.k7m4

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters

class OrderReminderRescheduleWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {
    override fun doWork(): Result {
        return try {
            OrderReminderScheduler.rescheduleAll(applicationContext)
            Result.success()
        } catch (error: Exception) {
            ReminderDiagnostics.markFailure(
                applicationContext,
                "reschedule worker: ${error.message}",
            )
            Result.retry()
        }
    }

    companion object {
        private const val WORK_NAME = "order-reminder-reschedule"

        fun enqueue(context: Context) {
            val request = OneTimeWorkRequest.Builder(
                OrderReminderRescheduleWorker::class.java,
            )
                .setExpedited(
                    OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST,
                )
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                request,
            )
        }
    }
}
