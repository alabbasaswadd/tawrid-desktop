import 'package:flutter/material.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';

import 'responsive.dart';

/// شبكة بطاقاتٍ تُقرّر أعمدتها من العرض المتاح.
///
/// وُضعت لأن ثلاث شاشاتٍ احتاجت الشيء نفسه — الأدوية والعروض والطلبات —
/// وتكرارُ `GridView` في كلٍّ منها يعني ثلاثة قراراتٍ تفترق عند أول
/// تعديل. والمقاس يُقاس من العرض المتاح لا من عرض النافذة: الشريط
/// الجانبي والهوامش تأكل مئتي بكسل.
///
/// وعمودٌ واحد على الشاشة الضيّقة ليس حالةً خاصّة — هو ما تُعطيه المعادلة
/// نفسها، فلا تفترق الشاشة عن نفسها بين مقاسٍ ومقاس.
class AdaptiveCardGrid extends StatelessWidget {
  const AdaptiveCardGrid({
    required this.itemCount,
    required this.itemBuilder,
    required this.tileHeight,
    this.minTileWidth = 340,
    this.maxColumns = 5,
    this.padding = EdgeInsets.zero,
    this.header,
    this.footer,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// ارتفاعٌ ثابت لا نسبةُ عرض: محتوى البطاقة معروف، والنسبة تُطيلها
  /// كلّما اتّسعت الشاشة فتصير مستطيلاتٍ فارغة.
  final double tileHeight;

  final double minTileWidth;
  final int maxColumns;
  final EdgeInsetsGeometry padding;

  /// يُمرَّر داخل التمرير نفسه لا فوقه — فيمضي مع القائمة بدل أن يثبت.
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final resolved = padding.resolve(Directionality.of(context));

    return BoardContent(
      child: LayoutBuilder(
        builder: (context, box) {
          final cols = columnsFor(
            box.maxWidth - resolved.horizontal,
            minTile: minTileWidth,
            max: maxColumns,
          );

          return CustomScrollView(
            slivers: [
              if (header != null)
                SliverPadding(
                  padding: EdgeInsets.only(
                    left: resolved.left,
                    right: resolved.right,
                    top: resolved.top,
                  ),
                  sliver: SliverToBoxAdapter(child: header),
                ),
              SliverPadding(
                padding: EdgeInsets.only(
                  left: resolved.left,
                  right: resolved.right,
                  top: header == null ? resolved.top : AppSpacing.md,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisExtent: tileHeight,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    itemBuilder,
                    childCount: itemCount,
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.only(
                  left: resolved.left,
                  right: resolved.right,
                  bottom: resolved.bottom,
                  top: AppSpacing.lg,
                ),
                sliver: SliverToBoxAdapter(
                  child: footer ?? const SizedBox.shrink(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
