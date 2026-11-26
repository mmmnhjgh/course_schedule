package io.github.mmmnhjgh.courseschedule

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class CourseWidgetRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        CourseWidgetData.refreshAllWidgets(context)
    }
}
