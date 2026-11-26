import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tawrid_app/shared/utils/xlsx.dart';

/// بنية ملف xlsx المُولَّد.
///
/// تُختبَر بنيوياً لأن الصيغة لا تُسامح: جزءٌ ناقص أو مرجعُ علاقةٍ خاطئ
/// يجعل Excel يُعلن الملف تالفاً بلا أن يقول أين — وذلك لا يظهر في
/// التحليل ولا في البناء، بل في يد المستخدم.
void main() {
  /// يفكّ الملف ويُعيد محتوى كل جزءٍ نصّاً.
  Map<String, String> unzip(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    return {
      for (final f in archive.files)
        if (f.isFile) f.name: utf8.decode(f.content as List<int>),
    };
  }

  final sheet = XlsxSheet(
    name: 'أدويتي',
    headers: const ['الصنف', 'السعر'],
    columnWidths: const [30, 12],
    rows: const [
      [XlsxText('بانادول 500'), XlsxNumber(2.25)],
      [XlsxText('كورناسيل بلس (6.25/ 2.5)'), XlsxNumber(1.63)],
    ],
  );

  group('بنية الملف', () {
    test('الأجزاء التي يطلبها Excel كلّها موجودة', () {
      final parts = unzip(buildXlsx([sheet]));

      expect(parts.keys, containsAll(<String>[
        '[Content_Types].xml',
        '_rels/.rels',
        'xl/workbook.xml',
        'xl/_rels/workbook.xml.rels',
        'xl/styles.xml',
        'xl/worksheets/sheet1.xml',
      ]));
    });

    test('كل ورقةٍ تُعلَن في الأنواع والعلاقات معاً', () {
      final second = XlsxSheet(
        name: 'العروض',
        headers: const ['العرض'],
        rows: const [
          [XlsxText('عرض فاركو')],
        ],
      );

      final parts = unzip(buildXlsx([sheet, second]));

      expect(parts['[Content_Types].xml'], contains('sheet2.xml'));
      expect(parts['xl/_rels/workbook.xml.rels'],
          contains('worksheets/sheet2.xml'));
      expect(parts.containsKey('xl/worksheets/sheet2.xml'), isTrue);

      // والأنماط بعد الأوراق كلّها — معرّفٌ لا يتصادم معها.
      expect(parts['xl/_rels/workbook.xml.rels'],
          contains('Id="rId3" Type="http://schemas.openxmlformats.org/'
              'officeDocument/2006/relationships/styles"'));
    });
  });

  group('الورقة', () {
    test('تُفتَح من اليمين', () {
      // بلا هذا يُقلَب الجدول كلّه على قارئٍ عربي.
      final parts = unzip(buildXlsx([sheet]));
      expect(parts['xl/worksheets/sheet1.xml'], contains('rightToLeft="1"'));
    });

    test('الأرقام تُكتب أرقاماً لا نصوصاً', () {
      // الرقم المكتوب نصّاً لا يُجمَع ولا يُرتَّب في Excel.
      final xml = unzip(buildXlsx([sheet]))['xl/worksheets/sheet1.xml']!;

      expect(xml, contains('<v>2.25</v>'));
      expect(xml, isNot(contains('<t>2.25</t>')));
    });

    test('العربية تُكتب كما هي', () {
      final xml = unzip(buildXlsx([sheet]))['xl/worksheets/sheet1.xml']!;
      expect(xml, contains('كورناسيل بلس (6.25/ 2.5)'));
    });

    test('مراجع الخلايا تتبع ترقيم Excel', () {
      final xml = unzip(buildXlsx([sheet]))['xl/worksheets/sheet1.xml']!;

      // الترويسة في السطر الأول، وأول صفّ بياناتٍ في الثاني.
      expect(xml, contains('r="A1"'));
      expect(xml, contains('r="B2"'));
    });

    test('عرض الأعمدة يُكتب حين يُطلَب', () {
      final xml = unzip(buildXlsx([sheet]))['xl/worksheets/sheet1.xml']!;
      expect(xml, contains('width="30"'));
    });
  });

  group('التهريب والتنظيف', () {
    test('محارف XML تُهرَّب', () {
      final risky = XlsxSheet(
        name: 'اختبار',
        headers: const ['الاسم'],
        rows: const [
          [XlsxText('فيتامين A & D <مركّب>')],
        ],
      );

      final xml = unzip(buildXlsx([risky]))['xl/worksheets/sheet1.xml']!;

      expect(xml, contains('&amp;'));
      expect(xml, contains('&lt;'));
      expect(xml, isNot(contains('<مركّب>')));
    });

    test('محارف التحكّم تُطرح — وإلا أعلن Excel الملف تالفاً', () {
      final risky = XlsxSheet(
        name: 'اختبار',
        headers: const ['الاسم'],
        rows: const [
          [XlsxText('بانادول500')],
        ],
      );

      final xml = unzip(buildXlsx([risky]))['xl/worksheets/sheet1.xml']!;
      expect(xml, isNot(contains('')));
      expect(xml, contains('بانادول500'));
    });

    test('اسم التبويب يُقصّ ويُنظَّف', () {
      final bad = XlsxSheet(
        name: 'تقرير/المزامنة: ${'ط' * 40}',
        headers: const ['x'],
        rows: const [
          [XlsxText('y')],
        ],
      );

      final name = RegExp(r'<sheet name="([^"]*)"')
          .firstMatch(unzip(buildXlsx([bad]))['xl/workbook.xml']!)!
          .group(1)!;

      expect(name.length, lessThanOrEqualTo(31));
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(':')));
    });
  });

  test('ملفٌ بلا أوراق يُرفَض', () {
    expect(() => buildXlsx([]), throwsArgumentError);
  });
}
