package io.github.mmmnhjgh.courseschedule

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val WIDGET_CHANNEL = "io.github.mmmnhjgh.courseschedule/widget"
    }

    private var widgetChannel: MethodChannel? = null
    private var pendingTargetTab: Int? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureTargetTab(intent, notifyFlutter = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureTargetTab(intent, notifyFlutter = true)
    }

    private fun captureTargetTab(intent: Intent?, notifyFlutter: Boolean) {
        if (intent == null) return
        val tab = intent.getIntExtra(CourseWidgetData.EXTRA_TARGET_TAB, -1)
        if (tab >= 0) {
            intent.removeExtra(CourseWidgetData.EXTRA_TARGET_TAB)
            if (notifyFlutter && widgetChannel != null) {
                widgetChannel?.invokeMethod("openTab", tab)
            } else {
                pendingTargetTab = tab
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WIDGET_CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncSchedule" -> {
                        val payload = call.argument<String>("payload")
                        if (!payload.isNullOrEmpty()) {
                            CourseWidgetData.savePayload(this, payload)
                            CourseWidgetData.refreshAllWidgets(this)
                        }
                        result.success(null)
                    }

                    "requestPinWidget" -> {
                        val type = call.argument<String>("type") ?: "wide"
                        val ok = requestPinDesktopWidget(type)
                        result.success(ok)
                    }

                    "consumeInitialTab" -> {
                        val tab = pendingTargetTab
                        pendingTargetTab = null
                        result.success(tab)
                    }

                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun requestPinDesktopWidget(type: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = AppWidgetManager.getInstance(this)
        if (!manager.isRequestPinAppWidgetSupported) return false
        val providerClass = if (type == "compact") {
            CourseWidgetCompactProvider::class.java
        } else {
            CourseWidgetWideProvider::class.java
        }
        val provider = ComponentName(this, providerClass)
        return manager.requestPinAppWidget(provider, null, null)
    }
}
