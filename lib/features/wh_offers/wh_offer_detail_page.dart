import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/app_tokens_ext.dart';
import 'package:tawrid_app/core/network/api_exception.dart';
import 'package:tawrid_app/models/enums.dart';
import 'package:tawrid_app/models/sales_offer_models.dart';
import 'package:tawrid_app/repositories/sales_offer_repository.dart';
import 'package:tawrid_app/shared/ui/ui.dart';
import 'package:tawrid_app/shared/utils/money.dart';
import 'package:tawrid_app/shared/utils/relative_time.dart';
import 'package:tawrid_app/shared/widgets/app_states.dart';
import 'package:tawrid_app/shared/widgets/chat_sheet.dart';

double _netUnitPrice(SalesOfferItem i) =>
    i.unitPrice * (1 - (i.discountPercentage ?? 0) / 100);

// تفاصيل العرض عند المستودع (Figma: المستودع / تفاصيل العرض).
//
// تختلف عن تفاصيل العرض عند الصيدلي: هذه شاشة مالكٍ يُراجع ما نشره —
// المناطق المستهدفة، شروط الدفع، وتعليقات الصيدليات وأسئلتها — لا شاشة
// شراء. ولا زرّ «إضافة للطلبية» فيها بطبيعة الحال.
class WhOfferDetailPage extends ConsumerStatefulWidget {
  const WhOfferDetailPage({required this.offerId, super.key});

  final String offerId;

  @override
  ConsumerState<WhOfferDetailPage> createState() => _WhOfferDetailPageState();
}

