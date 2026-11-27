import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/app_tokens_ext.dart';
import 'package:tawrid_app/core/network/api_exception.dart';
import 'package:tawrid_app/models/bonus_tier.dart';
import 'package:tawrid_app/models/enums.dart';
import 'package:tawrid_app/models/sales_offer_models.dart';
import 'package:tawrid_app/repositories/sales_offer_repository.dart';
import 'package:tawrid_app/shared/ui/ui.dart';
import 'package:tawrid_app/shared/utils/export.dart';
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

  /// أقلامٌ يجري تعديلها الآن — لتُعطَّل صفوفُها بدل تجميد الشاشة كلّها.
  ///
  /// تبديلُ قلمٍ لا يصحّ أن يُوقف العرض كلّه: صاحبه قد يُعطّل ثلاثة
  /// تِباعاً، وشاشةٌ تتجمّد عند كل نقرة تجعله ينتظر ثلاث مرات.
  final Set<String> _savingItems = {};

  /// يُرسل تعديلاً على قلمٍ واحد ويُحدّث العرض من الردّ.
  ///
  /// الردّ هو العرض كاملاً، فتُعاد الشاشة من مصدرٍ واحد بلا دمجٍ يدوي
  /// يفترق عن الخادم عند أول حقلٍ يُضاف.
  Future<void> _updateItem(
    SalesOfferItem item, {
    double? unitPrice,
    double? discountPercentage,
    double? quantity,
    List<BonusTier>? bonusTiers,
    bool clearBonus = false,
    bool? isActive,
    String? done,
  }) async {
    if (_savingItems.contains(item.id)) return;
    setState(() => _savingItems.add(item.id));

    try {
      final updated =
          await ref.read(salesOfferRepositoryProvider).updateOfferItem(
                widget.offerId,
                item.id,
                unitPrice: unitPrice,
                discountPercentage: discountPercentage,
                quantity: quantity,
                bonusTiers: bonusTiers,
                clearBonus: clearBonus,
                isActive: isActive,
              );
      if (!mounted) return;
      setState(() => _offer = updated);
      if (done != null) AppSnackbar.success(context, done);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _savingItems.remove(item.id));
    }
  }

  /// حوار تعديل سعر القلم وحسمه.
  Future<void> _editPrice(SalesOfferItem item) async {
    final currency = _offer!.currency;
    final price = TextEditingController(text: formatForInput(item.unitPrice));
    final discount = TextEditingController(
      text: (item.discountPercentage ?? 0) > 0
          ? formatForInput(item.discountPercentage!)
          : '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.surface,
        title: const Text('تعديل السعر'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.medicineName, style: ctx.text.titleSmall),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: price,
                label: 'سعر الوحدة (${currencySymbol(currency)})',
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: discount,
                label: 'نسبة الحسم ٪',
                hint: 'اتركه فارغاً لإلغاء الحسم',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'الصافي هو ما يراه الصيدلي ويُحسَب في سلّته.',
                style: ctx.text.labelSmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () {
              final p = parseDecimalInput(price.text);
              if (p == null || p <= 0) {
                AppSnackbar.error(ctx, 'أدخل سعراً أكبر من صفر');
                return;
              }

              // الحسم الفارغ قرارٌ صريح بإلغائه لا «لا تمسّه»: الحقل
              // معروضٌ بقيمته، وإفراغُه فعلٌ مقصود.
              final d = discount.text.trim().isEmpty
                  ? 0.0
                  : parseDecimalInput(discount.text);
              if (d == null || d < 0 || d > 100) {
                AppSnackbar.error(ctx, 'نسبة الحسم بين صفر ومئة');
                return;
              }

              Navigator.pop(ctx, true);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    final newPrice = parseDecimalInput(price.text);
    final newDiscount = discount.text.trim().isEmpty
        ? 0.0
        : parseDecimalInput(discount.text);

    price.dispose();
    discount.dispose();

    if (saved != true || newPrice == null) return;

    await _updateItem(
      item,
      unitPrice: newPrice,
      discountPercentage: newDiscount,
      done: 'حُفظ السعر',
    );
  }

  /// حوار تعديل بونص القلم — شريحةٌ واحدة «اشترِ N فتأخذ M».
  ///
  /// شريحةٌ واحدة لا سلّم: هذا ما تُنتجه ملفات المستودعات («١٠+١»)،
  /// وهو ما يفهمه الصيدلي. والسلّم المتعدّد يبقى في شاشة إنشاء العرض
  /// لمن يبنيه بيده.
  Future<void> _editBonus(SalesOfferItem item) async {
    final first = item.bonusTiers.isNotEmpty ? item.bonusTiers.first : null;
    final buy = TextEditingController(
      text: first != null ? formatForInput(first.buyQuantity) : '',
    );
    final free = TextEditingController(
      text: first != null ? formatForInput(first.freeQuantity) : '',
    );

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.surface,
        title: const Text('تعديل البونص'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.medicineName, style: ctx.text.titleSmall),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: buy,
                      label: 'اشترِ',
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppTextField(
                      controller: free,
                      label: 'فتأخذ مجاناً',
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'مثال: اشترِ ١٠ فتأخذ ١ — تُحسَب على كامل الكمية في سلّة '
                'الصيدلي.',
                style: ctx.text.labelSmall,
              ),
            ],
          ),
        ),
        actions: [
          if (item.hasBonus)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'clear'),
              child: Text('إزالة البونص',
                  style: TextStyle(color: ctx.tokens.danger)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () {
              final b = parseDecimalInput(buy.text);
              final f = parseDecimalInput(free.text);
              if (b == null || f == null || b <= 0 || f <= 0) {
                AppSnackbar.error(ctx, 'أدخل كميتين أكبر من صفر');
                return;
              }
              Navigator.pop(ctx, 'save');
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    final b = parseDecimalInput(buy.text);
    final f = parseDecimalInput(free.text);

    buy.dispose();
    free.dispose();

    if (result == 'clear') {
      await _updateItem(item, clearBonus: true, done: 'أُزيل البونص');
      return;
    }

    if (result != 'save' || b == null || f == null) return;

    await _updateItem(
      item,
      // التسمية تُبنى هنا وتُعاد من الخادم بعد الحفظ — وهذه نسخةُ
      // الإرسال، لا تصل الشاشة.
      bonusTiers: [
        BonusTier(
          buyQuantity: b,
          freeQuantity: f,
          label: '${formatForInput(b)} + ${formatForInput(f)}',
        ),
      ],
      done: 'حُفظ البونص',
    );
  }

  /// حقائق العرض في ترويسة الـ PDF.
  static List<PdfFact> _exportFacts(SalesOfferDetail o) {
    final active = o.items.where((i) => i.isActive).length;

    return [
      (label: 'الأصناف', value: '${o.items.length}'),
      if (active != o.items.length)
        (label: 'المعروض منها', value: '$active'),
      (label: 'العملة', value: currencySymbol(o.currency)),
      (
        label: 'السريان',
        value: o.expiresAt == null
            ? 'عرض ثابت'
            : '${formatSmartTimestamp(o.startsAt)} → '
                '${formatSmartTimestamp(o.expiresAt!)}'
      ),
      (
        label: 'المناطق',
        value: o.targetRegions.isEmpty
            ? 'كل مناطق الخدمة'
            : '${o.targetRegions.map((r) => r.governorate).toSet().length} محافظة'
      ),
    ];
  }

  /// أعمدة جدول أصناف العرض — للتصديرين معاً.
  ///
  /// القيمة الخام تذهب إلى Excel ليُجمَع عمود السعر ويُرتَّب، والنصّ
  /// المصوغ إلى PDF. ولذلك لا تُبنى النصوص مرّتين.
  static List<ExportColumn<SalesOfferItem>> _itemColumns(String currency) => [
        ExportColumn(
          header: 'الصنف',
          value: (i) => i.medicineName,
          width: 34,
          pdfFlex: 5,
        ),
        ExportColumn(
          header: 'الشركة',
          value: (i) => i.manufacturerName ?? '',
          width: 18,
          pdfFlex: 3,
        ),
        ExportColumn(
          header: 'الكمية',
          value: (i) => i.quantity <= 0 ? 'مفتوحة' : i.quantity,
          text: (i) => i.quantity <= 0
              ? 'مفتوحة'
              : '${formatQuantity(i.quantity)} ${i.unit}',
          width: 12,
        ),
        ExportColumn(
          header: 'سعر الوحدة',
          value: (i) => i.unitPrice,
          text: (i) => formatMoneyWith(i.unitPrice, currency),
          width: 13,
        ),
        ExportColumn(
          header: 'الحسم ٪',
          value: (i) => i.discountPercentage ?? 0,
          text: (i) => (i.discountPercentage ?? 0) > 0
              ? '${formatQuantity(i.discountPercentage!)}٪'
              : '—',
          width: 10,
        ),
        ExportColumn(
          header: 'الصافي',
          value: (i) => _netUnitPrice(i),
          text: (i) => formatMoneyWith(_netUnitPrice(i), currency),
          width: 13,
        ),
        ExportColumn(
          header: 'البونص',
          value: (i) => i.bonusLabel ?? '',
          text: (i) => i.bonusLabel ?? '—',
          width: 14,
        ),
        ExportColumn(
          header: 'الحالة',
          value: (i) => i.isActive ? 'معروض' : 'غير معروض',
          width: 12,
        ),
      ];

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
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExportButton<SalesOfferItem>(
                    compact: true,
                    fileName: 'عرض-${_offer!.title}',
                    title: _offer!.title,
                    // الاسم في الترويسة لا في العنوان الفرعي: موضعٌ
                    // واحد لمُصدِّر التقرير في كل تصدير.
                    issuer: _offer!.warehouseName,
                    subtitle: 'أصناف العرض',
                    sheetName: 'أصناف العرض',
                    facts: _exportFacts(_offer!),
                    columns: _itemColumns(_offer!.currency),
                    rows: _offer!.items,
                  ),
                  IconButton(
                    tooltip: 'التعليقات',
                    icon: const Icon(Icons.chat_bubble_outline, size: 20),
                    onPressed: _openChat,
                  ),
                ],
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
        final main = _MainColumn(
          offer: o,
          saving: _savingItems,
          onToggle: (item) => _updateItem(
            item,
            isActive: !item.isActive,
            done: item.isActive ? 'عُطّل الصنف' : 'فُعّل الصنف',
          ),
          onEditPrice: _editPrice,
          onEditBonus: _editBonus,
        );

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
  const _MainColumn({
    required this.offer,
    required this.saving,
    required this.onToggle,
    required this.onEditPrice,
    required this.onEditBonus,
  });

  final SalesOfferDetail offer;

  /// أقلامٌ يجري حفظها الآن — صفوفُها معطَّلة وحدها.
  final Set<String> saving;

  final ValueChanged<SalesOfferItem> onToggle;
  final ValueChanged<SalesOfferItem> onEditPrice;
  final ValueChanged<SalesOfferItem> onEditBonus;

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
              saving: saving.contains(items[i].id),
              onToggle: () => onToggle(items[i]),
              onEditPrice: () => onEditPrice(items[i]),
              onEditBonus: () => onEditBonus(items[i]),
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
          SizedBox(width: 56, child: Text('معروض', style: style)),
          SizedBox(width: 40, child: Text('#', style: style)),
          Expanded(flex: 5, child: Text('الصنف', style: style)),
          SizedBox(width: 110, child: Text('الكمية', style: style)),
          SizedBox(width: 100, child: Text('سعر الوحدة', style: style)),
          SizedBox(width: 80, child: Text('الحسم', style: style)),
          SizedBox(width: 110, child: Text('الصافي', style: style)),
          SizedBox(width: 130, child: Text('البونص', style: style)),
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
    required this.saving,
    required this.onToggle,
    required this.onEditPrice,
    required this.onEditBonus,
  });

  final int index;
  final SalesOfferItem item;
  final String currency;

  /// يجري حفظ هذا القلم الآن — صفُّه وحده يُعطَّل.
  final bool saving;

  final VoidCallback onToggle;
  final VoidCallback onEditPrice;
  final VoidCallback onEditBonus;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;
    final discount = item.discountPercentage ?? 0;
    final off = !item.isActive;

    // ── المعطَّل يُخفَت ولا يُخفى ──────────────────────────────────────
    // صاحبه يراه ليُعيد تفعيله متى عاد الصنف، والصيدلي لا يراه أصلاً
    // (الخادم يحجبه). وإخفاؤه هنا يجعل إعادة التفعيل مستحيلة.
    final dim = off ? 0.45 : 1.0;

    return Opacity(
      opacity: saving ? 0.6 : 1,
      child: Container(
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
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: Row(
          children: [
            // ── مفتاح العرض ───────────────────────────────────────────
            // أوّل عمودٍ لأنه أعلى القرارات: ما لا يُعرَض لا يعني سعرُه
            // ولا بونصه شيئاً.
            SizedBox(
              width: 56,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Transform.scale(
                        scale: 0.8,
                        alignment: AlignmentDirectional.centerStart,
                        child: Switch(
                          value: item.isActive,
                          onChanged: (_) => onToggle(),
                        ),
                      ),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text('$index',
                  style: context.text.labelSmall?.copyWith(color: tk.hint)),
            ),
            Expanded(
              flex: 5,
              child: Opacity(
                opacity: dim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(item.medicineName,
                              style: context.text.labelMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (off) ...[
                          const SizedBox(width: AppSpacing.sm),
                          StatusBadge(
                            label: 'غير معروض',
                            tone: StatusTone.neutral,
                          ),
                        ],
                      ],
                    ),
                    if ((item.manufacturerName ?? '').isNotEmpty)
                      Text(item.manufacturerName!,
                          style:
                              context.text.labelSmall?.copyWith(color: tk.hint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 110,
              child: Opacity(
                opacity: dim,
                child: Text(
                  // الكمية صفراً تعني مفتوحة لا معدومة — وعرضُها «٠» يقول
                  // للصيدلي إنه لا شيء متاح، وهو عكس المقصود.
                  item.quantity <= 0
                      ? 'مفتوحة'
                      : '${formatQuantity(item.quantity)} ${item.unit}',
                  style: context.text.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // ── السعر والحسم: خليّةٌ واحدة تُنقَر ──────────────────────
            // لأنهما يُحرَّران معاً: «الحسم ١٥٪» لا معنى له بلا السعر
            // الذي يُحسَم منه، وحواران منفصلان يجعلان تصحيح الاثنين
            // نقرتين وحفظين.
            _EditableCell(
              onTap: onEditPrice,
              tooltip: 'تعديل السعر والحسم',
              child: Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Opacity(
                      opacity: dim,
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
                  ),
                  SizedBox(
                    width: 80,
                    child: Opacity(
                      opacity: dim,
                      child: discount > 0
                          ? Text('${formatQuantity(discount)}٪',
                              style: context.text.labelSmall
                                  ?.copyWith(color: tk.success))
                          : Text('—',
                              style: context.text.labelSmall
                                  ?.copyWith(color: tk.hint)),
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Opacity(
                      opacity: dim,
                      child: Text(
                          formatMoneyWith(_netUnitPrice(item), currency),
                          style: context.priceBrandStyle),
                    ),
                  ),
                ],
              ),
            ),

            _EditableCell(
              onTap: onEditBonus,
              tooltip: 'تعديل البونص',
              child: SizedBox(
                width: 130,
                child: Opacity(
                  opacity: dim,
                  child: item.hasBonus
                      ? Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: BonusBadge(
                              label: item.bonusLabel!, compact: true),
                        )
                      : Text('— أضف',
                          style:
                              context.text.labelSmall?.copyWith(color: tk.hint)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// خليّةٌ تُنقَر فتُحرَّر — بقلمٍ ثابتٍ باهت.
///
/// ── لماذا ثابتٌ لا يظهر بالمرور؟ ──────────────────────────────────────
/// كان يظهر بالمرور عبر `MouseRegion` تُبدّل الحالة، فيتبدّل عرض الصفّ
/// بين إطارٍ وآخر. وذاك وحده مقبول — لكنّ الحوار الذي يفتحه النقر
/// يسحب التركيز، فتصل `onExit` بعد أن بُني الحوار فوق الشجرة، ويُطلَب
/// تخطيطٌ من عنصرٍ يُفكَّك:
///
///     RenderFlex overflowed by 99373 pixels
///     '_dependents.isEmpty': is not true
///
/// والشاشة تُغطّى بالأحمر بعد نقرةٍ واحدة على خليّة السعر.
///
/// والقلم الباهت الثابت يُؤدّي الغرض نفسه — يقول «هذه تُنقَر» — بلا
/// حالةٍ تتبدّل أصلاً. وهو أبسط: `StatelessWidget` لا حالة فيه تُفكّ.
class _EditableCell extends StatelessWidget {
  const _EditableCell({
    required this.child,
    required this.onTap,
    required this.tooltip,
  });

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              const SizedBox(width: AppSpacing.xs),
              AppIcon(AppIcons.pencil,
                  size: 11, color: tk.hint.withValues(alpha: 0.7)),
            ],
          ),
        ),
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
