import '../models/course.dart';

/// 单条变更分类
enum MergeItemKind {
  added,
  changed,
  protectedKept,
  removed,
}

/// 三方合并预览差异
class ImportMergeDiff {
  final List<Course> added;
  final List<({Course oldCourse, Course updatedCourse})> changed;
  final List<Course> protectedKept;
  final List<Course> removed;
  final int unchangedCount;
  final List<Course> incomingCourses;

  const ImportMergeDiff({
    required this.added,
    required this.changed,
    required this.protectedKept,
    required this.removed,
    required this.unchangedCount,
    required this.incomingCourses,
  });
}

/// 落盘导入模式
enum ImportApplyMode {
  smartMerge('智能合并（推荐）'),
  replaceAll('覆盖当前课表'),
  appendAll('追加到现有课程');

  final String label;
  const ImportApplyMode(this.label);
}

/// 智能三方合并服务：保留手动课程与用户编辑过的导入课程
class ImportMergeService {
  static String _courseSignature(Course c) {
    final sortedWeeks = [...c.weeks]..sort();
    return '${c.weekday}:${c.startSection}-${c.endSection}:${sortedWeeks.join(",")}:${c.location}:${c.teacher}';
  }

  /// 计算本次导入相对于现有课程的差异
  static ImportMergeDiff computeDiff(
    List<Course> existing,
    List<Course> incoming,
  ) {
    final importedExisting =
        existing.where((c) => c.source == 'import').toList();
    final unmatchedExisting = [...importedExisting];

    final added = <Course>[];
    final changed = <({Course oldCourse, Course updatedCourse})>[];
    final protectedKept = <Course>[];
    var unchangedCount = 0;

    for (final inc in incoming) {
      // 1. 优先按 identityKey + weekday + startSection 精确配对（解决同一门课一周上多次）
      var matchIdx = unmatchedExisting.indexWhere(
        (ex) =>
            ex.identityKey == inc.identityKey &&
            ex.weekday == inc.weekday &&
            ex.startSection == inc.startSection,
      );
      // 2. 退回同 identityKey 配对
      if (matchIdx < 0) {
        matchIdx = unmatchedExisting.indexWhere(
          (ex) => ex.identityKey == inc.identityKey,
        );
      }
      // 3. 退回仅课程名一致（老师可能变动或之前缺失）
      if (matchIdx < 0) {
        final incName = inc.name.trim().toLowerCase();
        matchIdx = unmatchedExisting.indexWhere(
          (ex) => ex.name.trim().toLowerCase() == incName,
        );
      }

      if (matchIdx < 0) {
        added.add(inc.copyWith(source: 'import'));
        continue;
      }

      final old = unmatchedExisting.removeAt(matchIdx);
      if (old.userEdited) {
        protectedKept.add(old);
        continue;
      }

      if (_courseSignature(old) == _courseSignature(inc)) {
        unchangedCount++;
      } else {
        changed.add((
          oldCourse: old,
          updatedCourse: inc.copyWith(
            id: old.id,
            colorValue: old.colorValue,
            note: old.note.isNotEmpty ? old.note : inc.note,
            canceledWeeks: old.canceledWeeks,
            source: 'import',
          ),
        ));
      }
    }

    return ImportMergeDiff(
      added: added,
      changed: changed,
      protectedKept: protectedKept,
      removed: unmatchedExisting,
      unchangedCount: unchangedCount,
      incomingCourses: incoming,
    );
  }

  /// 按指定模式生成合并后的最终课程列表
  static List<Course> applyMerge({
    required List<Course> existing,
    required ImportMergeDiff diff,
    required ImportApplyMode mode,
    bool removeMissing = false,
  }) {
    if (mode == ImportApplyMode.replaceAll) {
      return diff.incomingCourses
          .map((c) => c.copyWith(source: 'import'))
          .toList();
    }

    if (mode == ImportApplyMode.appendAll) {
      return [
        ...existing,
        ...diff.incomingCourses.map((c) => c.copyWith(source: 'import')),
      ];
    }

    // 智能合并：保留全部手动课程 + 受保护课程 + 未变化导入课程 + 已更新导入课程 + 新增课程
    final changedById = <String, Course>{
      for (final pair in diff.changed) pair.oldCourse.id: pair.updatedCourse,
    };
    final removedIds = removeMissing
        ? diff.removed.map((e) => e.id).toSet()
        : <String>{};

    final next = <Course>[];
    for (final old in existing) {
      if (removedIds.contains(old.id)) continue;
      if (changedById.containsKey(old.id)) {
        next.add(changedById[old.id]!);
      } else {
        next.add(old);
      }
    }
    next.addAll(diff.added);
    return next;
  }
}
