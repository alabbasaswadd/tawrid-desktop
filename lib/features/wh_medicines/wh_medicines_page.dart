import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tawrid_app/app/router/routes.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/app_tokens_ext.dart';
import 'package:tawrid_app/core/network/api_exception.dart';
import 'package:tawrid_app/models/warehouse_medicine_models.dart';
import 'package:tawrid_app/repositories/warehouse_medicine_repository.dart';
import 'package:tawrid_app/shared/ui/ui.dart';
import 'package:tawrid_app/shared/widgets/barcode_scanner_page.dart';
import 'package:tawrid_app/shared/utils/money.dart';
import 'package:tawrid_app/shared/widgets/app_states.dart';
import 'package:tawrid_app/core/state/inventory_revision.dart';
import 'package:tawrid_app/shared/utils/export.dart';

// أدوية مستودعي (Figma: المستودع / أدوية مستودعي).
//
// قائمة أصناف لا مخزون بكميات. لكل صنف **سعر اختياري**: الصنف المسعَّر يظهر
// للصيدليات في البحث المقارن كـ«تسعير مباشر»، وغير المسعَّر يبقى بياناً
// تعريفياً تُبنى عليه العروض فقط. الكميات تبقى داخل كل عرض بيع.
class WhMedicinesPage extends ConsumerStatefulWidget {
  const WhMedicinesPage({super.key});

  @override
  ConsumerState<WhMedicinesPage> createState() => _WhMedicinesPageState();
}

class _WhMedicinesPageState extends ConsumerState<WhMedicinesPage> {
  List<WarehouseMedicine>? _items;
  bool _loading = true;
  ApiException? _error;
  String _query = '';
  Timer? _debounce;

  /// كم صنفاً في المستودع كلّه — لا كم حُمِّل.
  int _total = 0;

  /// جلب الصفحة التالية جارٍ — يمنع إطلاق طلبين على نفس الإزاحة.
  bool _loadingMore = false;

  /// شبكةٌ أم قائمة. الشبكة افتراض سطح المكتب: أربعمئة صنفٍ في عمودٍ
  /// واحد تمريرٌ لا ينتهي، وفي شبكةٍ لمحةٌ واحدة.
  bool _grid = true;

  static const int _pageSize = 60;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(warehouseMedicineRepositoryProvider)
          .getMinePage(search: _query, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _total = page.total;
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

  /// يجلب الصفحة التالية ويُلحقها.
  ///
  /// كانت القائمة تقف عند خمسين صنفاً بلا أن تقول إنها وقفت: الباقي
  /// موجودٌ في الخادم ولا سبيل إليه من الشاشة.
  Future<void> _loadMore() async {
    final loaded = _items;
    if (_loadingMore || loaded == null || loaded.length >= _total) return;

    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(warehouseMedicineRepositoryProvider)
          .getMinePage(
            search: _query,
            limit: _pageSize,
            offset: loaded.length,
          );
      if (!mounted) return;
      setState(() {
        // الإلحاق على ما في الحالة الآن لا على نسخةٍ قديمة: الحذف أو
        // التسعير قد يجري أثناء الطلب.
        _items = [...(_items ?? const []), ...page.items];
        _total = page.total;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      AppSnackbar.error(context, ApiException.from(e).message);
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    // نصف ثانية: كتابة اسم دواء عربي لا تستحق رحلة شبكة لكل حرف.
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() => _query = v);
      _load(silent: true);
    });
  }

