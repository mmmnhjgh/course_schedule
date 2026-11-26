import 'dart:convert';

import 'package:course_schedule/main.dart';
import 'package:course_schedule/models/course.dart';
import 'package:course_schedule/models/course_adjustment.dart';
import 'package:course_schedule/models/schedule_config.dart';
import 'package:course_schedule/models/schedule_profile.dart';
import 'package:course_schedule/pages/today_page.dart';
import 'package:course_schedule/services/ai_import_service.dart';
import 'package:course_schedule/services/file_import_service.dart';
import 'package:course_schedule/services/import_merge_service.dart';
import 'package:course_schedule/services/schedule_occurrences.dart';
import 'package:course_schedule/services/storage_service.dart';
import 'package:course_schedule/services/widget_sync_service.dart';
import 'package:course_schedule/widgets/import_preview_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _config = ScheduleConfig(
  semesterStart: DateTime(2026, 9, 7),
  totalWeeks: 2,
  maxSections: 12,
  sectionTimes: ScheduleConfig.defaultSectionTimes(),
  showWeekend: false,
  themeMode: 'dark',
  themeColorValue: 0xFF166452,
);

Course _course(String id, int weekday, {bool edited = false}) => Course(
  id: id,
  name: '离散数学',
  teacher: '张老师',
  weekday: weekday,
  startSection: 1,
  sectionCount: 2,
  weeks: const [1, 2],
  colorValue: 0xFF22AA77,
  location: 'A101',
  source: 'import',
  userEdited: edited,
);

ScheduleProfile _profile(String id, List<Course> courses) =>
    ScheduleProfile(id: id, name: '秋季课表', courses: courses, config: _config);

