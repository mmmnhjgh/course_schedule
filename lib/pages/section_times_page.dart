import 'package:material_ui/material_ui.dart';

import '../models/schedule_config.dart';

/// 自定义每天总节数与每节课上下课时间的页面
class SectionTimesPage extends StatefulWidget {
  final ScheduleConfig config;

  const SectionTimesPage({super.key, required this.config});

  @override
  State<SectionTimesPage> createState() => _SectionTimesPageState();
}

class _SectionTimesPageState extends State<SectionTimesPage> {
  late int _maxSections;
  late List<SectionTime> _times;

  @override
  void initState() {
    super.initState();
    _maxSections = widget.config.maxSections;
    _times = [...widget.config.sectionTimes];
    _ensureLength(_maxSections);
  }

  void _ensureLength(int target) {
    while (_times.length < target) {
      final prevEnd = _times.isNotEmpty ? _times.last.end : '08:00';
      final startMin = _parseMinutes(prevEnd) + 10;
      final endMin = startMin + 45;
      _times.add(
        SectionTime(
          start: _formatMinutes(startMin.clamp(0, 23 * 60 + 59)),
          end: _formatMinutes(endMin.clamp(0, 23 * 60 + 59)),
        ),
      );
    }
  }

  int _parseMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 8 * 60;
    final h = int.tryParse(parts[0]) ?? 8;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  String _formatMinutes(int total) {
    final h = (total ~/ 60).toString().padLeft(2, '0');
    final m = (total % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  TimeOfDay _toTimeOfDay(String hhmm) {
    final mins = _parseMinutes(hhmm);
    return TimeOfDay(hour: mins ~/ 60, minute: mins % 60);
  }

  Future<void> _editSection(int index) async {
    final current = _times[index];
    final pickedStart = await showTimePicker(
      context: context,
      initialTime: _toTimeOfDay(current.start),
      helpText: '选择第 ${index + 1} 节上课时间',
    );
    if (pickedStart == null || !mounted) return;

    final startStr =
        '${pickedStart.hour.toString().padLeft(2, '0')}:${pickedStart.minute.toString().padLeft(2, '0')}';

    final pickedEnd = await showTimePicker(
      context: context,
      initialTime: _toTimeOfDay(current.end),
      helpText: '选择第 ${index + 1} 节下课时间',
    );
    if (pickedEnd == null || !mounted) return;

    final endStr =
        '${pickedEnd.hour.toString().padLeft(2, '0')}:${pickedEnd.minute.toString().padLeft(2, '0')}';

    setState(() {
      _times[index] = SectionTime(start: startStr, end: endStr);
    });
  }

  void _resetDefaults() {
    setState(() {
      _maxSections = 12;
      _times = [...ScheduleConfig.defaultSectionTimes()];
    });
  }

  void _saveAndPop() {
    Navigator.of(context).pop(
      widget.config.copyWith(
        maxSections: _maxSections,
        sectionTimes: _times.take(_maxSections).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('作息时间与节数'),
        actions: [
          TextButton(
            onPressed: _resetDefaults,
            child: const Text('恢复默认'),
          ),
          FilledButton(
            onPressed: _saveAndPop,
            child: const Text('保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('每天最大节数'),
            subtitle: Text('当前每天 $_maxSections 节课'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _maxSections > 8
                      ? () => setState(() => _maxSections--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_maxSections', style: const TextStyle(fontSize: 16)),
                IconButton(
                  onPressed: _maxSections < 16
                      ? () {
                          setState(() {
                            _maxSections++;
                            _ensureLength(_maxSections);
                          });
                        }
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '点击任意一节可修改上下课时间',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          ...List.generate(_maxSections, (i) {
            final t = _times[i];
            return ListTile(
              leading: CircleAvatar(
                radius: 14,
                child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
              ),
              title: Text('第 ${i + 1} 节'),
              subtitle: Text('${t.start} - ${t.end}'),
              trailing: const Icon(Icons.edit_outlined, size: 18),
              onTap: () => _editSection(i),
            );
          }),
        ],
      ),
    );
  }
}
