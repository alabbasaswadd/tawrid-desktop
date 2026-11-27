// جدولٌ لا يُسقط التصدير مهما طال نصُّه أو كثُرت صفوفه.
//
// `MultiPage` لا يفتّ صفّ جدولٍ بين صفحتين — يفتّ بين الصفوف لا داخلها.
// فخليّةٌ أطول من صفحة تُنتج صفّاً لا يتّسع في أيّ صفحة، فيدور المولّد
// بلا تقدّم حتى يرمي TooManyPagesException. ورسالتها تقول «عشرون صفحة»
// فيُظنّ السقفُ عدداً يُرفَع — وهو عدّادُ صفحاتٍ متتاليةٍ بلا تقدّم.
import 'package:flutter_test/flutter_test.dart';
import 'package:tawrid_app/shared/utils/export.dart';

/// صفٌّ وهمي: اسمٌ ونصٌّ طويل.
typedef _Row = ({String name, String regions});

List<ExportColumn<_Row>> _columns() => [
      ExportColumn(header: 'العرض', value: (r) => r.name, pdfFlex: 5),
      ExportColumn(header: 'الحالة', value: (r) => 'منشور'),
      ExportColumn(header: 'الأصناف', value: (r) => 12),
      ExportColumn(header: 'النوع', value: (r) => 'ثابت'),
      ExportColumn(header: 'يبدأ', value: (r) => '27/11'),
      ExportColumn(header: 'ينتهي', value: (r) => 'بلا نهاية'),
      ExportColumn(header: 'المناطق', value: (r) => r.regions, pdfFlex: 4),
      ExportColumn(header: 'بونص', value: (r) => 'نعم'),
    ];

void main() {
  // الشبكة تُنادى لجلب خطّ Cairo، فهذه تحتاج اتصالاً.
  // وهي مقصودة: المُولَّد الحقيقي هو ما يُختبَر لا محاكاته.

  test('مناطقُ عرضٍ تملأ صفحةً لا تُسقط التصدير', () async {
    // مستودعٌ يخدم عشرين مدينة: المناطق كلّها في خليّةٍ واحدة.
    // هذه هي الحالة التي أسقطت تصدير العروض.
    final regions = List.generate(
      40,
      (i) => 'محافظة إدلب - مدينة رقم ${i + 1}',
    ).join('، ');

    final rows = [
      for (var i = 0; i < 50; i++)
        (name: 'عرض مستورد ${i + 1} — 27/11', regions: regions),
    ];

    final bytes = await buildTablePdf<_Row>(
      title: 'عروض المستودع',
      issuer: 'مستودع الحياة سلقين',
      columns: _columns(),
      rows: rows,
      facts: const [(label: 'عدد العروض', value: '50')],
    );

    expect(bytes, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('خليّةٌ وحشية — عشرة آلاف حرف في خانةٍ واحدة', () async {
    final monster = 'نصٌّ طويل جداً ' * 700;

    final bytes = await buildTablePdf<_Row>(
      title: 'اختبار',
      columns: _columns(),
      rows: [(name: monster, regions: monster)],
    );

    expect(bytes, isNotEmpty,
        reason: 'الحارس في المُصدِّر: أيُّ حقلٍ يُضاف غداً قد يطول');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('أربعمئة صنفٍ تُصدَّر — الكثرة ليست العطب', () async {
    // «أدويتي» تُصدَّر كاملةً الآن لا الصفحة المعروضة وحدها.
    final rows = [
      for (var i = 0; i < 400; i++)
        (name: 'كورناسيل بلس (6.25/ 2.5) ملغ – 30 حبة #$i', regions: 'إدلب'),
    ];

    final bytes = await buildTablePdf<_Row>(
      title: 'أدوية مستودعي',
      issuer: 'مستودع الحياة سلقين',
      columns: _columns(),
      rows: rows,
    );

    expect(bytes, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('ألفا صنفٍ — أبعد من أيّ مستودعٍ حقيقي', () async {
    // السقف الجديد ألف صفحة. ألفا صفٍّ في ثمانية أعمدة تحتاج نحو مئة
    // وعشر صفحات — فهامشُ الأمان تسعةُ أضعاف.
    final rows = [
      for (var i = 0; i < 2000; i++)
        (name: 'كورناسيل بلس (6.25/ 2.5) ملغ – 30 حبة #$i', regions: 'إدلب'),
    ];

    final bytes = await buildTablePdf<_Row>(
      title: 'أدوية مستودعي',
      columns: _columns(),
      rows: rows,
    );

    expect(bytes, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('جدولٌ بلا صفوف لا يرمي', () async {
    final bytes = await buildTablePdf<_Row>(
      title: 'فارغ',
      columns: _columns(),
      rows: const [],
    );

    expect(bytes, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
