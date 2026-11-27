// فرقُ البونص بين الملف وما يعرضه المستودع.
//
// العطب: المراجعة كانت تُقارن السعر وحده. فملفٌّ غيّر «١٠+١» إلى «١٠+٣»
// يُعَدّ «لا جديد فيه»، فيختفي من مرشّح «المتغيّر» — وهو المرشّح
// الافتراضي — ويمرّ التبديل صامتاً. ويبقى بونصُ الشهر الماضي معروضاً
// على الصيدليات بعد أن ظنّ صاحبه أنه زامن.
import 'package:flutter_test/flutter_test.dart';
import 'package:tawrid_app/models/ai_import_models.dart';

ImportRow _row({
  double? bonusBuy,
  double? bonusFree,
  double? prevBuy,
  double? prevFree,
  bool bonusChanged = false,
  ImportMatch match = ImportMatch.owned,
  double? price = 100,
  double? previousPrice = 100,
  bool selected = true,
}) =>
    ImportRow(
      id: 'r1',
      rowNumber: 1,
      rawCells: '',
      name: 'دواء',
      price: price,
      previousPrice: previousPrice,
      bonusBuyQuantity: bonusBuy,
      bonusFreeQuantity: bonusFree,
      previousBonusBuyQuantity: prevBuy,
      previousBonusFreeQuantity: prevFree,
      bonusChanged: bonusChanged,
      matchStatus: match,
      selected: selected,
      confidence: 1,
    );

void main() {
  group('تسمية البونص', () {
    test('بونص الملف وبونصي يُصاغان بالصيغة نفسها', () {
      final row = _row(bonusBuy: 10, bonusFree: 3, prevBuy: 10, prevFree: 1);

      expect(row.bonusLabel, '10+3');
      expect(row.previousBonusLabel, '10+1');
    });

    test('بلا بونصٍ لا تسمية', () {
      expect(_row().bonusLabel, isNull);
      expect(_row().previousBonusLabel, isNull);
    });

    test('نصفُ بونصٍ لا يُصاغ — كميةُ شراءٍ بلا مجّاني ليست بونصاً', () {
      expect(_row(bonusBuy: 10).bonusLabel, isNull);
      expect(_row(prevBuy: 10).previousBonusLabel, isNull);
    });
  });

  group('البونص تغييرٌ كالسعر', () {
    test('سعرٌ ثابتٌ وبونصٌ تبدّل = صفٌّ متغيّر', () {
      // هذه هي الحالة التي كانت تمرّ صامتة: السعر نفسه، والبونص تبدّل.
      final row = _row(
        price: 100,
        previousPrice: 100,
        bonusBuy: 10,
        bonusFree: 3,
        prevBuy: 10,
        prevFree: 1,
        bonusChanged: true,
      );

      expect(row.willChange, isTrue,
          reason: 'لولاه لاختفى الصفّ من مرشّح «المتغيّر» الافتراضي');
    });

    test('سعرٌ ثابتٌ وبونصٌ ثابت = لا تغيير', () {
      final row = _row(
        price: 100,
        previousPrice: 100,
        bonusBuy: 10,
        bonusFree: 1,
        prevBuy: 10,
        prevFree: 1,
      );

      expect(row.willChange, isFalse);
    });

    test('السعر وحده ما زال يكفي للتغيير', () {
      final row = _row(price: 120, previousPrice: 100);
      expect(row.willChange, isTrue);
    });

    test('إضافةُ بونصٍ على صنفٍ بلا بونص تغييرٌ', () {
      final row = _row(bonusBuy: 10, bonusFree: 2, bonusChanged: true);
      expect(row.willChange, isTrue);
    });

    test('إزالةُ بونصٍ كانت موجودة تغييرٌ', () {
      final row = _row(prevBuy: 10, prevFree: 2, bonusChanged: true);
      expect(row.willChange, isTrue);
    });
  });

  group('حدود المقارنة', () {
    test('الصفّ غير المملوك لا يُقارَن — هو إضافةٌ لا تبديل', () {
      final row = _row(
        match: ImportMatch.notFound,
        previousPrice: null,
        bonusBuy: 10,
        bonusFree: 3,
      );

      // willChange تصدق لأنه جديد، لا لأن بونصه تبدّل.
      expect(row.willChange, isTrue);
      expect(row.previousBonusLabel, isNull);
    });

    test('الصفّ بلا اسمٍ لا يتغيّر — لا شيء فيه يُكتب', () {
      // `willChange` تصف الصفّ لا إقراره: التحديد شرطٌ منفصل يقرأه
      // الخادم عند التطبيق، وخلطُهما يجعل إلغاء تحديد صفٍّ يُخفيه من
      // عدّاد «المتغيّر» فيظنّ صاحبه أنه لم يتغيّر أصلاً.
      final row = ImportRow(
        id: 'r0',
        rowNumber: 1,
        rawCells: '',
        name: '',
        bonusChanged: true,
        matchStatus: ImportMatch.owned,
        selected: true,
        confidence: 1,
      );

      expect(row.willChange, isFalse);
    });
  });
}
