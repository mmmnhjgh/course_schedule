import '../models/course.dart';

class ImportMatchConflict {
  final int incomingIndex;
  final Course incoming;
  final Map<int, Course> candidates;

  const ImportMatchConflict(this.incomingIndex, this.incoming, this.candidates);
}

/// 三方合并预览差异。
class ImportMergeDiff {
  final List<Course> added;
  final List<({Course oldCourse, Course updatedCourse})> changed;
  final List<Course> protectedKept;
  final List<Course> removed;
  final List<ImportMatchConflict> conflicts;
  final int unchangedCount;
  final List<Course> incomingCourses;
  final Map<int, Course> _changesByIndex;
  final Set<int> _removedIndices;

  const ImportMergeDiff._(
    this._changesByIndex,
    this._removedIndices, {
    required this.added,
    required this.changed,
    required this.protectedKept,
    required this.removed,
    required this.conflicts,
    required this.unchangedCount,
    required this.incomingCourses,
  });
}

enum ImportApplyMode {
  smartMerge('智能合并（推荐）'),
  replaceAll('覆盖当前课表'),
  appendAll('追加到现有课程');

  final String label;
  const ImportApplyMode(this.label);
}

class ImportMergeService {
  static String _name(Course course) =>
      course.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static Object _signature(Course course) => (
    course.identityKey,
    course.weekday,
    course.startSection,
    course.sectionCount,
    ([...course.weeks]..sort()).join(','),
    course.location.trim(),
  );

  /// 所有精确配对先完成，再匹配变动的时段。null 选择表示保留旧课并新增。
  static ImportMergeDiff computeDiff(
    List<Course> existing,
    List<Course> incoming, {
    Map<int, int?> choices = const {},
  }) {
    final oldIndices = {
      for (var index = 0; index < existing.length; index++)
        if (existing[index].source == 'import') index,
    };
    final newIndices = {
      for (var index = 0; index < incoming.length; index++) index,
    };
    final pairs = <int, int>{};

    void matchUnique(Object Function(Course) key) {
      final oldGroups = <Object, List<int>>{};
      final newGroups = <Object, List<int>>{};
      for (final index in oldIndices) {
        oldGroups.putIfAbsent(key(existing[index]), () => []).add(index);
      }
      for (final index in newIndices) {
        newGroups.putIfAbsent(key(incoming[index]), () => []).add(index);
      }
      for (final entry in newGroups.entries) {
        final oldGroup = oldGroups[entry.key];
        if (oldGroup?.length == 1 && entry.value.length == 1) {
          final oldIndex = oldGroup!.single;
          final newIndex = entry.value.single;
          pairs[newIndex] = oldIndex;
          oldIndices.remove(oldIndex);
          newIndices.remove(newIndex);
        }
      }
    }

    matchUnique(_signature);
    matchUnique(
      (course) => (course.identityKey, course.weekday, course.startSection),
    );
    matchUnique((course) => course.identityKey);
    matchUnique(_name);

    final candidates = {
      for (final index in newIndices)
        index: [
          for (final oldIndex in oldIndices)
            if (_name(existing[oldIndex]) == _name(incoming[index])) oldIndex,
        ],
    };
    final retained = <int>{};
    final explicitlyAdded = <int>{};
    for (final entry in choices.entries) {
      final options = candidates[entry.key];
      if (options == null || options.isEmpty) continue;
      final selected = entry.value;
      if (selected == null) {
        explicitlyAdded.add(entry.key);
        retained.addAll(options);
      } else if (options.contains(selected) && oldIndices.remove(selected)) {
        pairs[entry.key] = selected;
        newIndices.remove(entry.key);
      }
    }

    final added = <Course>[];
    final conflicts = <ImportMatchConflict>[];
    for (final index in newIndices) {
      final options = candidates[index]!;
      if (options.isEmpty || explicitlyAdded.contains(index)) {
        added.add(incoming[index]);
      } else {
        conflicts.add(
          ImportMatchConflict(index, incoming[index], {
            for (final oldIndex in options)
              if (oldIndices.contains(oldIndex)) oldIndex: existing[oldIndex],
          }),
        );
      }
    }

    final changed = <({Course oldCourse, Course updatedCourse})>[];
    final protected = <Course>[];
    final changesByIndex = <int, Course>{};
    var unchanged = 0;
    for (final entry in pairs.entries) {
      final old = existing[entry.value];
      final next = incoming[entry.key];
      if (old.userEdited) {
        protected.add(old);
      } else if (_signature(old) == _signature(next)) {
        unchanged++;
      } else {
        final updated = next.copyWith(
          id: old.id,
          colorValue: old.colorValue,
          note: old.note.isNotEmpty ? old.note : next.note,
          canceledWeeks: old.canceledWeeks,
          source: 'import',
        );
        changesByIndex[entry.value] = updated;
        changed.add((oldCourse: old, updatedCourse: updated));
      }
    }
    final unresolvedCandidates = {
      for (final conflict in conflicts) ...conflict.candidates.keys,
    };
    final removedIndices = <int>{};
    for (final index in oldIndices) {
      if (existing[index].userEdited) {
        protected.add(existing[index]);
      } else if (!retained.contains(index) &&
          !unresolvedCandidates.contains(index)) {
        removedIndices.add(index);
      }
    }
    return ImportMergeDiff._(
      changesByIndex,
      removedIndices,
      added: added,
      changed: changed,
      protectedKept: protected,
      removed: [for (final index in removedIndices) existing[index]],
      conflicts: conflicts,
      unchangedCount: unchanged,
      incomingCourses: incoming,
    );
  }

  static List<Course> applyMerge({
    required List<Course> existing,
    required ImportMergeDiff diff,
    required ImportApplyMode mode,
    bool removeMissing = false,
    Iterable<String> reservedIds = const [],
  }) {
    final List<Course> base;
    final List<Course> additions;
    switch (mode) {
      case ImportApplyMode.replaceAll:
        base = [];
        additions = diff.incomingCourses;
      case ImportApplyMode.appendAll:
        base = [...existing];
        additions = diff.incomingCourses;
      case ImportApplyMode.smartMerge:
        if (diff.conflicts.isNotEmpty) {
          throw StateError('请先确认有歧义的课程配对');
        }
        base = [
          for (var index = 0; index < existing.length; index++)
            if (!removeMissing || !diff._removedIndices.contains(index))
              diff._changesByIndex[index] ?? existing[index],
        ];
        additions = diff.added;
    }

    final ids = {...reservedIds, for (final course in base) course.id};
    for (final course in additions) {
      var id = course.id;
      var suffix = 1;
      while (!ids.add(id)) {
        id = '${course.id}_import_${suffix++}';
      }
      base.add(course.copyWith(id: id, source: 'import'));
    }
    return base;
  }
}
