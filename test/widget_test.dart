import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:course_schedule/main.dart';
import 'package:course_schedule/models/course.dart';
import 'package:course_schedule/models/schedule_config.dart';
import 'package:course_schedule/models/schedule_profile.dart';
import 'package:course_schedule/pages/settings_page.dart';
import 'package:course_schedule/services/storage_service.dart';
import 'package:course_schedule/services/web_parser_service.dart';
import 'package:course_schedule/services/widget_sync_service.dart';
import 'package:course_schedule/widgets/course_edit_sheet.dart';

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

    final zfOpts = WebParserService.buildZfTermOptions(
      (
        xnm: ['2031', '2030', '2029', '2026', '2025', '2024'],
        xqm: ['', 'all', '16', '3', '12'],
        selXnm: '2026',
        selXqm: '3',
      ),
      referenceYear: 2026,
    );
    expect(zfOpts.first, (xnm: '2026', xqm: '3'));
    expect(zfOpts.any((o) => o.xnm == '2031'), isFalse);
    expect(zfOpts.any((o) => o.xqm.isEmpty || o.xqm == 'all'), isFalse);
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

    final reimported = ScheduleLibrary.fromBackup(jsonDecode(loaded.encode()));
    expect(reimported.profiles.single.courses.length, 1);
    expect(reimported.profiles.single.courses.first.name, '线性代数');
  });

  testWidgets('CourseScheduleApp renders navigation tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CourseScheduleApp());
    await tester.pumpAndSettle();

    expect(find.text('今日'), findsOneWidget);
    expect(find.text('周课表'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('Desktop widget picker keeps manual instructions after a request',
      (tester) async {
    final profile = ScheduleProfile(
      id: 'profile',
      name: '测试课表',
      config: ScheduleConfig.defaults(),
      courses: const [],
    );
    final wideRequest = Completer<bool>();
    final requests = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          profiles: [profile],
          activeProfile: profile,
          onSwitchProfile: (_) {},
          onCreateProfile: (_) {},
          onRenameActiveProfile: (_) {},
          onDeleteActiveProfile: () {},
          onUpdateConfig: (_) {},
          onRequestPinWidget: (type) {
            requests.add(type);
            return type == 'wide' ? wideRequest.future : Future.value(false);
          },
          onOpenWebImport: () {},
          onOpenAiImport: () {},
          onImportFile: () {},
          onExportIcsShare: () {},
          onExportJson: () => '',
          onImportJson: (_) {},
          onLoadSampleCourses: () {},
          onClearAllCourses: () {},
          onRestoreBackup: () {},
          onManageAdjustments: () {},
        ),
      ),
    );

    final entry = find.text('桌面小组件');
    await tester.scrollUntilVisible(entry, 180);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    final instructions = find.textContaining('将「全部卡片」滑到底，再点「插件」');
    final wideCard = find.text('今日课表 4×2 宽卡');
    final compactCard = find.text('今日课表 2×2 小卡');
    expect(instructions, findsOneWidget);

    await tester.tap(wideCard);
    await tester.pump();
    expect(find.textContaining('正在向系统桌面发送'), findsOneWidget);
    await tester.tap(compactCard);
    expect(requests, ['wide']);

    wideRequest.complete(true);
    await tester.pumpAndSettle();
    expect(find.textContaining('已发送添加请求'), findsOneWidget);
    expect(instructions, findsOneWidget);

    await tester.tap(compactCard);
    await tester.pumpAndSettle();
    expect(requests, ['wide', 'compact']);
    expect(find.textContaining('一键添加暂不可用'), findsOneWidget);
    expect(instructions, findsOneWidget);
  });

  test('WidgetSyncService builds complete Android widget JSON payload', () {
    final profile = ScheduleProfile(
      id: 'p1',
      name: '2026秋主修',
      config: ScheduleConfig(
        semesterStart: DateTime(2026, 9, 7),
        totalWeeks: 18,
        maxSections: 12,
        sectionTimes: ScheduleConfig.defaultSectionTimes(),
      ),
      courses: const [
        Course(
          id: 'c1',
          name: '模拟电子技术',
          teacher: '魏红彦',
          location: '本部综合楼302',
          weekday: 2,
          startSection: 1,
          sectionCount: 2,
          weeks: [1, 2, 3],
          canceledWeeks: [2],
          colorValue: 0xFF66BB6A,
        ),
      ],
    );

    final payload = WidgetSyncService.buildSyncPayload(profile);
    expect(payload['semesterStartYmd'], '2026-09-07');
    expect(payload['totalWeeks'], 18);
    expect((payload['sectionTimes'] as List).length, 12);
    final days = payload['days'] as Map<String, dynamic>;
    expect(days.keys, ['2026-09-08', '2026-09-22']);
    expect(days['2026-09-08'].single['name'], '模拟电子技术');
  });

  testWidgets('CourseEditSheet shows live time preview and submits course',
      (tester) async {
    CourseEditResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showCourseEditSheet(
                  context,
                  initialWeekday: 1,
                  initialStartSection: 1,
                  totalWeeks: 20,
                  maxSections: 12,
                  sectionTimes: ScheduleConfig.defaultSectionTimes(),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('周一 第 1-2 节 · 08:00 - 09:40'), findsOneWidget);
    expect(find.text('确认添加'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '电路分析');
    await tester.tap(find.text('单周'));
    await tester.pumpAndSettle();
    expect(find.text('1-19周(单)'), findsOneWidget);

    await tester.tap(find.text('确认添加'));
    await tester.pumpAndSettle();

    expect(result?.course?.name, '电路分析');
    expect(result?.course?.weeks.length, 10);
    expect(result?.course?.weeks.first, 1);
  });
}
