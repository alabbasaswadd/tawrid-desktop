import 'package:flutter_test/flutter_test.dart';
import 'package:tawrid_app/shared/ui/responsive.dart';

/// حساب أعمدة الشبكة.
///
/// سببُ وجودها عطبٌ وقع على ملفٍ حقيقي: لوحة حصيلة المراجعة تحسب
/// أعمدتها بـ`clamp(2, shown.length)`، وملفٌّ كلُّ أصنافه جديدة يُخرج
/// خانةً واحدة — فيصير «الأدنى فوق الأعلى» ويرمي
/// «Invalid argument(s): 2»، وتُغطّى الشاشة بالأحمر بعد تحليلٍ استغرق
/// دقائق وكلّف ٢١٧ ألف توكن.
///
/// والحارس في [columnsFor] نفسها لا عند كل نداء: تُنادى من ست شاشات،
/// وحمايةٌ في واحدة تترك الخمس.
void main() {
  group('columnsFor', () {
    test('سقفٌ دون الواحد لا يرمي', () {
      // `max: items.length` على قائمةٍ فارغة — وهو النداء الذي أسقط
      // الشاشة.
      expect(columnsFor(1900, minTile: 200, max: 0), 1);
      expect(columnsFor(1900, minTile: 200, max: -3), 1);
    });

    test('سقفٌ واحد يُعيد عموداً', () {
      expect(columnsFor(1900, minTile: 200, max: 1), 1);
    });

    test('عرضٌ معدوم أو سالب يُعيد عموداً', () {
      expect(columnsFor(0), 1);
      expect(columnsFor(-500), 1);
    });

    test('يملأ العرض ولا يتجاوز سقفه', () {
      // ١٩٠٠ بكسل تسع ستّ بطاقاتٍ بعرض ٣٠٠، والسقف ثلاثة.
      expect(columnsFor(1900, minTile: 300, max: 3), 3);

      // وشاشةٌ ضيّقة لا تبلغ السقف.
      expect(columnsFor(700, minTile: 300, max: 5), 2);
    });

    test('عرضٌ دون بطاقةٍ واحدة يبقى عموداً', () {
      expect(columnsFor(150, minTile: 300, max: 4), 1);
    });
  });
}
