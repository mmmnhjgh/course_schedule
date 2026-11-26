import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../models/schedule_config.dart';
import '../models/schedule_profile.dart';
import 'schedule_occurrences.dart';

/// 负责将当前激活课表同步到 Android 原生桌面小组件，并支持一键添加小组件与卡片跳转
class WidgetSyncService {
  static const MethodChannel _channel =
      MethodChannel('io.github.mmmnhjgh.courseschedule/widget');

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// 构建发送给 Android 原生端的精简 JSON 数据
  static Map<String, dynamic> buildSyncPayload(ScheduleProfile profile) {
    final config = profile.config;
    final days = <String, List<Map<String, Object?>>>{};
    for (final item in ScheduleOccurrences(profile).all) {
      final course = item.course;
      days.putIfAbsent(ScheduleConfig.dateKey(item.date), () => []).add({
        'name': course.name,
        'location': course.location,
        'startSection': course.startSection,
        'sectionCount': course.sectionCount,
        'colorValue': course.colorValue,
      });
    }
    return {
      'version': 2,
      'semesterStartYmd': ScheduleConfig.dateKey(config.firstMonday),
      'totalWeeks': config.totalWeeks,
      'sectionTimes': config.sectionTimes.map((time) => time.toJson()).toList(),
      'days': days,
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

  static Future<void> refreshWidgets() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('refreshWidgets');
    } on MissingPluginException {
      // 桌面桥接可能尚未初始化。
    } on PlatformException {
      // 系统定时刷新可接续。
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
  static void setOnOpenTabListener(void Function(int tabIndex)? onOpenTab) {
    if (!_isAndroid) return;
    if (onOpenTab == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
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
