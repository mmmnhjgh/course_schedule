package io.github.mmmnhjgh.courseschedule

import android.app.AlarmManager
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
import java.util.TimeZone

data class WidgetCourseItem(
    val name: String,
    val location: String,
    val startSection: Int,
    val timeRange: String,
    val endMinutes: Int?,
    val colorValue: Int
)

data class TodayWidgetSnapshot(
    val dateLabel: String,
    val weekdayLabel: String,
    val currentWeek: Int?,
    val semesterMessage: String?,
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
        val compactIds = manager.getAppWidgetIds(
            ComponentName(context, CourseWidgetCompactProvider::class.java)
        )
        val now = Calendar.getInstance()
        val snapshot = if (wideIds.isNotEmpty() || compactIds.isNotEmpty()) {
            val raw = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_PAYLOAD, null)
            snapshotFor(raw, now)
        } else {
            null
        }
        if (snapshot != null) {
            if (wideIds.isNotEmpty()) {
                CourseWidgetWideProvider.updateWidgets(context, manager, wideIds, snapshot)
            }
            if (compactIds.isNotEmpty()) {
                CourseWidgetCompactProvider.updateWidgets(context, manager, compactIds, snapshot)
            }
        }
        scheduleNextRefresh(context, now, snapshot)
    }

    private fun scheduleNextRefresh(
        context: Context,
        now: Calendar,
        snapshot: TodayWidgetSnapshot?
    ) {
        val alarm = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = Intent(context, CourseWidgetRefreshReceiver::class.java)
            .setAction(ACTION_WIDGET_REFRESH)
        val pending = PendingIntent.getBroadcast(
            context, 1002, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        if (snapshot?.hasSyncedData != true) {
            alarm.cancel(pending)
            return
        }

        val midnight = (now.clone() as Calendar).apply {
            add(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val nextEnd = snapshot.upcomingCourses.mapNotNull { it.endMinutes }.minOrNull()
        val next = nextEnd?.let { minutes ->
            (now.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, minutes / 60)
                set(Calendar.MINUTE, minutes % 60)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis.takeIf { it > now.timeInMillis }
        }
        alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, minOf(next ?: midnight, midnight), pending)
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

    internal fun snapshotFor(raw: String?, now: Calendar): TodayWidgetSnapshot {
        val year = now.get(Calendar.YEAR)
        val month = now.get(Calendar.MONTH) + 1
        val day = now.get(Calendar.DAY_OF_MONTH)
        val dateLabel = String.format(Locale.US, "%d.%02d", month, day)
        val todayYmd = String.format(Locale.US, "%04d-%02d-%02d", year, month, day)
        val weekday = ((now.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
        val weekdayLabel = weekdayNames[weekday - 1]
        val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val unsynced = TodayWidgetSnapshot(
            dateLabel, weekdayLabel, null, null, 0, emptyList(), false
        )
        if (raw.isNullOrBlank()) return unsynced

        return try {
            val root = JSONObject(raw)
            val totalWeeks = root.optInt("totalWeeks", 20).coerceAtLeast(1)
            val offset = daysSinceFirstMonday(year, month, day, root.getString("semesterStartYmd"))
            val semesterMessage = when {
                offset < 0 -> "学期未开始"
                offset.toLong() >= totalWeeks * 7L -> "学期已结束"
                else -> null
            }
            if (semesterMessage != null) {
                return TodayWidgetSnapshot(
                    dateLabel, weekdayLabel, null, semesterMessage, 0, emptyList(), true
                )
            }
            val week = offset / 7 + 1
            val byDate = root.optInt("version", 1) >= 2
            val courses = if (byDate) {
                root.optJSONObject("days")?.optJSONArray(todayYmd)
            } else {
                root.optJSONArray("courses")
            }
            val times = root.optJSONArray("sectionTimes")
            val today = mutableListOf<WidgetCourseItem>()
            for (index in 0 until (courses?.length() ?: 0)) {
                val item = courses?.optJSONObject(index) ?: continue
                if (!byDate && (item.optInt("weekday") != weekday ||
                        week !in parseIntSet(item.optJSONArray("weeks")) ||
                        week in parseIntSet(item.optJSONArray("canceledWeeks")))) {
                    continue
                }
                val start = item.optInt("startSection", 1).coerceAtLeast(1)
                val end = start + item.optInt("sectionCount", 1).coerceAtLeast(1) - 1
                val startClock = times?.optJSONObject(start - 1)?.optString("start")
                val endClock = times?.optJSONObject(end - 1)?.optString("end")
                val startMinutes = parseMinutes(startClock)
                val endMinutes = parseMinutes(endClock)
                val hasTime = startMinutes != null && endMinutes != null && startMinutes < endMinutes
                today.add(
                    WidgetCourseItem(
                        name = item.optString("name"),
                        location = item.optString("location"),
                        startSection = start,
                        timeRange = if (hasTime) "$startClock - $endClock" else "第$start-${end}节",
                        endMinutes = if (hasTime) endMinutes else null,
                        colorValue = item.optLong("colorValue", 0xFF42A5F5L).toInt()
                    )
                )
            }
            today.sortWith(compareBy<WidgetCourseItem> { it.startSection }.thenBy { it.name })
            val upcoming = today.filter { it.endMinutes == null || it.endMinutes > nowMinutes }
            TodayWidgetSnapshot(dateLabel, weekdayLabel, week, null, today.size, upcoming, true)
        } catch (_: Exception) {
            unsynced
        }
    }

    private fun daysSinceFirstMonday(year: Int, month: Int, day: Int, startYmd: String): Int {
        val fields = startYmd.split('-')
        require(fields.size == 3)
        val utc = TimeZone.getTimeZone("UTC")
        val monday = Calendar.getInstance(utc, Locale.US).apply {
            clear()
            isLenient = false
            set(fields[0].toInt(), fields[1].toInt() - 1, fields[2].toInt())
            add(Calendar.DAY_OF_MONTH, -((get(Calendar.DAY_OF_WEEK) + 5) % 7))
        }
        val today = Calendar.getInstance(utc, Locale.US).apply {
            clear()
            set(year, month - 1, day)
        }
        return ((today.timeInMillis - monday.timeInMillis) / 86_400_000L).toInt()
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
        return if (h in 0..23 && m in 0..59) h * 60 + m else null
    }
}
