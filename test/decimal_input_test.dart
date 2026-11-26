import 'package:flutter_test/flutter_test.dart';
import 'package:tawrid_app/shared/utils/money.dart';

/// قراءة الأرقام التي يكتبها مستخدمٌ عربي.
///
/// سببُ وجودها عطبٌ وقع: حقل السعر كان يقرأ بـ
/// `double.tryParse(text.replaceAll(',', ''))` — فالفاصلة تُحذَف دائماً
/// بوصفها فاصل آلاف. ومن كتب «٣,٥» قاصداً ثلاثةً ونصفاً حُفظ له «٣٥»،
/// سعرٌ عشرةُ أضعاف ما أراد يذهب إلى الصيدليات بلا تنبيه. ومن كتب
/// بالأرقام العربية-الهندية لم يُقرأ له شيء أصلاً.
void main() {
  group('parseDecimalInput', () {
    test('الأرقام اللاتينية بنقطةٍ عشرية', () {
      expect(parseDecimalInput('2.25'), 2.25);
      expect(parseDecimalInput('0.35'), 0.35);
      expect(parseDecimalInput('12500'), 12500);
    });

    test('الفاصلة عشريةٌ حين لا تحتمل التجميع', () {
      // هذا هو العطب بعينه: «٣,٥» ثلاثةٌ ونصف لا خمسةٌ وثلاثون.
      expect(parseDecimalInput('3,5'), 3.5);
      expect(parseDecimalInput('0,75'), 0.75);
      expect(parseDecimalInput('2,2'), 2.2);
    });

    test('الفاصلة تجميعٌ بثلاث خاناتٍ بعدها', () {
      expect(parseDecimalInput('12,500'), 12500);
      expect(parseDecimalInput('1,250,000'), 1250000);
    });

    test('النقطة والفاصلة معاً — آخرُهما العشري', () {
      expect(parseDecimalInput('1.250,75'), 1250.75);
      expect(parseDecimalInput('1,250.75'), 1250.75);
    });

    test('الأرقام العربية-الهندية والفارسية', () {
      expect(parseDecimalInput('٢٥٠'), 250);
      expect(parseDecimalInput('۲۵۰'), 250);

      // الفاصلة العشرية العربية ٫ (U+066B).
      expect(parseDecimalInput('٢٫٢٥'), 2.25);
    });

    test('رموز العملة والمسافات تُطرح', () {
      expect(parseDecimalInput('2.25 \$'), 2.25);
      expect(parseDecimalInput('12500 ل.س'), 12500);
      expect(parseDecimalInput('  7  '), 7);
    });

    test('ما لا يُقرأ رقماً يعود null', () {
      expect(parseDecimalInput(''), isNull);
      expect(parseDecimalInput('   '), isNull);
      expect(parseDecimalInput('مجاناً'), isNull);
    });
  });

  group('formatForInput', () {
    test('لا يُدوّر الكسر', () {
      // العطب الثاني: الحقل كان يُملأ بـ toStringAsFixed(0)، فصنفٌ
      // سعره ٢٫٢٥ يُفتَح حواره فيظهر «2» — ويكفي ضغط «حفظ» ليصير اثنين.
      expect(formatForInput(2.25), '2.25');
      expect(formatForInput(0.35), '0.35');
    });

    test('الصحيح بلا كسرٍ ولا أصفار لاحقة', () {
      expect(formatForInput(12500), '12500');
      expect(formatForInput(2.0), '2');
      expect(formatForInput(2.50), '2.5');
    });

    test('بلا فاصل آلاف — ما يُكتب هنا يُقرأ ثانيةً', () {
      expect(formatForInput(1250000), '1250000');
    });

    test('الذهاب والإياب لا يُغيّر القيمة', () {
      for (final v in [2.25, 0.35, 12500.0, 1.5, 999999.0]) {
        expect(parseDecimalInput(formatForInput(v)), v, reason: '$v');
      }
    });
  });
}