class _WhOfferDetailPageState extends ConsumerState<WhOfferDetailPage> {
  SalesOfferDetail? _offer;
  bool _loading = true;
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final offer = await ref.read(salesOfferRepositoryProvider).getWarehouseOfferById(widget.offerId);
      if (!mounted) return;
      setState(() {
        _offer = offer;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiException.from(e);
        _loading = false;
      });
    }
  }

  void _openChat() {
    final repo = ref.read(salesOfferRepositoryProvider);
    ChatSheet.show(
      context,
      title: 'تعليقات العرض',
      currentUserType: 'warehouse',
      loadMessages: () => repo.getWarehouseComments(widget.offerId),
      sendMessage: (text) => repo.addWarehouseComment(widget.offerId, text),
    );
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      await ref.read(salesOfferRepositoryProvider).publishOffer(widget.offerId);
      if (!mounted) return;
      AppSnackbar.success(context, 'نُشر العرض — صار مرئياً للصيدليات المستهدفة');
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إيقاف العرض'),
        content:
            const Text('لن تراه الصيدليات بعد الإيقاف، ولا يمكن التراجع عنه.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.colors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إيقاف'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(salesOfferRepositoryProvider).cancelOffer(widget.offerId);
      if (!mounted) return;
      AppSnackbar.success(context, 'أُوقف العرض');
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: InnerTopBar(
        title: 'تفاصيل العرض',
        trailing: _offer == null
            ? null
            : IconButton(
                tooltip: 'التعليقات',
                icon: const Icon(Icons.chat_bubble_outline, size: 20),
                onPressed: _openChat,
              ),
      ),
      body: _buildBody(),
      bottomNavigationBar: _offer == null ? null : _buildActions(),
    );
  }

  /// جسم الشاشة — عمودان على المكتب، عمودٌ على الضيّق.
  ///
  /// كان عموداً واحداً ممدوداً بعرض الشاشة: كل بطاقة صنفٍ تمتدّ ألفاً
  /// وسبعمئة بكسل وفيها اسمٌ وسعر، والباقي فراغ. والمناطق سطرٌ واحد
  /// تتجاور فيه ثلاثون منطقة مفصولةً بنقاط — يُقرأ ولا يُمسَح.
  ///
  /// فصارت الأصناف جدولاً يملأ العرض، والمناطق والشروط في عمودٍ جانبي:
  /// الأول يُمسَح بالعين عموداً عموداً، والثاني يُقرأ مرّةً عند الحاجة.
  Widget _buildBody() {
    if (_loading) return const AppDetailSkeleton();
    if (_error != null) return ErrorState.of(_error!, onRetry: _load);

    final o = _offer!;

    return LayoutBuilder(
      builder: (context, constraints) {
        // تحت ١١٠٠ بكسل يصير عموداً واحداً: العمود الجانبي بعرض ٣٦٠،
        // وما دونه يضغط جدول الأصناف فتتقطّع أسماؤها.
        final wide = constraints.maxWidth >= 1100;

        final side = _SidePanel(offer: o);
        final main = _MainColumn(offer: o);

        if (!wide) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md,
                AppSpacing.page, AppSpacing.x3l),
            children: [
              _OfferHeadline(offer: o),
              const SizedBox(height: AppSpacing.lg),
              side,
              const SizedBox(height: AppSpacing.lg),
              main,
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md,
              AppSpacing.page, AppSpacing.x3l),
          children: [
            _OfferHeadline(offer: o),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: main),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(width: 360, child: side),
              ],
            ),
          ],
        );
      },
    );
  }

  // الإجراءات تتبع الحالة: المسودة تُنشر، والمنشور يُوقَف، وما انتهى أو
  // أُوقف لا إجراء عليه — فلا يظهر شريط أصلاً.
  Widget? _buildActions() {
    final o = _offer!;
    if (o.status == SalesOfferStatus.expired ||
        o.status == SalesOfferStatus.cancelled) {
      return null;
    }

    final cs = context.colors;
    final tk = context.tokens;
    final isDraft = o.status == SalesOfferStatus.draft;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outline)),
          boxShadow: tk.navShadow,
        ),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: AppButton(
                // الخادم لا يتيح تعديل عرض بعد إنشائه، فالزرّ الرئيسي هو
                // النشر للمسودة — ولا نَعِد بـ«تعديل العرض» كما في التصميم.
                label: isDraft ? 'نشر العرض' : 'العرض منشور',
                loading: _busy && isDraft,
                onPressed: isDraft && !_busy ? _publish : null,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: AppButton(
                label: 'إيقاف العرض',
                variant: AppButtonVariant.danger,
                onPressed: _busy ? null : _stop,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ترويسة العرض — العنوان وحاله وحقائقه في شريطٍ واحد.
class _OfferHeadline extends StatelessWidget {
  const _OfferHeadline({required this.offer});

  final SalesOfferDetail offer;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    final (label, tone) = switch (offer.status) {
      SalesOfferStatus.active => ('منشور', StatusTone.success),
      SalesOfferStatus.draft => ('مسودة', StatusTone.neutral),
      SalesOfferStatus.cancelled => ('متوقف', StatusTone.danger),
      SalesOfferStatus.expired => ('منتهٍ', StatusTone.neutral),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(offer.title, style: context.text.titleLarge)),
              const SizedBox(width: AppSpacing.md),
              StatusBadge(label: label, tone: tone),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── الحقائق في صفٍّ لا في أسطر ───────────────────────────────
          // أربعُ حقائقَ قصيرة كانت أربعة أسطر تحت بعضها تأكل ثلث الشاشة.
          // والصفّ يسعها بنظرةٍ واحدة.
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.sm,
            children: [
              _Fact(
                icon: Icons.event_outlined,
                label: 'السريان',
                value: offer.expiresAt == null
                    // العرض الثابت: بدايةٌ بلا نهاية — فلا يُفتعَل له «إلى».
                    ? 'من ${formatSmartTimestamp(offer.startsAt)} · ثابت'
                    : 'من ${formatSmartTimestamp(offer.startsAt)} '
                        'إلى ${formatSmartTimestamp(offer.expiresAt!)}',
              ),
              _Fact(
                icon: Icons.inventory_2_outlined,
                label: 'الأصناف',
                value: '${offer.items.length}',
              ),
              _Fact(
                icon: Icons.payments_outlined,
                label: 'العملة',
                value: currencySymbol(offer.currency),
              ),
              _Fact(
                icon: Icons.link,
                label: 'الوصول',
                value: offer.isPublicInRegion
                    ? 'كل صيدليات المناطق'
                    : 'صيدليات محدَّدة',
              ),
            ],
          ),

          if (offer.bonusMedicineName != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: tk.goldSurface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: tk.gold),
              ),
              child: Row(
                children: [
                  AppIcon(AppIcons.gift, size: 16, color: tk.goldStrong),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'بونص العرض: '
                      '${offer.bonusMedicineQuantity?.toStringAsFixed(0) ?? ''} '
                      '${offer.bonusMedicineUnit ?? ''} '
                      '${offer.bonusMedicineName} مجاناً',
                      style: context.text.bodySmall
                          ?.copyWith(color: tk.goldStrong),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// حقيقةٌ واحدة: تسميةٌ فوق قيمتها.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: tk.hint),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: context.text.labelSmall?.copyWith(color: tk.hint)),
            Text(value, style: context.text.labelMedium),
          ],
        ),
      ],
    );
  }
}

/// العمود الرئيسي — جدول الأصناف.
class _MainColumn extends StatelessWidget {
  const _MainColumn({required this.offer});

  final SalesOfferDetail offer;

