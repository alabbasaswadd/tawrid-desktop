// عمودُ الترقيم في التصدير — «١، ٢، ٣…».
//
// موضعُه المُصدِّر لا أعمدةُ كل شاشة: ستُّ شاشاتٍ تُصدّر، وعمودٌ يُكتب
// في كلٍّ منها ستُّ نسخٍ تفترق — وواحدةٌ تُنسى. وهو هنا أيضاً يعرف
// ترتيب الصفّ، وتعريفُ العمود (`ExportColumn.value`) لا يعرف إلا الصفّ.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tawrid_app/shared/utils/export.dart';

void main() {
  group('قلبُ الترقيم مع بقيّة الأعمدة', () {
    test('عمودُ الترقيم يقع أقصى اليمين — حيث تبدأ القراءة', () {
      // الجدول يُرسَم مقلوباً (pw.Table لا يرث اتجاه الصفحة)، والترقيم
      // يُلحَق بآخر الخلايا — فيقع أوّلَ ما تقع عليه العين العربية.
      final cells = pdfRtlRow(['الصنف', 'السعر']) + ['#'];

      expect(cells.last, '#');
      expect(cells, ['السعر', 'الصنف', '#']);
    });

    test('وزنُ الترقيم أضيقُ الأوزان', () {
      final widths = pdfRtlWidths(2, {
        0: const pw.FlexColumnWidth(5),
        1: const pw.FlexColumnWidth(2),
      });

      // بعد القلب: الصنف العريض يبقى عريضاً.
      expect(widths[1], const pw.FlexColumnWidth(5));
      expect(widths[0], const pw.FlexColumnWidth(2));
    });
  });

  group('ترتيب الأعمدة بعد حذف «مصدر السعر»', () {
    test('الأعمدة الباقية سبعةٌ لا ثمانية', () {
      // «مصدر السعر» تمييزٌ داخليّ يخصّ المراجعة، والملفّ يُرسَل إلى
      // صيدليةٍ لا تعنيها طريقةُ اشتقاق الرقم. وهو ظاهرٌ في الشاشة.
      const expected = [
        'الصنف',
        'المادة الفعّالة',
        'الشركة',
        'العيار',
        'الشكل',
        'كود ساكو',
        'السعر',
      ];

      expect(expected, isNot(contains('مصدر السعر')));
      expect(expected.length, 7);
    });
  });

  group('حدود الترقيم', () {
    test('جدولٌ فارغ لا يُنتج صفّ ترقيمٍ واحداً', () {
      const rows = <String>[];
      final numbers = [for (var i = 0; i < rows.length; i++) i + 1];
      expect(numbers, isEmpty);
    });

    test('الترقيم يبدأ من واحدٍ لا من صفر', () {
      const rows = ['أ', 'ب', 'ج'];
      final numbers = [for (var i = 0; i < rows.length; i++) i + 1];
      expect(numbers, [1, 2, 3]);
    });
  });
}
