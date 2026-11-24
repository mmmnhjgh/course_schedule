import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:course_schedule/main.dart';
import 'package:course_schedule/models/course.dart';
import 'package:course_schedule/models/schedule_config.dart';
import 'package:course_schedule/services/storage_service.dart';
import 'package:course_schedule/services/web_parser_service.dart';

void main() {
  test('Course endSection, overlap, and formatWeeks work correctly', () {
    const c1 = Course(
      id: '1',
      name: '高等数学',
      weekday: 1,
      startSection: 1,
      sectionCount: 2,
      weeks: [1, 2, 3, 4],
      colorValue: 0xFF42A5F5,
    );
    const c2 = Course(
      id: '2',
      name: '物理实验',
      weekday: 1,
      startSection: 2,
      sectionCount: 2,
      weeks: [1, 3, 5, 7],
      colorValue: 0xFF26A69A,
    );
    const c3 = Course(
      id: '3',
      name: '英语听说',
      weekday: 2,
      startSection: 1,
      sectionCount: 2,
      weeks: [2, 4, 6, 8],
      colorValue: 0xFFFFA726,
    );

    expect(c1.endSection, 2);
    expect(c1.formatWeeks(), '1-4周');
    expect(c2.formatWeeks(), '1-7周(单)');
    expect(c3.formatWeeks(), '2-8周(双)');
    expect(c1.overlapsSectionWith(c2), isTrue);
    expect(c1.overlapsSectionWith(c3), isFalse);

    final restored = Course.fromJson(c1.toJson());
    expect(restored.name, '高等数学');
    expect(restored.note, '');
  });

  test('ScheduleConfig calculates current week and serializes new fields', () {
    final config = ScheduleConfig(
      semesterStart: DateTime(2026, 9, 7),
      totalWeeks: 20,
      maxSections: 12,
      sectionTimes: ScheduleConfig.defaults().sectionTimes,
      showWeekend: false,
      themeColorValue: 0xFF26A69A,
      themeMode: 'dark',
    );

    expect(config.getCurrentWeek(DateTime(2026, 9, 7)), 1);
    expect(config.getCurrentWeek(DateTime(2026, 9, 13)), 1);
    expect(config.getCurrentWeek(DateTime(2026, 9, 14)), 2);

    final restored = ScheduleConfig.fromJson(config.toJson());
    expect(restored.showWeekend, isFalse);
    expect(restored.themeColorValue, 0xFF26A69A);
    expect(restored.themeMode, 'dark');
  });

  test('WebParserService parses complex week expressions and WebView payloads', () {
    expect(
      WebParserService.parseWeeksExpression('1-8周(单), 10-12周'),
      [1, 3, 5, 7, 10, 11, 12],
    );
    expect(
      WebParserService.parseWeeksExpression('2-6双周'),
      [2, 4, 6],
    );

    final payload = jsonEncode({
      'ok': true,
      'kbList': [
        {
          'kcmc': '编译原理',
          'xm': '周老师',
          'cdmc': '信息楼-301',
          'xqj': '3',
          'jcs': '3-4',
          'zcd': '1-8周(单)',
        },
        {
          'kcmc': '编译原理',
          'xm': '周老师',
          'cdmc': '信息楼-301',
          'xqj': '3',
          'jcs': '3-4',
          'zcd': '1-8周(单)',
        },
      ],
    });

    // 模拟 Android WebView runJavaScriptReturningResult 返回的双重 JSON 字符串
    final doubleEncoded = jsonEncode(payload);
    final result = WebParserService.parseExtractedPayload(doubleEncoded);
    expect(result.sourceTag, 'zhengfangApi');
    expect(result.courses.length, 1);
    expect(result.courses.first.weeks, [1, 3, 5, 7]);
    expect(result.courses.first.location, '信息楼-301');
  });

  test('StorageService migrates legacy v1 courses and supports JSON roundtrip',
      () async {
    final legacyCourses = [
      const Course(
        id: 'legacy_1',
        name: '线性代数',
        weekday: 4,
        startSection: 1,
        sectionCount: 2,
        weeks: [1, 2, 3],
        colorValue: 0xFF42A5F5,
      ).toJson(),
    ];

    SharedPreferences.setMockInitialValues({
      'saved_courses_v1': jsonEncode(legacyCourses),
    });

    final storage = StorageService();
    final loaded = await storage.loadAllProfiles();
    expect(loaded.profiles.length, 1);
    expect(loaded.profiles.first.courses.length, 1);
    expect(loaded.profiles.first.courses.first.name, '线性代数');

    final exported = storage.exportBackupJson(
      courses: loaded.profiles.first.courses,
      config: loaded.profiles.first.config,
    );
    final reimported = storage.importBackupJson(exported);
    expect(reimported.courses.length, 1);
    expect(reimported.courses.first.name, '线性代数');
  });

  testWidgets('CourseScheduleApp renders navigation tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CourseScheduleApp());
    await tester.pumpAndSettle();

    expect(find.text('今日'), findsOneWidget);
    expect(find.text('周课表'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
