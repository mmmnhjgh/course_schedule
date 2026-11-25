import 'package:flutter_test/flutter_test.dart';

import 'package:course_schedule/services/edu_parsers.dart';

void main() {
  test('EduParsers detects academic systems and parses section ranges', () {
    expect(
      EduParsers.detectSystem('https://jw.example.edu.cn/jwglxt/kbcx/xskbcx.html'),
      WebAcademicType.zhengfangNew,
    );
    expect(
      EduParsers.detectSystem('http://jwgl.example.edu.cn/jsxsd/xskb/xskb_list.do'),
      WebAcademicType.qiangzhi,
    );
    expect(EduParsers.parseSectionRange('0304'), (start: 3, end: 4));
    expect(EduParsers.parseSectionRange('第5-6节'), (start: 5, end: 6));
    expect(
      EduParsers.parseWeeksExpression('1-8周(单), 10-12周'),
      [1, 3, 5, 7, 10, 11, 12],
    );
  });

  test('EduParsers parses Zhengfang kbList API payload cleanly', () {
    final payload = {
      'kbList': [
        {
          'kcmc': '编译原理',
          'xm': '周老师',
          'cdmc': '信息楼301',
          'xqj': '3',
          'jcs': '0304',
          'zcd': '1-8周(单),10-12周',
        },
        {
          'kcmc': '编译原理',
          'xm': '周老师',
          'cdmc': '信息楼301',
          'xqj': '3',
          'jcs': '0304',
          'zcd': '1-8周(单),10-12周',
        },
      ],
    };

    final res = EduParsers.parseZhengfangKbList(payload);
    expect(res.sourceTag, 'zhengfangApi');
    expect(res.courses.length, 1);
    final c = res.courses.first;
    expect(c.name, '编译原理');
    expect(c.weekday, 3);
    expect(c.startSection, 3);
    expect(c.sectionCount, 2);
    expect(c.weeks, [1, 3, 5, 7, 10, 11, 12]);
  });

  test('EduParsers parses Qiangzhi table#kbtable with multi-course blocks', () {
    const html = '''
<table id="kbtable">
  <tr>
    <th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th>
  </tr>
  <tr>
    <td>第一二节<br>08:00-09:40</td>
    <td>
      <div class="kbcontent">
        高等数学 P<br>张教授<br>1-8(周)[01-02节]<br>教A-101
        ---------------------
        大学物理<br>李老师<br>2-8周(双)[01-02节]<br>教B-202
      </div>
    </td>
    <td></td><td></td><td></td><td></td>
  </tr>
</table>
''';

    final res = EduParsers.parseQiangzhiTableHtml(html);
    expect(res.courses.length, 2);
    expect(res.courses[0].name, '高等数学');
    expect(res.courses[0].teacher, '张教授');
    expect(res.courses[0].location, '教A-101');
    expect(res.courses[0].startSection, 1);
    expect(res.courses[0].endSection, 2);
    expect(res.courses[0].weeks, [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(res.courses[1].weeks, [2, 4, 6, 8]);
  });

  test('EduParsers parses generic HTML table with rowspan', () {
    const html = '''
<table>
  <tr><th>节次</th><th>周一</th><th>周二</th><th>周三</th><th>周四</th><th>周五</th></tr>
  <tr>
    <td>1-2节</td>
    <td rowspan="2">操作系统<br>1-16周<br>主楼405<br>陈老师</td>
    <td></td><td></td><td></td><td></td>
  </tr>
  <tr>
    <td>3-4节</td>
    <td></td><td></td><td></td><td></td>
  </tr>
</table>
''';

    final res = EduParsers.parseGenericHtmlTable(html);
    expect(res.courses.length, 1);
    expect(res.courses.first.name, '操作系统');
    expect(res.courses.first.startSection, 1);
    expect(res.courses.first.endSection, 4);
    expect(res.courses.first.location, '主楼405');
    expect(res.courses.first.teacher, '陈老师');
  });

  test('EduParsers splits <p>/<div> blocks and inline teacher/location labels',
      () {
    const html = '''
<table>
  <tr><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th></tr>
  <tr>
    <td>1-2节</td>
    <td><p>金融学</p><p>教师：王老师</p><p>地点：教A-203</p><p>1-16周</p></td>
    <td><div>大学语文教师：李老师</div><div>1-16周</div><div>文科楼101</div></td>
    <td></td><td></td><td></td>
  </tr>
</table>
''';

    final res = EduParsers.parseGenericHtmlTable(html);
    expect(res.courses.length, 2);
    expect(res.courses[0].name, '金融学');
    expect(res.courses[0].teacher, '王老师');
    expect(res.courses[0].location, '教A-203');
    expect(res.courses[1].name, '大学语文');
    expect(res.courses[1].teacher, '李老师');
    expect(res.courses[1].location, '文科楼101');
  });

  test('EduParsers preserves rows after nested <table> inside a timetable cell',
      () {
    const html = '''
<table>
  <tr><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th></tr>
  <tr>
    <td>1-2节</td>
    <td><p>模拟电子技术</p><table><tr><td>子表</td></tr></table><p>(1-2节)1-17周</p></td>
    <td></td><td></td><td></td><td></td>
  </tr>
  <tr>
    <td>3-4节</td>
    <td></td>
    <td><p>信号与系统</p><p>(3-4节)1-16周</p><p>信息楼201</p><p>张老师</p></td>
    <td></td><td></td><td></td>
  </tr>
</table>
''';

    final res = EduParsers.parseGenericHtmlTable(html);
    expect(res.courses.length, 2);
    expect(res.courses[1].name, '信号与系统');
    expect(res.courses[1].startSection, 3);
    expect(res.courses[1].endSection, 4);
  });
}
