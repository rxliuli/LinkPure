package com.rxliuli.linkpure.clean

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.rxliuli.linkpure.MainActivity
import com.rxliuli.linkpure.R

/**
 * 清洗完之后的通知。
 *
 * 静默模式下**原位替换本身就是反馈**（选区里的文字当场变了），
 * 但「本来就是干净的」和「这压根不是 URL」这两种情况完全没有反馈——
 * 用户会怀疑是不是没生效。通知就是补这个洞的。
 */
object CleanNotifier {

    private const val CHANNEL_ID = "clean"
    private const val NOTIFICATION_ID = 1

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.notif_channel_name),
                NotificationManager.IMPORTANCE_LOW, // 不响不震不弹头，安静地待在通知栏
            ).apply {
                description = context.getString(R.string.notif_channel_desc)
            },
        )
    }

    fun show(context: Context, outcome: Cleaner.Outcome, copiedInstead: Boolean = false) {
        if (!canNotify(context)) return

        val title: String
        // ★ 正文是**清洗后的 URL**，不是一句概括。
        //   用户要知道的就是「它变成了什么」；macOS 侧也是这么发的
        //   （`NotificationService.post(title: "URL Rewritten", body: to)`）。
        val text: String
        /** 展开后才看得到的补充信息；没有就不写。 */
        val detail: String?

        if (!outcome.isUrl) {
            title = context.getString(R.string.notif_not_a_link_title)
            text = context.getString(R.string.notif_not_a_url)
            detail = null
        } else {
            title = if (outcome.changed) {
                context.getString(R.string.notif_cleaned_title)
            } else {
                context.getString(R.string.notif_already_clean_title)
            }
            text = outcome.output
            detail = when {
                copiedInstead -> context.getString(R.string.notif_readonly_note)
                else -> outcome.summary.ifEmpty { null }
            }
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            // 收起时只显示 URL；展开后才多一行「去掉了几个参数」
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(listOfNotNull(text, detail).joinToString("\n")),
            )
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setShowWhen(false)
            .setAutoCancel(true)
            .setContentIntent(
                PendingIntent.getActivity(
                    context,
                    0,
                    Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )

        // 「复制」：这时候文本就在我们手上，不需要读剪贴板——顺手补上
        // 「清洗完要粘到别处」的场景。
        if (outcome.isUrl) {
            builder.addAction(
                R.drawable.ic_notification,
                context.getString(R.string.notif_action_copy),
                copyPendingIntent(context, outcome.output),
            )
        }

        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, builder.build())
    }

    fun copyPendingIntent(context: Context, text: String): PendingIntent {
        val intent = Intent(context, CopyActionReceiver::class.java)
            .putExtra(CopyActionReceiver.EXTRA_TEXT, text)
        return PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    private fun canNotify(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    /** 通知栏里那条的 id。 */
    internal fun notificationId(): Int = NOTIFICATION_ID
}