  @override
  Widget build(BuildContext context) {
    final items = offer.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: 'أصناف العرض (${items.length})',
          appIcon: AppIcons.pill,
        ),
        const SizedBox(height: AppSpacing.sm),

        if (items.isEmpty)
          const UiEmpty(
            message: 'لا أصناف في هذا العرض',
            description: 'عرضٌ بلا بنود لا يراه صيدلي',
            appIcon: AppIcons.pill,
          )
        else ...[
          // ── جدولٌ لا بطاقات ──────────────────────────────────────────
          // البطاقة تُفرّق أرقام الصنف الواحد في زواياها، فيُقرأ كل صنفٍ
          // وحده. والسؤال هنا مقارنة: «أيُّ صنفٍ أرخص؟ وأيُّها عليه
          // بونص؟» — وهو يُجاب بتمرير النظر على عمود.
          const _ItemsHeader(),
          for (var i = 0; i < items.length; i++)
            _ItemRow(
              index: i + 1,
              item: items[i],
              currency: offer.currency,
            ),
        ],
      ],
    );
  }
}

class _ItemsHeader extends StatelessWidget {
  const _ItemsHeader();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final style = context.text.labelSmall?.copyWith(color: context.tokens.hint);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text('#', style: style)),
          Expanded(flex: 5, child: Text('الصنف', style: style)),
          SizedBox(width: 110, child: Text('الكمية', style: style)),
          SizedBox(width: 100, child: Text('سعر الوحدة', style: style)),
          SizedBox(width: 80, child: Text('الحسم', style: style)),
          SizedBox(width: 110, child: Text('الصافي', style: style)),
          SizedBox(width: 120, child: Text('البونص', style: style)),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.index,
    required this.item,
    required this.currency,
  });

  final int index;
  final SalesOfferItem item;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;
    final discount = item.discountPercentage ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: index.isEven
            ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
            : cs.surface,
        border: Border(
          left: BorderSide(color: cs.outline),
          right: BorderSide(color: cs.outline),
          bottom: BorderSide(color: cs.outline),
        ),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text('$index',
                style: context.text.labelSmall?.copyWith(color: tk.hint)),
          ),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.medicineName,
                    style: context.text.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if ((item.manufacturerName ?? '').isNotEmpty)
                  Text(item.manufacturerName!,
                      style: context.text.labelSmall?.copyWith(color: tk.hint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              // الكمية صفراً تعني مفتوحة لا معدومة — وعرضُها «٠» يقول
              // للصيدلي إنه لا شيء متاح، وهو عكس المقصود.
              item.quantity <= 0
                  ? 'مفتوحة'
                  : '${item.quantity.toStringAsFixed(0)} ${item.unit}',
              style: context.text.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              formatMoneyWith(item.unitPrice, currency),
              style: discount > 0
                  ? context.text.labelSmall?.copyWith(
                      color: tk.hint,
                      decoration: TextDecoration.lineThrough,
                    )
                  : context.text.labelSmall,
            ),
          ),
          SizedBox(
            width: 80,
            child: discount > 0
                ? Text('${discount.toStringAsFixed(0)}٪',
                    style:
                        context.text.labelSmall?.copyWith(color: tk.success))
                : Text('—',
                    style: context.text.labelSmall?.copyWith(color: tk.hint)),
          ),
          SizedBox(
            width: 110,
            child: Text(formatMoneyWith(_netUnitPrice(item), currency),
                style: context.priceBrandStyle),
          ),
          SizedBox(
            width: 120,
            child: item.hasBonus
                ? Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: BonusBadge(label: item.bonusLabel!, compact: true),
                  )
                : Text('—',
                    style: context.text.labelSmall?.copyWith(color: tk.hint)),
          ),
        ],
      ),
    );
  }
}

/// العمود الجانبي — المناطق والشروط.
class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.offer});

  final SalesOfferDetail offer;

  @override
  Widget build(BuildContext context) {
    final hasTerms = offer.upfrontPercentage != null ||
        offer.paymentPeriodDays != null ||
        (offer.consignmentTerms?.isNotEmpty ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RegionsCard(regions: offer.targetRegions),
        if (hasTerms) ...[
          const SizedBox(height: AppSpacing.md),
          _TermsCard(offer: offer),
        ],
      ],
    );
  }
}

