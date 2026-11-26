import 'package:flutter/material.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/tokens.dart';

// يوسّط المحتوى ضمن عرض أقصى على الشاشات العريضة (بدل تمدّد قبيح).
class CenteredContent extends StatelessWidget {
  const CenteredContent({
    required this.child,
    this.maxWidth = AppBreakpoints.maxContentWidth,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// لوحٌ يملأ عرض الشاشة إلى حدٍّ معقول — للقوائم والشبكات.
///
/// عكس [CenteredContent] في غرضه: ذاك يضيّق ليُقرأ سطراً سطراً، وهذا
/// يتّسع ليُمسح بالعين دفعةً واحدة. والخلط بينهما هو ما كان يترك ثلثي
/// الشاشة فارغاً ويجعل البطاقة الواحدة تمتدّ بعرض المكتب بلا محتوى.
class BoardContent extends StatelessWidget {
  const BoardContent({
    required this.child,
    this.maxWidth = AppBreakpoints.maxBoardWidth,
    super.key,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// عدد أعمدة شبكةٍ لا تقلّ بطاقتها عن [minTile].
///
/// يُحسب من العرض المتاح لا من عرض النافذة: الشريط الجانبي يأخذ ٢٢٠
/// بكسل، وحسابُها من النافذة يُعطي عموداً زائداً فتُضغط البطاقات.
int columnsFor(
  double width, {
  double minTile = 320,
  int max = 6,
  double gap = AppSpacing.md,
}) {
  if (width <= 0) return 1;
  final n = ((width + gap) / (minTile + gap)).floor();
  return n.clamp(1, max);
}

extension ResponsiveX on BuildContext {
  bool get isTablet => MediaQuery.sizeOf(this).width >= AppBreakpoints.tablet;

  /// شاشةٌ تتّسع لشبكةٍ متعدّدة الأعمدة وكثافةِ سطح مكتب.
  bool get isDesktop => MediaQuery.sizeOf(this).width >= AppBreakpoints.desktop;

  bool get isWide => MediaQuery.sizeOf(this).width >= AppBreakpoints.wide;

  /// هامش الصفحة — أوسع على الشاشات العريضة فلا تلتصق البطاقات بالحافّة.
  double get pageGutter => isWide
      ? AppSpacing.x3l
      : isDesktop
          ? AppSpacing.x2l
          : AppSpacing.page;
}
