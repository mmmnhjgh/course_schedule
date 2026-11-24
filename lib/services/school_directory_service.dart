import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'edu_parsers.dart';

/// 高校教务入口记录
class SchoolEntry {
  final String name;
  final String rawSystem;
  final String url;

  const SchoolEntry({
    required this.name,
    required this.rawSystem,
    required this.url,
  });

  WebAcademicType get academicType {
    final lower = rawSystem.toLowerCase();
    if (lower.startsWith('zhengfang')) return WebAcademicType.zhengfangNew;
    if (lower.startsWith('qiangzhi')) return WebAcademicType.qiangzhi;
    return WebAcademicType.auto;
  }

  String get systemLabel {
    return switch (rawSystem.toLowerCase()) {
      'zhengfang_new' => '正方教务',
      'qiangzhi' || 'qiangzhi_old' => '强智教务',
      'kingosoft' || 'kingosoft_new' => '青果教务',
      'urp' || 'urp_new' => 'URP 教务',
      'wisedu' => '金智教务',
      _ => '网页教务',
    };
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'rawSystem': rawSystem,
        'url': url,
      };

  factory SchoolEntry.fromJson(Map<String, dynamic> json) {
    return SchoolEntry(
      name: json['name'] as String? ?? '',
      rawSystem: json['rawSystem'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }
}

/// 负责从本地 assets 加载全国高校教务索引，并记录最近使用学校
class SchoolDirectoryService {
  static const _recentKey = 'recent_edu_schools_v1';
  static List<SchoolEntry>? _cached;

  Future<List<SchoolEntry>> loadSchools() async {
    if (_cached != null) return _cached!;
    try {
      final raw = await rootBundle.loadString('assets/schools.json');
      final list = jsonDecode(raw) as List<dynamic>;
      _cached = list
          .whereType<List<dynamic>>()
          .where((row) => row.length >= 3)
          .map(
            (row) => SchoolEntry(
              name: row[0].toString().trim(),
              rawSystem: row[1].toString().trim(),
              url: row[2].toString().trim(),
            ),
          )
          .where((e) => e.name.isNotEmpty && e.url.startsWith('http'))
          .toList();
      return _cached!;
    } catch (_) {
      return [];
    }
  }

  Future<List<SchoolEntry>> search(String query, {int limit = 25}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final all = await loadSchools();
    final starts = <SchoolEntry>[];
    final contains = <SchoolEntry>[];
    for (final s in all) {
      final nameLower = s.name.toLowerCase();
      if (nameLower.startsWith(q)) {
        starts.add(s);
      } else if (nameLower.contains(q) || s.url.toLowerCase().contains(q)) {
        contains.add(s);
      }
      if (starts.length + contains.length >= limit) break;
    }
    return [...starts, ...contains].take(limit).toList();
  }

  Future<List<SchoolEntry>> loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SchoolEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> remember(SchoolEntry entry) async {
    final current = await loadRecent();
    final updated = [
      entry,
      ...current.where((e) => e.url != entry.url),
    ].take(6).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recentKey,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }
}