/// المناطق المستهدفة — مجموعةً بمحافظاتها.
///
/// كانت سطراً واحداً: «دمشق - المزة · دمشق - المالكي · حلب - السبيل · …»
/// ثلاثون منطقةً مفصولةً بنقاط، يُعاد فيها اسم المحافظة مع كل مدينة.
/// فلا يُعرَف منها بنظرةٍ كم محافظةً يغطّي العرض ولا أيّ مدنٍ منها.
///
/// والتجميع يُجيب الاثنين: المحافظة عنوانٌ وتحته مدنها شرائحَ — ومحافظةٌ
/// بلا مدن تعني «كل مدنها»، وهو فرقٌ كان يضيع في السطر الواحد.
class _RegionsCard extends StatefulWidget {
  const _RegionsCard({required this.regions});

  final List<TargetRegion> regions;

  @override
  State<_RegionsCard> createState() => _RegionsCardState();
}

class _RegionsCardState extends State<_RegionsCard> {
  /// كم مدينةً تُعرَض لكل محافظة قبل الطيّ.
  ///
  /// مستودعٌ يخدم إدلب كاملةً يستهدف مئةً وتسعاً وثمانين مدينة، وعرضُها
  /// كلَّها يُطيل العمود أمتاراً ولا يُفيد: السؤال «أيُّ محافظات؟» لا
  /// «عدّ لي قراها».
  static const int _preview = 24;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final regions = widget.regions;
    final cs = context.colors;
    final tk = context.tokens;

    final byGovernorate = <String, List<String>>{};
    for (final r in regions) {
      byGovernorate
          .putIfAbsent(r.governorate, () => [])
          .addAll([if ((r.city ?? '').isNotEmpty) r.city!]);
    }

    final governorates = byGovernorate.keys.toList()..sort();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(AppIcons.mapPin, size: 16, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                  child:
                      Text('المناطق المستهدفة', style: context.text.labelLarge)),
              if (governorates.isNotEmpty)
                StatusBadge(
                  label: '${governorates.length} محافظة',
                  tone: StatusTone.neutral,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          if (regions.isEmpty)
            Text('كل مناطق خدمتك',
                style: context.text.bodySmall?.copyWith(color: tk.hint))
          else
            for (final g in governorates) ...[
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(g,
                          style: context.text.labelMedium
                              ?.copyWith(color: cs.primary)),
                    ),
                    Text(
                      byGovernorate[g]!.isEmpty
                          ? 'كل المدن'
                          : '${byGovernorate[g]!.length} مدينة',
                      style:
                          context.text.labelSmall?.copyWith(color: tk.hint),
                    ),
                  ],
                ),
              ),
              if (byGovernorate[g]!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Builder(builder: (context) {
                  final cities = byGovernorate[g]!..sort();
                  final shown = _expanded
                      ? cities
                      : cities.take(_preview).toList();
                  final hidden = cities.length - shown.length;

                  return Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final city in shown)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm, vertical: 3),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius:
                                BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(city, style: context.text.labelSmall),
                        ),

                      // الباقي خلف نقرة — لا يُحذف، ولا يُطيل العمود.
                      if (hidden > 0)
                        InkWell(
                          onTap: () => setState(() => _expanded = true),
                          borderRadius:
                              BorderRadius.circular(AppRadius.full),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm, vertical: 3),
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                              border: Border.all(color: cs.outline),
                            ),
                            child: Text('+$hidden أخرى',
                                style: context.text.labelSmall
                                    ?.copyWith(color: cs.primary)),
                          ),
                        ),
                    ],
                  );
                }),
              ],
            ],

          if (_expanded) ...[
            const SizedBox(height: AppSpacing.sm),
            InkWell(
              onTap: () => setState(() => _expanded = false),
              child: Text('طيّ القائمة',
                  style: context.text.labelSmall?.copyWith(color: cs.primary)),
            ),
          ],
        ],
      ),
    );
  }
}

class _TermsCard extends StatelessWidget {
  const _TermsCard({required this.offer});

  final SalesOfferDetail offer;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.handshake_outlined, size: 16, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Text('شروط الدفع', style: context.text.labelLarge),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (offer.upfrontPercentage != null)
            _TermLine(
              label: 'دفعة مقدَّمة',
              value: '${offer.upfrontPercentage!.toStringAsFixed(0)}٪',
            ),
          if (offer.paymentPeriodDays != null)
            _TermLine(
              label: 'مهلة السداد',
              value: '${offer.paymentPeriodDays} يوماً',
            ),
          if (offer.consignmentTerms?.isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(offer.consignmentTerms!,
                style: context.text.bodySmall?.copyWith(color: tk.hint)),
          ],
        ],
      ),
    );
  }
}

class _TermLine extends StatelessWidget {
  const _TermLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: context.text.bodySmall
                    ?.copyWith(color: context.tokens.hint)),
          ),
          Text(value, style: context.text.labelMedium),
        ],
      ),
    );
  }
}
