// اتجاه جداول الـPDF.
//
// `pw.Table` — وما يبنيه `TableHelper` — لا يرث `textDirection` من
// الصفحة: يرصف خلاياه من اليسار مهما كان اتجاه المستند. فجدولٌ رؤوسه
// «الصنف · الشركة · الكمية» كان يبدأ من اليسار، ويبدأ القارئ العربي
// من آخر أعمدته: «الحالة» قبل أن يعرف أيّ صنفٍ هو.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tawrid_app/shared/utils/export.dart';

void main() {
  group('قلب صفوف الجدول', () {
    test('أول عمودٍ يصير آخر خليّة — فيرتسم أقصى اليمين', () {
      final headers = ['الصنف', 'الشركة', 'الكمية', 'السعر'];

      expect(pdfRtlRow(headers), ['السعر', 'الكمية', 'الشركة', 'الصنف']);
    });

    test('الرؤوس والبيانات تُقلَبان بالترتيب نفسه', () {
      final headers = ['#', 'الصنف', 'السعر'];
      final row = ['1', 'باراسيتامول', '1200'];

      final h = pdfRtlRow(headers);
      final r = pdfRtlRow(row);

      // كل خليّةٍ تحت رأسها: لو قُلب أحدهما وحده لوقع السعر تحت «#».
      for (var i = 0; i < h.length; i++) {
        final original = headers.indexOf(h[i]);
        expect(r[i], row[original]);
      }
    });

    test('القلب مرّتين يعود إلى الأصل، والأصل لا يُمَسّ', () {
      final original = ['أ', 'ب', 'ج'];
      final once = pdfRtlRow(original);

      expect(pdfRtlRow(once), original);
      expect(original, ['أ', 'ب', 'ج'], reason: 'يُعيد نسخةً لا يُبدّل');
    });

    test('الصفّ الفارغ والواحد لا يكسران شيئاً', () {
      expect(pdfRtlRow(<String>[]), isEmpty);
      expect(pdfRtlRow(['وحيد']), ['وحيد']);
    });
  });

  group('قلب أوزان الأعمدة', () {
    test('الوزن يتبع عموده — وإلا وقع وزن «الصنف» على «التسلسل»', () {
      // الترتيب الأصلي: 0=التسلسل ضيّق · 1=الصنف عريض · 2=السعر
      final widths = <int, pw.TableColumnWidth>{
        0: const pw.FixedColumnWidth(32),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(1.4),
      };

      final flipped = pdfRtlWidths(3, widths);

      // بعد القلب: التسلسل صار الأخير، فوزنه الضيّق يتبعه إلى هناك.
      expect(flipped[2], widths[0]);
      expect(flipped[1], widths[1]);
      expect(flipped[0], widths[2]);
    });

    test('عمودٌ بلا وزنٍ معرَّف يبقى بلا وزن', () {
      final widths = <int, pw.TableColumnWidth>{
        1: const pw.FlexColumnWidth(3),
      };

      final flipped = pdfRtlWidths(3, widths);

      expect(flipped.containsKey(1), isTrue, reason: 'الوسط يبقى وسطاً');
      expect(flipped.containsKey(0), isFalse);
      expect(flipped.containsKey(2), isFalse);
    });

    test('كل الأوزان تنجو من القلب — لا يسقط واحد', () {
      final widths = <int, pw.TableColumnWidth>{
        for (var i = 0; i < 6; i++) i: pw.FlexColumnWidth(i + 1),
      };

      final flipped = pdfRtlWidths(6, widths);

      expect(flipped.length, 6);
      for (var i = 0; i < 6; i++) {
        expect(flipped[i], widths[5 - i]);
      }
    });
  });
}
