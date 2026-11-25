package io.github.mmmnhjgh.courseschedule

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

data class WidgetCourseItem(
    val name: String,
    val location: String,
    val teacher: String,
    val startSection: Int,
    val endSection: Int,
    val timeRange: String,
    val endMinutes: Int?,
    val colorValue: Int
)

data class TodayWidgetSnapshot(
    val dateLabel: String,
    val weekdayLabel: String,
    val currentWeek: Int,
    val totalTodayCount: Int,
    val upcomingCourses: List<WidgetCourseItem>,
    val hasSyncedData: Boolean
)

object CourseWidgetData {
    private const val PREFS_NAME = "course_widget_prefs"
    private const val KEY_PAYLOAD = "active_schedule_json"

    const val ACTION_WIDGET_REFRESH = "io.github.mmmnhjgh.courseschedule.ACTION_WIDGET_REFRESH"
    const val EXTRA_TARGET_TAB = "target_tab"

    private val weekdayNames = arrayOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")

    fun savePayload(context: Context, payloadJson: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PAYLOAD, payloadJson)
            .apply()
    }

    fun refreshAllWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)

        val wideIds = manager.getAppWidgetIds(
            ComponentName(context, CourseWidgetWideProvider::class.java)
        )
        if (wideIds.isNotEmpty()) {
            CourseWidgetWideProvider.updateWidgets(context, manager, wideIds)
        }

        val compactIds = manager.getAppWidgetIds(
            ComponentName(context, CourseWidgetCompactProvider::class.java)
        )
        if (compactIds.isNotEmpty()) {
            CourseWidgetCompactProvider.updateWidgets(context, manager, compactIds)
        }
    }

    fun createOpenTodayIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_TARGET_TAB, 0)
        }
        return PendingIntent.getActivity(
            context,
            1001,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun computeCardTint(context: Context, courseColor: Int): Int {
        val isNight = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
        val baseColor = if (isNight) Color.parseColor("#262930") else Color.WHITE
        val ratio = if (isNight) 0.24f else 0.13f

        val r = (Color.red(courseColor) * ratio + Color.red(baseColor) * (1f - ratio)).toInt().coerceIn(0, 255)
        val g = (Color.green(courseColor) * ratio + Color.green(baseColor) * (1f - ratio)).toInt().coerceIn(0, 255)
        val b = (Color.blue(courseColor) * ratio + Color.blue(baseColor) * (1f - ratio)).toInt().coerceIn(0, 255)
        return Color.rgb(r, g, b)
    }

    fun loadTodaySnapshot(context: Context): TodayWidgetSnapshot {
        val now = Calendar.getInstance()
        val month = now.get(Calendar.MONTH) + 1
        val day = now.get(Calendar.DAY_OF_MONTH)
        val dateLabel = String.format(Locale.US, "%d.%02d", month, day)
        val todayWeekday = ((now.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
        val weekdayLabel = weekdayNames[(todayWeekday - 1).coerceIn(0, 6)]
        val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)

        val raw = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_PAYLOAD, null)
        if (raw.isNullOrBlank()) {
            return TodayWidgetSnapshot(
                dateLabel = dateLabel,
                weekdayLabel = weekdayLabel,
                currentWeek = 1,
                totalTodayCount = 0,
                upcomingCourses = emptyList(),
                hasSyncedData = false
            )
        }

        return try {
            val root = JSONObject(raw)
            val totalWeeks = root.optInt("totalWeeks", 20).coerceAtLeast(1)
            val startYmd = root.optString("semesterStartYmd", "")
            val currentWeek = computeCurrentWeek(now, startYmd, totalWeeks)

            val sectionTimes = parseSectionTimes(root.optJSONArray("sectionTimes"))
            val coursesJson = root.optJSONArray("courses") ?: JSONArray()

            val todayCourses = mutableListOf<WidgetCourseItem>()
            for (i in 0 until coursesJson.length()) {
                val obj = coursesJson.optJSONObject(i) ?: continue
                val weekday = obj.optInt("weekday", -1)
                if (weekday != todayWeekday) continue

                val weeks = parseIntSet(obj.optJSONArray("weeks"))
                if (!weeks.contains(currentWeek)) continue

                val canceled = parseIntSet(obj.optJSONArray("canceledWeeks"))
                if (canceled.contains(currentWeek)) continue

                val startSec = obj.optInt("startSection", 1).coerceAtLeast(1)
                val count = obj.optInt("sectionCount", 1).coerceAtLeast(1)
                val endSec = startSec + count - 1

                val startClock = sectionTimes.getOrNull(startSec - 1)?.first
                val endClock = sectionTimes.getOrNull(endSec - 1)?.second
                val timeRange = if (!startClock.isNullOrEmpty() && !endClock.isNullOrEmpty()) {
                    "$startClock - $endClock"
                } else {
                    "第$startSec-${endSec}节"
                }
                val endMinutes = parseMinutes(endClock)

                val colorVal = obj.optLong("colorValue", 0xFF42A5F5L).toInt()
                todayCourses.add(
                    WidgetCourseItem(
                        name = obj.optString("name", "").trim(),
                        location = obj.optString("location", "").trim(),
                        teacher = obj.optString("teacher", "").trim(),
                        startSection = startSec,
                        endSection = endSec,
                        timeRange = timeRange,
                        endMinutes = endMinutes,
                        colorValue = colorVal
                    )
                )
            }

            todayCourses.sortWith(compareBy<WidgetCourseItem> { it.startSection }.thenBy { it.name })

            val upcoming = todayCourses.filter { item ->
                item.endMinutes == null || item.endMinutes >= nowMinutes
            }

            TodayWidgetSnapshot(
                dateLabel = dateLabel,
                weekdayLabel = weekdayLabel,
                currentWeek = currentWeek,
                totalTodayCount = todayCourses.size,
                upcomingCourses = upcoming,
                hasSyncedData = true
            )
        } catch (_: Exception) {
            TodayWidgetSnapshot(
                dateLabel = dateLabel,
                weekdayLabel = weekdayLabel,
                currentWeek = 1,
                totalTodayCount = 0,
                upcomingCourses = emptyList(),
                hasSyncedData = false
            )
        }
    }

    private fun computeCurrentWeek(now: Calendar, startYmd: String, totalWeeks: Int): Int {
        val parts = startYmd.split("-")
        if (parts.size != 3) return 1
        val year = parts[0].toIntOrNull() ?: return 1
        val month = parts[1].toIntOrNull() ?: return 1
        val day = parts[2].toIntOrNull() ?: return 1

        val startCal = Calendar.getInstance().apply {
            set(Calendar.YEAR, year)
            set(Calendar.MONTH, month - 1)
            set(Calendar.DAY_OF_MONTH, day)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val todayCal = Calendar.getInstance().apply {
            set(Calendar.YEAR, now.get(Calendar.YEAR))
            set(Calendar.MONTH, now.get(Calendar.MONTH))
            set(Calendar.DAY_OF_MONTH, now.get(Calendar.DAY_OF_MONTH))
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        val diffMillis = todayCal.timeInMillis - startCal.timeInMillis
        val diffDays = Math.round(diffMillis / 86_400_000.0).toInt()
        val week = if (diffDays >= 0) (diffDays / 7) + 1 else 1
        return week.coerceIn(1, totalWeeks)
    }

    private fun parseSectionTimes(array: JSONArray?): List<Pair<String, String>> {
        if (array == null) return emptyList()
        val list = mutableListOf<Pair<String, String>>()
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            list.add(obj.optString("start", "") to obj.optString("end", ""))
        }
        return list
    }

    private fun parseIntSet(array: JSONArray?): Set<Int> {
        if (array == null) return emptySet()
        val set = HashSet<Int>(array.length())
        for (i in 0 until array.length()) {
            set.add(array.optInt(i))
        }
        return set
    }

    private fun parseMinutes(hhmm: String?): Int? {
        if (hhmm.isNullOrBlank()) return null
        val parts = hhmm.split(":")
        if (parts.size != 2) return null
        val h = parts[0].toIntOrNull() ?: return null
        val m = parts[1].toIntOrNull() ?: return null
        return h * 60 + m
    }
}
