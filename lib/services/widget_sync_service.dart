import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../models/schedule_profile.dart';

/// 负责将当前激活课表同步到 Android 原生桌面小组件，并支持一键添加小组件与卡片跳转
class WidgetSyncService {
  static const MethodChannel _channel =
      MethodChannel('io.github.mmmnhjgh.courseschedule/widget');

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// 构建发送给 Android 原生端的精简 JSON 数据
  static Map<String, dynamic> buildSyncPayload(ScheduleProfile profile) {
    final s = profile.config.semesterStart;
    final startYmd =
        '${s.year.toString().padLeft(4, '0')}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}';
    return {
      'profileName': profile.name,
      'semesterStartYmd': startYmd,
      'totalWeeks': profile.config.totalWeeks,
      'maxSections': profile.config.maxSections,
      'sectionTimes': profile.config.sectionTimes
          .map((t) => {'start': t.start, 'end': t.end})
          .toList(),
      'courses': profile.courses
          .map(
            (c) => {
              'id': c.id,
              'name': c.name,
              'teacher': c.teacher,
              'location': c.location,
              'weekday': c.weekday,
              'startSection': c.startSection,
              'sectionCount': c.sectionCount,
              'weeks': c.weeks,
              'canceledWeeks': c.canceledWeeks,
              'colorValue': c.colorValue,
            },
          )
          .toList(),
    };
  }

  /// 同步课表数据至 Android SharedPreferences 并立即刷新桌面小组件
  static Future<void> syncProfile(ScheduleProfile profile) async {
    if (!_isAndroid) return;
    try {
      final payload = jsonEncode(buildSyncPayload(profile));
      await _channel.invokeMethod<void>(
        'syncSchedule',
        {'payload': payload},
      );
    } on MissingPluginException {
      // 测试环境或非 Android 平台静默跳过
    } on PlatformException {
      // 忽略原生通道异常，不影响主应用正常使用
    }
  }

  /// 向系统桌面发出添加请求。返回值表示请求是否已发送，小组件由桌面添加。
  static Future<bool> requestPinWidget(String widgetType) async {
    if (!_isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'requestPinWidget',
        {'type': widgetType},
      );
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 读取并消费点击桌面小组件启动时附带的目标标签页索引（如 0 代表「今日」）
  static Future<int?> consumeInitialTab() async {
    if (!_isAndroid) return null;
    try {
      return await _channel.invokeMethod<int>('consumeInitialTab');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 注册热启动监听：App 在后台时点击桌面小组件可切到指定标签页
  static void setOnOpenTabListener(void Function(int tabIndex) onOpenTab) {
    if (!_isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openTab') {
        final tab = call.arguments;
        if (tab is int) {
          onOpenTab(tab);
        }
      }
    });
  }
}
