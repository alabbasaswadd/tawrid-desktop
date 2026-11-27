// حدود حقول العرض — نسخةُ العميل من `CreateSalesOfferValidator`.
//
// كلّ حالةٍ هنا كانت تمرّ قبل هذا العمل، فيردّها الخادم برسالةٍ عامّة
// لا تسمّي الصنف — أو لا يردّها أحد.
import 'package:flutter_test/flutter_test.dart';
import 'package:tawrid_app/shared/utils/offer_rules.dart';

void main() {
  group('سعر الوحدة', () {
    test('الصفر يُردّ — وكان يمرّ لأن الشرط كان «أصغر من صفر»', () {
      expect(OfferRules.unitPrice('0'), isNotNull);
      expect(OfferRules.unitPrice('0.0'), isNotNull);
    });

    test('الفارغ والنصّ يُردّان', () {
      expect(OfferRules.unitPrice(''), isNotNull);
      expect(OfferRules.unitPrice(null), isNotNull);
      expect(OfferRules.unitPrice('غالٍ'), isNotNull);
    });

    test('الموجب يمرّ — بالفاصلة العشرية العربية أيضاً', () {
      expect(OfferRules.unitPrice('1500'), isNull);
      expect(OfferRules.unitPrice('2,25'), isNull);
      expect(OfferRules.unitPrice('٣٥٠٠'), isNull);
    });
  });

  group('الكمية', () {
    test('المفتوحة تمرّ ولو كان الحقل فارغاً', () {
      expect(OfferRules.quantity('', open: true), isNull);
      expect(OfferRules.quantity(null, open: true), isNull);
      expect(OfferRules.quantity('لا شيء', open: true), isNull);
    });

    test('المحدَّدة تشترط موجباً', () {
      expect(OfferRules.quantity('0', open: false), isNotNull);
      expect(OfferRules.quantity('-5', open: false), isNotNull);
      expect(OfferRules.quantity('', open: false), isNotNull);
      expect(OfferRules.quantity('100', open: false), isNull);
    });
  });

  group('نسبة الحسم', () {
    // net = السعر × (١ − الحسم/١٠٠): فما فوق المئة يجعل سعر السلّة
    // سالباً، والسالب يرفعه فوق المعلَن.
    test('خارج المدى يُردّ', () {
      expect(OfferRules.discount('150'), isNotNull);
      expect(OfferRules.discount('-50'), isNotNull);
      expect(OfferRules.discount('1000'), isNotNull);
      expect(OfferRules.discount('نصف'), isNotNull);
    });

    test('داخل المدى يمرّ، والفارغ اختياري', () {
      expect(OfferRules.discount('0'), isNull);
      expect(OfferRules.discount('12,5'), isNull);
      expect(OfferRules.discount('100'), isNull);
      expect(OfferRules.discount(''), isNull);
      expect(OfferRules.discount('   '), isNull);
      expect(OfferRules.discount(null), isNull);
    });
  });

  group('شروط الدفع', () {
    test('الدفعة المقدَّمة بين صفر ومئة', () {
      expect(OfferRules.upfrontPercentage('500'), isNotNull);
      expect(OfferRules.upfrontPercentage('-1'), isNotNull);
      expect(OfferRules.upfrontPercentage('30'), isNull);
      expect(OfferRules.upfrontPercentage(''), isNull);
    });

    test('مدّة السداد غير سالبة ولا تتجاوز السقف', () {
      expect(OfferRules.paymentPeriodDays('-30'), isNotNull);
      expect(OfferRules.paymentPeriodDays('9999'), isNotNull);
      expect(OfferRules.paymentPeriodDays('30,5'), isNotNull, reason: 'أيامٌ صحيحة');
      expect(OfferRules.paymentPeriodDays('0'), isNull);
      expect(OfferRules.paymentPeriodDays('60'), isNull);
      expect(OfferRules.paymentPeriodDays(''), isNull);
    });

    test('السقف يطابق مدقّق الخادم', () {
      // MaxPaymentPeriodDays في CreateSalesOfferValidator.
      expect(OfferRules.maxPaymentPeriodDays, 730);
      expect(OfferRules.paymentPeriodDays('730'), isNull);
      expect(OfferRules.paymentPeriodDays('731'), isNotNull);
    });
  });

  group('هديّة العرض', () {
    test('بلا دواءٍ مختار لا شرط على الكمية', () {
      expect(OfferRules.bonusQuantity('', hasMedicine: false), isNull);
      expect(OfferRules.bonusQuantity('0', hasMedicine: false), isNull);
    });

    test('مع دواءٍ مختار تُشترط كميةٌ موجبة — نصفُ هديّة لا تُعرض', () {
      expect(OfferRules.bonusQuantity('', hasMedicine: true), isNotNull);
      expect(OfferRules.bonusQuantity('0', hasMedicine: true), isNotNull);
      expect(OfferRules.bonusQuantity('5', hasMedicine: true), isNull);
    });
  });

  group('الوحدة', () {
    test('الفراغ ليس وحدة', () {
      expect(OfferRules.unit('   '), isNotNull);
      expect(OfferRules.unit(''), isNotNull);
      expect(OfferRules.unit(null), isNotNull);
      expect(OfferRules.unit('علبة'), isNull);
    });
  });

  group('سقف الكمية المفتوحة', () {
    test('ليس واحداً — وكان واحداً فيمنع طلب علبتين', () {
      expect(OfferRules.openQuantityCap, greaterThan(1));
      expect(OfferRules.openQuantityCap, 9999);
    });
  });

  group('كلّ الرسائل عربية', () {
    test('لا حرفَ لاتينيّ في أيّ رسالةِ ردّ', () {
      final messages = <String?>[
        OfferRules.unitPrice('0'),
        OfferRules.quantity('0', open: false),
        OfferRules.discount('150'),
        OfferRules.upfrontPercentage('500'),
        OfferRules.paymentPeriodDays('-1'),
        OfferRules.bonusQuantity('', hasMedicine: true),
        OfferRules.unit(''),
      ].whereType<String>();

      expect(messages, isNotEmpty);
      for (final m in messages) {
        expect(RegExp(r'[a-zA-Z]').hasMatch(m), isFalse, reason: m);
      }
    });
  });
}
