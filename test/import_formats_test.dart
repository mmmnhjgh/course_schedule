import 'package:flutter_test/flutter_test.dart';

import 'package:course_schedule/models/course.dart';
import 'package:course_schedule/models/schedule_config.dart';
import 'package:course_schedule/services/ai_import_service.dart';
import 'package:course_schedule/services/file_import_service.dart';
import 'package:course_schedule/services/import_merge_service.dart';

void main() {
  test('AiImportService extracts fenced JSON and timeSlots cleanly', () {
    const aiReply = '''
好的，这是为您转换后的课表：
```json
{
  "tableName": "2026秋",
  "startDate": "2026-09-07",
  "totalWeeks": 18,
  "timeSlots": [
    { "node": 1, "startTime": "08:00", "endTime": "08:45" },
    { "node": 2, "startTime": "08:55", "endTime": "09:40" }
  ],
  "courses": [
    {
      "name": "计算机网络",
      "day": 2,
      "startNode": 1,
      "step": 2,
      "weeks": [1, 2, 3, 4],
      "teacher": "刘老师",
      "location": "实验楼302"
    }
  ]
}
```
希望对您有帮助！
''';

    final payload = AiImportService.parseAiJson(aiReply);
    expect(payload.totalWeeks, 18);
    expect(payload.semesterStart, DateTime(2026, 9, 7));
    expect(payload.sectionTimes?.length, 2);
    expect(payload.courses.length, 1);
    expect(payload.courses.first.name, '计算机网络');
    expect(payload.courses.first.endSection, 2);
  });

  test('FileImportService parses CSV with BOM and quoted fields', () {
    const csv = '\uFEFF课程名,星期,节次,周次,地点,教师\n'
        '"数据结构\n(重点班)",周三,3-4节,"1-8周(单)",信息楼101,王老师\n';

    final payload = FileImportService.parseCsv(csv);
    expect(payload.courses.length, 1);
    expect(payload.courses.first.weekday, 3);
    expect(payload.courses.first.startSection, 3);
    expect(payload.courses.first.sectionCount, 2);
    expect(payload.courses.first.weeks, [1, 3, 5, 7]);
  });

  test('FileImportService round-trips ICS export and import', () {
    final config = ScheduleConfig(
      semesterStart: DateTime(2026, 9, 7),
      totalWeeks: 16,
      maxSections: 12,
      sectionTimes: ScheduleConfig.defaults().sectionTimes,
    );
    const courses = [
      Course(
        id: 'c1',
        name: '软件工程',
        teacher: '孙老师',
        location: '教C-201',
        weekday: 4,
        startSection: 1,
        sectionCount: 2,
        weeks: [1, 3, 5],
        colorValue: 0xFF42A5F5,
      ),
    ];

    final ics = FileImportService.exportIcs(
      courses: courses,
      config: config,
      scheduleName: '测试课表',
    );
    final reimported = FileImportService.parseIcs(ics, config);
    expect(reimported.courses.length, 1);
    expect(reimported.courses.first.name, '软件工程');
    expect(reimported.courses.first.weekday, 4);
    expect(reimported.courses.first.startSection, 1);
    expect(reimported.courses.first.endSection, 2);
    expect(reimported.courses.first.weeks, [1, 3, 5]);
    expect(reimported.courses.first.colorValue, 0xFF42A5F5);
  });

  test('ImportMergeService protects manual and userEdited courses', () {
    const existing = [
      Course(
        id: 'm1',
        name: '自定义自习',
        weekday: 5,
        startSection: 9,
        sectionCount: 2,
        weeks: [1, 2, 3],
        colorValue: 0xFF66BB6A,
        source: 'manual',
      ),
      Course(
        id: 'i1',
        name: '高等数学',
        teacher: '张老师',
        location: '我改过的教室',
        weekday: 1,
        startSection: 1,
        sectionCount: 2,
        weeks: [1, 2, 3],
        colorValue: 0xFF42A5F5,
        source: 'import',
        userEdited: true,
      ),
      Course(
        id: 'i2',
        name: '大学英语',
        teacher: '陈老师',
        location: '旧教室',
        weekday: 2,
        startSection: 3,
        sectionCount: 2,
        weeks: [1, 2],
        colorValue: 0xFFFFA726,
        source: 'import',
      ),
    ];

    const incoming = [
      Course(
        id: 'new_1',
        name: '高等数学',
        teacher: '张老师',
        location: '教务原教室',
        weekday: 1,
        startSection: 1,
        sectionCount: 2,
        weeks: [1, 2, 3],
        colorValue: 0xFF42A5F5,
        source: 'import',
      ),
      Course(
        id: 'new_2',
        name: '大学英语',
        teacher: '陈老师',
        location: '新教室205',
        weekday: 2,
        startSection: 3,
        sectionCount: 2,
        weeks: [1, 2],
        colorValue: 0xFFFFA726,
        source: 'import',
      ),
      Course(
        id: 'new_3',
        name: '体育',
        weekday: 3,
        startSection: 5,
        sectionCount: 2,
        weeks: [1, 2, 3, 4],
        colorValue: 0xFFEC407A,
        source: 'import',
      ),
    ];

    final diff = ImportMergeService.computeDiff(existing, incoming);
    expect(diff.protectedKept.length, 1);
    expect(diff.changed.length, 1);
    expect(diff.added.length, 1);

    final merged = ImportMergeService.applyMerge(
      existing: existing,
      diff: diff,
      mode: ImportApplyMode.smartMerge,
    );
    expect(merged.length, 4);
    expect(merged.any((c) => c.id == 'm1'), isTrue);
    expect(merged.firstWhere((c) => c.id == 'i1').location, '我改过的教室');
    expect(merged.firstWhere((c) => c.id == 'i2').location, '新教室205');
    expect(merged.any((c) => c.name == '体育'), isTrue);
  });
}
