import 'package:flutter_test/flutter_test.dart';
import 'package:tawrid_app/shared/utils/export.dart';

/// تنظيف أسماء ملفات التصدير.
///
/// سببُ وجودها عطبٌ رآه المستخدم: أسماء التصدير تُبنى من بياناته —
/// «عرض ابن حيان 27/11» — والشرطة المائلة فاصلُ مسار، فيُفهَم الاسم
/// مجلّداً لا ملفاً ويخرج الحوار بـ«يتعذر على Windows العثور على…».
///
/// وعنوانُ العرض الافتراضي الذي يُنشئه الاستيراد يحمل تاريخه دائماً،
/// فكان التصدير يسقط على أكثر الحالات شيوعاً لا على شاذّة.
void main() {
  group('safeFileName', () {
    test('الشرطة المائلة تُبدَّل — وهي العطب بعينه', () {
      expect(safeFileName('عرض ابن حيان 27/11'), 'عرض ابن حيان 27-11');
    });

    test('كل المحارف التي يرفضها ويندوز', () {
      expect(safeFileName(r'a\b/c:d*e?f"g<h>i|j'),
          'a-b-c-d-e-f-g-h-i-j');
    });

    test('العربية تبقى كما هي', () {
      expect(safeFileName('تقرير المزامنة'), 'تقرير المزامنة');
      expect(safeFileName('أدويتي'), 'أدويتي');
    });

    test('نقطةٌ أو مسافةٌ في الآخر تُحذَف', () {
      // ويندوز يحذفها صمتاً فيلتصق الامتداد بالاسم.
      expect(safeFileName('تقرير.'), 'تقرير');
      expect(safeFileName('تقرير   '), 'تقرير');
      expect(safeFileName('تقرير. . '), 'تقرير');
    });

    test('محارف التحكّم تُطرح', () {
      expect(safeFileName('تقرير\u0001المزامنة'), 'تقريرالمزامنة');
    });

    test('اسمٌ خاوٍ بعد التنظيف يأخذ بديلاً', () {
      // وإلا صار الملف «.xlsx» — مخفيّاً في لينكس وبلا اسمٍ في ويندوز.
      expect(safeFileName('///'), isNotEmpty);
      expect(safeFileName('   '), isNotEmpty);
      expect(safeFileName(''), isNotEmpty);
    });

    test('الطويل يُقصّ', () {
      final long = 'ط' * 300;
      expect(safeFileName(long).length, lessThanOrEqualTo(120));
    });

    test('النتيجة لا تحمل فاصل مسارٍ أبداً', () {
      for (final raw in [
        'عرض ابن حيان 27/11',
        r'C:\Users\x',
        'a/b/c/d',
        '2026/11/27',
      ]) {
        final out = safeFileName(raw);
        expect(out, isNot(contains('/')), reason: raw);
        expect(out, isNot(contains(r'\')), reason: raw);
      }
    });
  });
}
