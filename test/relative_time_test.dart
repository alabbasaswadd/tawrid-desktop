import 'package:flutter_test/flutter_test.dart';
import 'package:tawrid_app/shared/utils/relative_time.dart';

/// صياغة التواريخ — ماضيها ومستقبلها.
///
/// سببُ وجودها عطبٌ وقع: الدالّة كانت تحسب `now.difference(dt)` وتفرّع
/// على موجبه وحده، وفرقُ تاريخٍ قادم سالب — و«سالبٌ أصغر من ستين» صادق
/// دائماً. فكان كل تاريخٍ مستقبلي يُعرَض «الآن».
///
/// ولم يكن أثرُه تجميلياً: شاشة العرض تكتب «ساري من كذا إلى {الانتهاء}»،
/// فعرضٌ أمامه ثلاثون يوماً يُقرأ «إلى الآن» — يظنّ صاحبه أنه انتهى
/// لحظةَ إنشائه.
void main() {
  final now = DateTime.now();

  group('الماضي', () {
    test('لحظةٌ مضت = الآن', () {
      expect(formatSmartTimestamp(now.subtract(const Duration(seconds: 5))),
          'الآن');
    });

    test('دقائق مضت', () {
      expect(formatSmartTimestamp(now.subtract(const Duration(minutes: 9))),
          'منذ 9 دقائق');
      expect(formatSmartTimestamp(now.subtract(const Duration(minutes: 1))),
          'منذ 1 دقيقة');
    });

    test('تمييز العدد عربيّ — لا «١٢ دقائق»', () {
      expect(formatSmartTimestamp(now.subtract(const Duration(minutes: 12))),
          'منذ 12 دقيقة');
      expect(formatSmartTimestamp(now.subtract(const Duration(minutes: 2))),
          'منذ 2 دقيقتين');
    });

    test('أيامٌ مضت دون الأسبوع', () {
      expect(formatSmartTimestamp(now.subtract(const Duration(days: 3))),
          startsWith('منذ 3'));
    });

    test('ما جاوز الأسبوع تاريخٌ كامل', () {
      final old = DateTime(2026, 3, 14, 9, 5);
      expect(formatSmartTimestamp(old), contains('2026/03/14'));
    });
  });

  group('المستقبل', () {
    test('دقائق قادمة لا تُقرأ «الآن»', () {
      final out = formatSmartTimestamp(now.add(const Duration(minutes: 30)));
      expect(out, isNot('الآن'));
      expect(out, startsWith('بعد'));
    });

    test('غداً يُسمّى غداً', () {
      final tomorrow = DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 1, hours: 10));
      expect(formatSmartTimestamp(tomorrow), startsWith('غداً'));
    });

    test('أيامٌ قادمة دون الأسبوع', () {
      expect(formatSmartTimestamp(now.add(const Duration(days: 3, hours: 1))),
          startsWith('بعد 3'));
    });

    test('العطب بعينه: انتهاءٌ بعد ثلاثين يوماً ليس «الآن»', () {
      final expiry = now.add(const Duration(days: 30));
      final out = formatSmartTimestamp(expiry);

      expect(out, isNot('الآن'));
      // ما جاوز الأسبوع تاريخٌ كامل — أوضح من «بعد ثلاثين يوماً».
      expect(out, contains('${expiry.year}/'));
    });

    test('لحظةٌ قادمة جداً تبقى «الآن»', () {
      expect(formatSmartTimestamp(now.add(const Duration(seconds: 5))), 'الآن');
    });
  });
}