void main() {
  test('Exact matches survive reordered import with a rescheduled session', () {
    final old = [_course('mon', 1, edited: true), _course('wed', 3)];
    final monday = _course('new-mon', 1);
    final tuesday = _course('moved', 2).copyWith(location: 'B202');
    for (final incoming in [
      [tuesday, monday],
      [monday, tuesday],
    ]) {
      final diff = ImportMergeService.computeDiff(old, incoming);
      expect(diff.conflicts, isEmpty);
      final result = ImportMergeService.applyMerge(
        existing: old,
        diff: diff,
        mode: ImportApplyMode.smartMerge,
      );
      expect(result.map((item) => (item.id, item.weekday, item.location)), [
        ('mon', 1, 'A101'),
        ('wed', 2, 'B202'),
      ]);
    }
  });

  test(
    'Ambiguous links require a decision and adding preserves the old options',
    () {
      final old = [_course('mon', 1), _course('wed', 3)];
      final incoming = [_course('new-tue', 2)];
      final pending = ImportMergeService.computeDiff(old, incoming);
      expect(pending.conflicts.single.candidates.keys, [0, 1]);
      expect(
        () => ImportMergeService.applyMerge(
          existing: old,
          diff: pending,
          mode: ImportApplyMode.smartMerge,
        ),
        throwsStateError,
      );

      final add = ImportMergeService.computeDiff(
        old,
        incoming,
        choices: {0: null},
      );
      final all = ImportMergeService.applyMerge(
        existing: old,
        diff: add,
        mode: ImportApplyMode.smartMerge,
        removeMissing: true,
      );
      expect(all.map((item) => item.id), ['mon', 'wed', 'new-tue']);

      final link = ImportMergeService.computeDiff(
        old,
        incoming,
        choices: {0: 1},
      );
      expect(link.changed.single.updatedCourse.id, 'wed');
      expect(link.changed.single.updatedCourse.weekday, 2);
    },
  );

  test('v2 storage migrates as a full library and v3 restores independent profiles', () async {
    final first = _profile('first', [_course('mon', 1)]);
    final second = _profile('second', [
      _course('wed', 3).copyWith(canceledWeeks: [2], source: 'manual'),
    ]);
    SharedPreferences.setMockInitialValues({
      'saved_profiles_v2': jsonEncode([first.toJson(), second.toJson()]),
      'active_profile_id_v2': second.id,
    });
    final storage = StorageService();
    final loaded = await storage.loadAllProfiles();
    expect(loaded.activeId, 'second');
    final moved = CourseAdjustment(
      course: _course('makeup', 4).copyWith(location: 'N306'),
      date: DateTime(2026, 9, 10),
    );
    final backup = ScheduleLibrary(
      profiles: [
        first.copyWith(adjustments: [moved]),
        second,
      ],
      activeId: second.id,
    );
    final decoded = FileImportService.parseJsonInput(
      backup.encode(),
      _config,
    ).backup!;
    final restored = loaded.withRestored(decoded);
    expect(restored.profiles.take(2), loaded.profiles);
    expect(restored.profiles.length, 4);
    expect(restored.profiles.map((item) => item.id).toSet(), hasLength(4));
    expect(restored.profiles.map((item) => item.name).toSet(), hasLength(3));
    expect(restored.activeId, restored.profiles.last.id);
    expect(restored.profiles[2].adjustments.single.course.location, 'N306');
    expect(restored.profiles.last.config.themeMode, 'dark');
    expect(restored.profiles.last.config.showWeekend, isFalse);
    expect(restored.profiles.last.config.themeColorValue, 0xFF166452);
    expect(restored.profiles.last.courses.single.canceledWeeks, [2]);
    expect(restored.profiles.last.courses.single.source, 'manual');

    await storage.saveAllProfiles(
      profiles: restored.profiles,
      activeId: restored.activeId,
    );
    expect((await storage.loadAllProfiles()).encode(), restored.encode());
  });

  test(
    'Unreadable current data is preserved before explicit recovery',
    () async {
      final previous = ScheduleLibrary(
        profiles: [
          _profile('p', [_course('c', 2)]),
        ],
        activeId: 'p',
      );
      const damaged = '{"version":3,"profiles":[broken';
      SharedPreferences.setMockInitialValues({
        'schedule_library_v3': damaged,
        'schedule_library_v3_previous': previous.encode(),
      });
      final storage = StorageService();
      ScheduleRecoveryRequired? issue;
      try {
        await storage.loadAllProfiles();
      } on ScheduleRecoveryRequired catch (error) {
        issue = error;
      }
      expect(issue?.raw, damaged);
      expect(issue?.previous?.encode(), previous.encode());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('schedule_library_v3'), damaged);

      await storage.saveAllProfiles(
        profiles: previous.profiles,
        activeId: previous.activeId,
        recovery: issue!,
      );
      expect((await storage.loadAllProfiles()).encode(), previous.encode());
      expect(prefs.getString('schedule_library_v3_recovery'), damaged);
    },
  );

  test('Old single-profile JSON restores the full configuration and retains course source', () {
    final backup = FileImportService.parseJsonInput(
      jsonEncode({
        'version': 2,
        'config': _config.toJson(),
        'courses': [_course('original', 1).copyWith(source: 'manual').toJson()],
      }),
      _config,
    ).backup!;
    final profile = backup.profiles.single;
    expect(profile.config.toJson(), _config.toJson());
    expect(profile.courses.single.source, 'manual');

    final invalid = jsonDecode(backup.encode()) as Map<String, dynamic>;
    invalid['activeId'] = 'missing';
    expect(() => ScheduleLibrary.fromBackup(invalid), throwsFormatException);
  });

  test('Actual dates, class sections and rooms agree in the app, widget payload and ICS', () {
    final repeated = _course('mon', 1);
    final move = CourseAdjustment(
      course: repeated.copyWith(id: 'move', location: '新楼301', startSection: 3),
      date: DateTime(2026, 9, 8),
      originalCourseId: repeated.id,
      originalDate: DateTime(2026, 9, 7),
    );
    final extra = CourseAdjustment(
      course: repeated.copyWith(id: 'makeup', location: '补课教室'),
      date: DateTime(2026, 9, 21),
    );
    final profile = _profile('p', [
      repeated,
    ]).copyWith(adjustments: [move, extra]);
    final timetable = ScheduleOccurrences(profile);
    expect(timetable.onDate(DateTime(2026, 9, 7)), isEmpty);
    expect(timetable.onDate(DateTime(2026, 8, 31)), isEmpty);
    expect(timetable.onDate(DateTime(2026, 9, 21)), isEmpty);
    expect(timetable.isValidTarget(extra), isFalse);
    expect(
      timetable.onDate(DateTime(2026, 9, 8)).single.course.location,
      '新楼301',
    );
    expect(
      timetable.onDate(DateTime(2026, 9, 14)).single.course.location,
      'A101',
    );
    expect(_config.semesterMessage(DateTime(2026, 8, 31)), '学期未开始');
    expect(_config.semesterMessage(DateTime(2026, 9, 21)), '学期已结束');

    final widgetDays =
        WidgetSyncService.buildSyncPayload(profile)['days'] as Map;
    expect(widgetDays.keys, ['2026-09-08', '2026-09-14']);
    expect(widgetDays['2026-09-08'].single['location'], '新楼301');
    expect(widgetDays['2026-09-08'].single['startSection'], 3);

    final ics = FileImportService.exportIcs(
      courses: profile.courses,
      config: profile.config,
      adjustments: profile.adjustments,
    );
    expect(ics, contains('UID:mon-w1@qingkebiao'));
    expect(ics, contains('DTSTART:20260908T100000'));
    expect(ics, contains('LOCATION:新楼301'));
    expect(ics, isNot(contains('DTSTART:20260907')));
    final parsed = FileImportService.parseIcs(ics, _config);
    expect(
      parsed.courses.map(
        (item) => (item.weekday, item.startSection, item.location),
      ),
      [(2, 3, '新楼301'), (1, 1, 'A101')],
    );

    final undo = ScheduleOccurrences(profile.copyWith(adjustments: []));
    expect(undo.onDate(DateTime(2026, 9, 7)).single.course.id, 'mon');
    expect(undo.onDate(DateTime(2026, 9, 8)), isEmpty);
  });

  test('A move outside the available lessons keeps the original visible', () {
    final original = _course('mon', 1);
    final outside = CourseAdjustment(
      course: original.copyWith(id: 'new', startSection: 11),
      date: DateTime(2026, 9, 8),
      originalCourseId: 'mon',
      originalDate: DateTime(2026, 9, 7),
    );
    final profile = _profile('p', [original]).copyWith(
      config: _config.copyWith(maxSections: 10),
      adjustments: [outside],
    );
    expect(
      ScheduleOccurrences(profile).onDate(DateTime(2026, 9, 7)).single.course,
      original,
    );
    expect(ScheduleOccurrences(profile).onDate(DateTime(2026, 9, 8)), isEmpty);
  });

  testWidgets(
    'Today switches at the class end and shows the semester boundary',
    (tester) async {
      final profile = _profile('p', [_course('mon', 1)]);
      Future<void> show(DateTime now) => tester.pumpWidget(
        MaterialApp(
          home: TodayPage(
            profile: profile,
            now: now,
            onTapCourse: (_, _) {},
            onAddCourse: () {},
          ),
        ),
      );
      await show(DateTime(2026, 9, 7, 9, 39));
      expect(find.textContaining('还有 1 分钟下课'), findsOneWidget);
      await show(DateTime(2026, 9, 7, 9, 40));
      expect(find.text('今日课程已全部结束'), findsOneWidget);
      await show(DateTime(2026, 9, 21, 8));
      expect(find.text('学期已结束'), findsOneWidget);
      expect(find.text('离散数学'), findsNothing);
    },
  );

  testWidgets('Empty home exposes the first import menu', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CourseScheduleApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入课表'));
    await tester.pumpAndSettle();
    expect(find.text('教务系统网页'), findsOneWidget);
    expect(find.text('课表文件或备份'), findsOneWidget);
    expect(find.text('AI 转换导入'), findsOneWidget);
  });

  testWidgets('Import preview keeps an adjustment whose original class moved', (
    tester,
  ) async {
    final monday = _course('monday', 1);
    final target = DateTime(2026, 9, 9);
    final profile = _profile('p', [monday]).copyWith(
      adjustments: [
        CourseAdjustment(
          course: monday.copyWith(id: 'once', weekday: 3, location: '补课地点'),
          date: target,
          originalCourseId: monday.id,
          originalDate: DateTime(2026, 9, 7),
        ),
      ],
    );
    ScheduleProfile? proposed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                proposed = await showImportPreviewSheet(
                  context,
                  profile: profile,
                  payload: ImportPayload(courses: [_course('new-tue', 2)]),
                );
              },
              child: const Text('查看导入'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('查看导入'));
    await tester.pumpAndSettle();
    expect(find.textContaining('将保留为独立补课'), findsOneWidget);
    await tester.tap(find.text('确认导入'));
    await tester.pumpAndSettle();
    expect(proposed?.courses.single.weekday, 2);
    final retained = proposed!.adjustments.single;
    expect(retained.isMove, isFalse);
    expect(retained.date, target);
    expect(retained.course.location, '补课地点');
  });

  testWidgets(
    'Pasted backup previews and restores a second independent profile',
    (tester) async {
      final original = _profile('original', [_course('here', 2)]);
      SharedPreferences.setMockInitialValues({
        'saved_profiles_v2': jsonEncode([original.toJson()]),
        'active_profile_id_v2': original.id,
      });
      final incoming = ScheduleLibrary(
        profiles: [
          _profile('backup', [_course('there', 3)]),
        ],
        activeId: 'backup',
      );
      await tester.pumpWidget(const CourseScheduleApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      final entry = find.text('粘贴 JSON 导入或恢复');
      await tester.scrollUntilVisible(entry, 240);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), incoming.encode());
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('恢复为新课表'), findsOneWidget);
      expect(find.textContaining('秋季课表（1 门课）'), findsOneWidget);
      await tester.tap(find.text('确认恢复'));
      await tester.pumpAndSettle();
      final restored = await StorageService().loadAllProfiles();
      expect(restored.profiles.length, 2);
      expect(restored.profiles.first.courses.single.id, 'here');
      expect(restored.profiles.last.courses.single.id, 'there');
      expect(restored.activeId, restored.profiles.last.id);
    },
  );

  testWidgets(
    'Makeup can be added from the week view and deleted independently',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const CourseScheduleApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('添加课程'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加一次补课'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '习题补课');
      final button = find.text('保存这次安排');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final saved = await StorageService().loadAllProfiles();
      final profile = saved.profiles.single;
      expect(profile.courses, isEmpty);
      expect(profile.adjustments.single.course.name, '习题补课');
      expect(
        ScheduleOccurrences(profile).all.single.adjustment?.isMove,
        isFalse,
      );

      await tester.tap(find.text('习题补课'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除补课'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除补课'));
      await tester.pumpAndSettle();
      expect(
        (await StorageService().loadAllProfiles()).profiles.single.adjustments,
        isEmpty,
      );
    },
  );
}