  Future<void> _remove(WarehouseMedicine m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إزالة من أدويتي'),
        content: Text(
            'سيُزال «${m.displayName}» من قائمة أدوية مستودعك. لا يؤثر ذلك '
            'في العروض المنشورة التي تضمّه.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.colors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إزالة'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(warehouseMedicineRepositoryProvider).remove(m.id);
      if (!mounted) return;
      AppSnackbar.success(context, 'أُزيل الدواء من قائمتك');
      await _load(silent: true);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, ApiException.from(e).message);
    }
  }

  // تحرير السعر في حوار صغير: الحقل وحده هو القرار ولا يستحق شاشة.
  // إفراغ الحقل يسحب السعر — يختفي الصنف من بحث الصيدليات ويبقى في قائمتك.
  Future<void> _editPrice(WarehouseMedicine m) async {
    final controller = TextEditingController(
      // لا تدوير: السعر ٢٫٢٥ كان يُعرَض «2»، فيكفي ضغط «حفظ» ليصير اثنين.
      text: m.price == null ? '' : formatForInput(m.price!),
    );

    final result = await showDialog<_PriceResult>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(m.price == null ? 'إضافة سعر' : 'تعديل السعر'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.displayName, style: Theme.of(ctx).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: controller,
              label: 'سعر الوحدة (${currencySymbol(m.currency)})',
              hint: m.currency == 'SYP' ? '12500' : '2.25',
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              // مستودعٌ بعملة غير عملة النشرة لا اشتقاق له أصلاً، فوعدُه
              // بـ«سعر تقديري» عند الإفراغ كذب: الصنف يعود بلا سعر.
              m.needsManualPrice
                  ? 'أسعارك بـ${currencyName(m.currency)} والنشرة الوطنية '
                        'بالليرة، فلا يُشتقّ سعر تقديري — إفراغ الحقل يترك '
                        'الصنف بلا سعر في بحث الصيدليات.'
                  : 'اتركه فارغاً ليعود السعر إلى التقديري (٧٤٪ من سعر '
                        'المستهلك في النشرة).',
              style: Theme.of(ctx).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                Navigator.pop(ctx, const _PriceResult(null));
                return;
              }
              // الفاصلة عشريةٌ لا تُحذَف: `replaceAll(',', '')` كان
              // يحوّل «٣,٥» إلى «٣٥» — عشرةَ أضعاف ما قصده صاحبه،
              // ويذهب إلى الصيدليات بلا تنبيه.
              final value = parseDecimalInput(controller.text);
              if (value == null || value <= 0) {
                AppSnackbar.error(ctx, 'أدخل سعراً أكبر من صفر');
                return;
              }
              Navigator.pop(ctx, _PriceResult(value));
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (result == null) return;

    try {
      await ref
          .read(warehouseMedicineRepositoryProvider)
          .setPrice(m.id, result.value);
      if (!mounted) return;
      AppSnackbar.success(
        context,
        result.value == null ? 'سُحب سعر الصنف' : 'حُفظ السعر',
      );
      await _load(silent: true);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, ApiException.from(e).message);
    }
  }

  // الماسح حقيقي (mobile_scanner): يُعيد الرمز نصاً فنمرّره إلى البحث
  // نفسه — الباركود مجرّد طريقة أسرع لكتابة ما يُبحث عنه.
  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (code == null || code.isEmpty || !mounted) return;
    // لا حقل نصّي مرتبط — يُمرَّر الرمز مباشرة إلى البحث.
    _onSearchChanged(code);
  }

  @override
  Widget build(BuildContext context) {
    // مخزونٌ تغيّر من شاشة الاستيراد — تُعاد القائمة بهدوء بلا مؤشّر
    // تحميلٍ يقطع ما يقرأه المستخدم.
    ref.listen(inventoryRevisionProvider, (_, _) => _load(silent: true));

    final cs = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('أدوية مستودعي'),
        actions: [
          // التصدير أوّل الإجراءات: قائمةُ أسعارٍ تُرسَل إلى صيدليةٍ أو
          // تُراجَع في Excel هي أكثر ما يُطلَب من هذه الشاشة.
          ExportButton<WarehouseMedicine>(
            compact: true,
            fileName: 'أدويتي',
            title: 'أدوية مستودعي',
            sheetName: 'أدويتي',
            facts: [
              (label: 'عدد الأصناف', value: '${(_items ?? const []).length}'),
            ],
            columns: _medicineColumns(),
            rows: _items ?? const [],
          ),
          // زر الكتالوج العام: حدٌّ بلون العلامة — ثانوي لا رئيسي.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Material(
              color: Colors.transparent,
              shape: StadiumBorder(side: BorderSide(color: cs.primary)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () async {
                  await context.push(TRoutes.whMedicineCatalog);
                  if (mounted) await _load(silent: true);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('الكتالوج العام',
                          style: context.text.bodySmall
                              ?.copyWith(color: cs.primary)),
                      const SizedBox(width: 6),
                      AppIcon(AppIcons.package, size: 15, color: cs.primary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final tk = context.tokens;
    final items = _items ?? const <WarehouseMedicine>[];
    final gutter = context.pageGutter;

    // شريط أدواتٍ واحد: بحثٌ واستيرادٌ وتبديل عرضٍ في سطر على الشاشة
    // العريضة، وثلاثة أسطر على الضيّقة. كانت كلٌّ منها سطراً مستقلاً
    // يأكل ثُلث الشاشة قبل أن يظهر صنفٌ واحد.
    final wide = context.isDesktop;

    final search = AppSearchBar(
      hint: 'ابحث في أصناف المخزون…',
      onChanged: _onSearchChanged,
      onScanTap: _scanBarcode,
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ImportButton(onTap: () => context.push(TRoutes.whImportInventory)),
        const SizedBox(width: AppSpacing.sm),
        _ViewToggle(
          grid: _grid,
          onChanged: (v) => setState(() => _grid = v),
        ),
      ],
    );

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, AppSpacing.sm, gutter, 0),
          child: wide
              ? Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: AppSpacing.md),
                    actions,
                  ],
                )
              : Column(
                  children: [
                    search,
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: actions,
                    ),
                  ],
                ),
        ),

        Padding(
          padding: EdgeInsets.fromLTRB(
              gutter, AppSpacing.sm, gutter, AppSpacing.sm),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _countLabel(items.length),
              style: context.text.bodySmall?.copyWith(color: tk.hint),
            ),
          ),
        ),

        Expanded(child: _buildList(items)),
      ],
    );
  }

  /// «٦٠ من ٤١٢ صنفاً» — ما حُمِّل وما يملك، لا خلط بينهما.
  String _countLabel(int shown) {
    if (_loading) return 'جارٍ التحميل…';
    if (_query.trim().isNotEmpty) {
      return shown < _total ? 'عُرض $shown من $_total نتيجة' : '$shown نتيجة';
    }
    if (shown < _total) return 'عُرض $shown من $_total صنفاً في مستودعك';
    return '$shown ${shown == 1 ? 'دواء' : 'دواءً'} في مستودعك';
  }

  /// أعمدة تصدير «أدويتي».
  ///
  /// السعر الخام لا المصوغ في عمود Excel: صاحبه يُرتّب به ويجمعه،
  /// والنصّ المصوغ لا يُرتَّب إلا أبجدياً.
  static List<ExportColumn<WarehouseMedicine>> _medicineColumns() => [
        ExportColumn(
          header: 'الصنف',
          value: (m) => m.displayName,
          width: 34,
          pdfFlex: 5,
        ),
        ExportColumn(
          header: 'المادة الفعّالة',
          value: (m) => m.genericName,
          width: 26,
          pdfFlex: 4,
        ),
        ExportColumn(
          header: 'الشركة',
          value: (m) => m.manufacturerName,
          width: 20,
          pdfFlex: 3,
        ),
        ExportColumn(
          header: 'العيار',
          value: (m) => m.strength > 0 ? m.strength : '',
          text: (m) => m.strength > 0 ? formatQuantity(m.strength) : '—',
          width: 10,
        ),
        ExportColumn(
          header: 'الشكل',
          value: (m) => m.dosageForm.label,
          width: 12,
        ),
        ExportColumn(
          header: 'كود ساكو',
          value: (m) => m.sakoCode,
          width: 12,
        ),
        ExportColumn(
          header: 'السعر',
          value: (m) => m.effectivePrice ?? '',
          text: (m) => m.effectivePrice == null
              ? 'بلا سعر'
              : formatMoneyWith(m.effectivePrice!, m.currency),
          width: 14,
        ),
        ExportColumn(
          header: 'مصدر السعر',
          // الفرق مهمّ عند المراجعة: المشتقّ يتبدّل مع النشرة الوطنية،
          // واليدوي لا يتبدّل إلا بيد صاحبه.
          value: (m) => m.effectivePrice == null
              ? 'غير مسعَّر'
              : (m.isDerivedPrice ? 'مشتقّ' : 'يدوي'),
          width: 12,
        ),
      ];

  Widget _buildList(List<WarehouseMedicine> items) {
    if (_loading) return const AppListSkeleton(variant: SkeletonVariant.row);
    if (_error != null) return ErrorState.of(_error!, onRetry: _load);

    if (items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: AppSpacing.x3l),
          EmptyState(
            icon: Icons.medication_outlined,
            message: _query.trim().isNotEmpty
                ? 'لا دواء يطابق بحثك في أدويتك'
                : 'لا أدوية بعد — أضفها من «الكتالوج العام» لتبني عليها عروضك',
          ),
        ],
      );
    }

    final tk = context.tokens;
    final gutter = context.pageGutter;
    final hasMore = items.length < _total;

    final footer = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasMore) ...[
            Center(
              child: SizedBox(
                width: 320,
                child: AppButton(
                  label: _loadingMore
                      ? 'يُحمِّل…'
                      : 'عرض ${_remaining()} صنفاً إضافياً',
                  variant: AppButtonVariant.outline,
                  appIcon: AppIcons.chevronDown,
                  onPressed: _loadingMore ? null : _loadMore,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          // توضيح ما تعنيه القائمة فعلاً — ليست مخزوناً بكميات وأسعار.
          Text(
            'كل صنف في قائمتك يظهر للصيدليات في البحث المقارن. ما لم تحدّد له '
            'سعراً يُحتسب سعره ٧٤٪ من سعر المستهلك في النشرة الوطنية، '
            'ويبقى سعرك اليدوي — متى أدخلته — هو المعتمد. الكميات تُحدَّد '
            'داخل كل عرض بيع.',
            style: context.text.labelSmall?.copyWith(color: tk.hint),
          ),
        ],
      ),
    );

    return BoardContent(
      child: LayoutBuilder(
        builder: (context, box) {
          // الشبكة تُحسب من العرض المتاح داخل اللوح لا من عرض النافذة:
          // الشريط الجانبي والهوامش تأكل مئتي بكسل، وحسابُها من النافذة
          // يُعطي عموداً زائداً فتُضغط البطاقات.
          final cols = _grid
              ? columnsFor(box.maxWidth - gutter * 2, minTile: 340, max: 5)
              : 1;

          return ListView(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, AppSpacing.x3l),
            children: [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  // ارتفاعٌ ثابت لا نسبة: محتوى البطاقة معروف (اسمٌ
                  // وسطران وسعرٌ وإجراءان)، والنسبة تُطيلها كلّما اتّسعت
                  // الشاشة فتصير مستطيلاتٍ فارغة.
                  mainAxisExtent: _grid ? 150 : 104,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) => _MedicineCard(
                  medicine: items[i],
                  dense: !_grid,
                  onRemove: () => _remove(items[i]),
                  onEditPrice: () => _editPrice(items[i]),
                ),
              ),
              footer,
            ],
          );
        },
      ),
    );
  }

  int _remaining() {
    final shown = _items?.length ?? 0;
    final left = _total - shown;
    return left < _pageSize ? left : _pageSize;
  }
}

