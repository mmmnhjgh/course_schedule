import 'package:material_ui/material_ui.dart';

import '../models/course.dart';

/// 周视图网格中的单个彩色课程卡片（展示课程名、教室、教师与冲突/停课标记）
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
        ? baseColor.withValues(alpha: 0.92)
        : Colors.grey.withValues(alpha: 0.24);
    final textColor = activeStyle ? Colors.white : Colors.black54;
    final isMultiSection = course.sectionCount >= 2;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(7),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      course.name,
                      maxLines: isMultiSection ? 4 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        height: 1.16,
                        decoration:
                            isCanceled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (course.location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${course.location}',
                        maxLines: isMultiSection ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.94),
                          fontSize: 9.5,
                          height: 1.15,
                        ),
                      ),
                    ],
                    if (isMultiSection && course.teacher.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        course.teacher,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.84),
                          fontSize: 9,
                          height: 1.1,
                        ),
                      ),
                    ],
                    if (isCanceled) ...[
                      const SizedBox(height: 2),
                      Text(
                        '[已停课]',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else if (!isCurrentWeek) ...[
                      const SizedBox(height: 2),
                      Text(
                        '[非本周]',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (conflictCount > 0)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '+$conflictCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
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
