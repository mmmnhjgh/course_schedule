import 'package:material_ui/material_ui.dart';

import '../models/course.dart';

/// 周视图网格中的单个彩色课程卡片（支持长按快捷操作与单周停课样式）
class CourseCard extends StatelessWidget {
  final Course course;
  final bool isCurrentWeek;
  final bool isCanceled;
  final int conflictCount;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const CourseCard({
    super.key,
    required this.course,
    this.isCurrentWeek = true,
    this.isCanceled = false,
    this.conflictCount = 0,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = Color(course.colorValue);
    final activeStyle = isCurrentWeek && !isCanceled;
    final bgColor = activeStyle
        ? baseColor.withValues(alpha: 0.90)
        : Colors.grey.withValues(alpha: 0.24);
    final textColor = activeStyle ? Colors.white : Colors.black54;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      decoration:
                          isCanceled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (course.location.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      '@${course.location}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.92),
                        fontSize: 10,
                        height: 1.15,
                      ),
                    ),
                  ],
                  if (isCanceled) ...[
                    const Spacer(),
                    Text(
                      '[已停课]',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ] else if (!isCurrentWeek) ...[
                    const Spacer(),
                    Text(
                      '[非本周]',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (conflictCount > 0)
              Positioned(
                right: 3,
                bottom: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '+$conflictCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