/// نتيجة حوار السعر — تميّز «أُلغي الحوار» (null) عن «سُحب السعر» (قيمة
/// بداخلها null)، وهما قراران مختلفان لا يصحّ خلطهما.
class _PriceResult {
  const _PriceResult(this.value);
  final double? value;
}

class _MedicineCard extends StatelessWidget {
  const _MedicineCard({
    required this.medicine,
    required this.onRemove,
    required this.onEditPrice,
    this.dense = false,
  });

  final WarehouseMedicine medicine;
  final VoidCallback onRemove;
  final VoidCallback onEditPrice;

  /// صفٌّ منخفض لعرض القائمة — الوصف سطرٌ واحد والهوامش أضيق.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;
    final m = medicine;

    final spec = [
      if (m.genericName.isNotEmpty) m.genericName,
      m.dosageForm.label,
      if (m.manufacturerName.isNotEmpty) m.manufacturerName,
    ].join(' · ');

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.displayName,
                        style: context.text.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(spec,
                        style:
                            context.text.bodySmall?.copyWith(color: tk.hint),
                        maxLines: dense ? 1 : 2,
                        overflow: TextOverflow.ellipsis),
                    // الصنف الحرّ لا كود ساكو له — وسطرٌ فارغ مكانه
                    // يُوحي ببيانٍ ناقص، فيُستبدل بوسمٍ يقول ما هو.
                    if (m.sakoCode.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('كود ساكو: ${m.sakoCode}',
                          style: context.text.labelSmall
                              ?.copyWith(color: tk.hint)),
                    ] else if (m.isCatalogFree && !dense) ...[
                      const SizedBox(height: AppSpacing.xs),
                      const StatusBadge(
                          label: 'صنف خاص بك', tone: StatusTone.neutral),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // السعر أولاً: هو ما تراه الصيدليات. وحين لا يُدخله
                  // المستودع يدوياً يُشتقّ من سعر المستهلك (٧٤٪) — فلا
                  // يظنّ صنفه بلا سعر بينما يُباع فعلاً بسعر مشتقّ.
                  if (m.effectivePrice != null)
                    Text(
                      formatMoneyWith(m.effectivePrice!, m.currency),
                      style: context.priceStyle,
                    )
                  // سببان مختلفان لغياب السعر وعلاجهما مختلف: اختلافُ
                  // العملة يحلّه المستودع بإدخال سعر، وغيابُ سعر المستهلك
                  // لا حيلة فيه.
                  else if (m.needsManualPrice)
                    Text(
                      'سعّره بنفسك',
                      style: context.text.labelSmall
                          ?.copyWith(color: tk.warning),
                    )
                  else
                    Text(
                      'لا سعر ولا نشرة',
                      style: context.text.labelSmall?.copyWith(color: tk.hint),
                    ),
                  if (m.isDerivedPrice)
                    Text(
                      'تقديري (٧٤٪ من سعر المستهلك)',
                      style: context.text.labelSmall?.copyWith(color: tk.hint),
                    ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: onEditPrice,
                        style: _denseButton,
                        child: Text(
                          m.price == null ? 'حدّد سعراً' : 'تعديل',
                          style:
                              context.text.bodySmall?.copyWith(color: cs.primary),
                        ),
                      ),
                      TextButton(
                        onPressed: onRemove,
                        style: _denseButton,
                        child: Text(
                          'إزالة',
                          style:
                              context.text.bodySmall?.copyWith(color: cs.error),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // إجراءان متجاوران داخل بطاقة — الحشوة الافتراضية تجعلهما يزاحمان النص.
  static final ButtonStyle _denseButton = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

/// زرّ الاستيراد — زرٌّ لا شريحةٌ ممتدّة بعرض الشاشة.
///
/// كان شريطاً يمتدّ بعرض المكتب كلّه لجملةٍ من أربع كلمات، وهو الشكل
/// الذي يجعل الشاشة تبدو هاتفاً مكبَّراً: عنصرٌ بُني لعرض ٣٦٠ بكسل
/// مشدودٌ إلى ١٧٠٠.
class _ImportButton extends StatelessWidget {
  const _ImportButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return Tooltip(
      message: 'استيراد المخزون من ملف Excel',
      child: Material(
        color: tk.brandSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(AppIcons.fileImport, size: 18, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'استيراد مخزون',
                  style: context.text.labelMedium?.copyWith(color: cs.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// مبدّل شبكة/قائمة — زوجُ أيقوناتٍ بطراز سطح المكتب.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.grid, required this.onChanged});

  final bool grid;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    Widget seg(AppIcons icon, bool active, String tip, VoidCallback onTap) =>
        Tooltip(
          message: tip,
          child: InkWell(
            onTap: active ? null : onTap,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: 11),
              decoration: BoxDecoration(
                color: active ? cs.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                boxShadow: active ? tk.cardShadow : null,
              ),
              child: AppIcon(icon,
                  size: 18, color: active ? cs.primary : tk.hint),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tk.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(AppIcons.layoutGrid, grid, 'عرض شبكي', () => onChanged(true)),
          seg(AppIcons.listRows, !grid, 'عرض قائمة', () => onChanged(false)),
        ],
      ),
    );
  }
}

