package io.github.mmmnhjgh.courseschedule

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews

class CourseWidgetWideProvider : AppWidgetProvider() {

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
        private val slotIds = intArrayOf(
            R.id.wide_slot_0,
            R.id.wide_slot_1,
            R.id.wide_slot_2,
            R.id.wide_slot_3
        )
        private val bgIds = intArrayOf(
            R.id.wide_bg_0,
            R.id.wide_bg_1,
            R.id.wide_bg_2,
            R.id.wide_bg_3
        )
        private val barIds = intArrayOf(
            R.id.wide_bar_0,
            R.id.wide_bar_1,
            R.id.wide_bar_2,
            R.id.wide_bar_3
        )
        private val titleIds = intArrayOf(
            R.id.wide_title_0,
            R.id.wide_title_1,
            R.id.wide_title_2,
            R.id.wide_title_3
        )
        private val subIds = intArrayOf(
            R.id.wide_sub_0,
            R.id.wide_sub_1,
            R.id.wide_sub_2,
            R.id.wide_sub_3
        )

        fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray,
            snapshot: TodayWidgetSnapshot
        ) {
            val openIntent = CourseWidgetData.createOpenTodayIntent(context)

            for (appWidgetId in appWidgetIds) {
                val views = RemoteViews(context.packageName, R.layout.widget_course_wide)
                views.setOnClickPendingIntent(R.id.widget_wide_root, openIntent)

                views.setTextViewText(
                    R.id.tv_wide_header_left,
                    snapshot.currentWeek?.let { "${snapshot.dateLabel} ${snapshot.weekdayLabel} · 第${it}周" }
                        ?: "${snapshot.dateLabel} ${snapshot.weekdayLabel}"
                )
                views.setTextViewText(
                    R.id.tv_wide_header_right,
                    if (snapshot.totalTodayCount > 0) "共${snapshot.totalTodayCount}节课" else "无课"
                )

                val courses = snapshot.upcomingCourses.take(4)
                if (courses.isEmpty()) {
                    views.setViewVisibility(R.id.layout_wide_grid, View.GONE)
                    views.setViewVisibility(R.id.tv_wide_empty, View.VISIBLE)
                    val emptyText = snapshot.semesterMessage ?: when {
                        !snapshot.hasSyncedData -> "打开「轻课表」同步课程"
                        snapshot.totalTodayCount > 0 -> "今日 ${snapshot.totalTodayCount} 节课已全部结束"
                        else -> "今日无课，好好休息"
                    }
                    views.setTextViewText(R.id.tv_wide_empty, emptyText)
                } else {
                    views.setViewVisibility(R.id.tv_wide_empty, View.GONE)
                    views.setViewVisibility(R.id.layout_wide_grid, View.VISIBLE)
                    views.setViewVisibility(
                        R.id.layout_wide_row2,
                        if (courses.size > 2) View.VISIBLE else View.GONE
                    )

                    for (i in 0 until 4) {
                        if (i < courses.size) {
                            val item = courses[i]
                            views.setViewVisibility(slotIds[i], View.VISIBLE)
                            views.setInt(
                                bgIds[i],
                                "setColorFilter",
                                CourseWidgetData.computeCardTint(context, item.colorValue)
                            )
                            views.setInt(barIds[i], "setColorFilter", item.colorValue)
                            views.setTextViewText(titleIds[i], item.name)
                            val sub = if (item.location.isNotEmpty()) {
                                "${item.timeRange} ${item.location}"
                            } else {
                                item.timeRange
                            }
                            views.setTextViewText(subIds[i], sub)
                        } else {
                            val hiddenState = if (courses.size == 1 && i == 1) View.GONE else View.INVISIBLE
                            views.setViewVisibility(slotIds[i], hiddenState)
                        }
                    }
                }

                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        }
    }
}
