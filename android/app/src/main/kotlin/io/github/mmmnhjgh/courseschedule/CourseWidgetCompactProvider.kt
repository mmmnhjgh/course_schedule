package io.github.mmmnhjgh.courseschedule

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews

class CourseWidgetCompactProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        CourseWidgetData.refreshAllWidgets(context)
    }

    override fun onDisabled(context: Context) {
        CourseWidgetData.refreshAllWidgets(context)
    }

    companion object {
        fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray,
            snapshot: TodayWidgetSnapshot
        ) {
            val openIntent = CourseWidgetData.createOpenTodayIntent(context)

            for (appWidgetId in appWidgetIds) {
                val views = RemoteViews(context.packageName, R.layout.widget_course_compact)
                views.setOnClickPendingIntent(R.id.widget_compact_root, openIntent)

                views.setTextViewText(R.id.tv_compact_day, snapshot.weekdayLabel)
                views.setTextViewText(
                    R.id.tv_compact_count,
                    if (snapshot.totalTodayCount > 0) "共${snapshot.totalTodayCount}节课" else "无课"
                )

                val courses = snapshot.upcomingCourses
                if (courses.isEmpty()) {
                    views.setViewVisibility(R.id.layout_compact_content, View.GONE)
                    views.setViewVisibility(R.id.tv_compact_empty, View.VISIBLE)
                    val emptyText = snapshot.semesterMessage ?: when {
                        !snapshot.hasSyncedData -> "打开应用同步"
                        snapshot.totalTodayCount > 0 -> "今日课程已结束"
                        else -> "今日无课"
                    }
                    views.setTextViewText(R.id.tv_compact_empty, emptyText)
                } else {
                    views.setViewVisibility(R.id.tv_compact_empty, View.GONE)
                    views.setViewVisibility(R.id.layout_compact_content, View.VISIBLE)

                    val first = courses[0]
                    views.setInt(
                        R.id.compact_bg_0,
                        "setColorFilter",
                        CourseWidgetData.computeCardTint(context, first.colorValue)
                    )
                    views.setInt(R.id.compact_bar_0, "setColorFilter", first.colorValue)
                    views.setTextViewText(R.id.compact_title_0, first.name)
                    views.setTextViewText(R.id.compact_time_0, first.timeRange)
                    if (first.location.isNotEmpty()) {
                        views.setViewVisibility(R.id.compact_loc_0, View.VISIBLE)
                        views.setTextViewText(R.id.compact_loc_0, first.location)
                    } else {
                        views.setViewVisibility(R.id.compact_loc_0, View.GONE)
                    }

                    if (courses.size >= 2) {
                        val second = courses[1]
                        views.setViewVisibility(R.id.compact_slot_1, View.VISIBLE)
                        views.setInt(
                            R.id.compact_bg_1,
                            "setColorFilter",
                            CourseWidgetData.computeCardTint(context, second.colorValue)
                        )
                        views.setInt(R.id.compact_bar_1, "setColorFilter", second.colorValue)
                        views.setTextViewText(R.id.compact_title_1, second.name)
                    } else {
                        views.setViewVisibility(R.id.compact_slot_1, View.GONE)
                    }
                }

                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        }
    }
}
