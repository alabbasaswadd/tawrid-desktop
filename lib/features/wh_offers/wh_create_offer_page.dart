import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/app_tokens_ext.dart';
import 'package:tawrid_app/core/network/api_exception.dart';
import 'package:tawrid_app/models/bonus_tier.dart';
import 'package:tawrid_app/models/sales_offer_models.dart';
import 'package:tawrid_app/models/warehouse_medicine_models.dart';
import 'package:tawrid_app/repositories/sales_offer_repository.dart';
import 'package:tawrid_app/repositories/warehouse_medicine_repository.dart';
import 'package:tawrid_app/repositories/warehouse_settings_repository.dart';
import 'package:tawrid_app/shared/ui/ui.dart';
import 'package:tawrid_app/shared/widgets/app_states.dart';
import 'package:tawrid_app/shared/widgets/medicine_list_tile.dart';
import 'package:tawrid_app/shared/utils/money.dart';
import 'package:tawrid_app/shared/utils/offer_rules.dart';
import 'package:tawrid_app/shared/widgets/multi_region_picker.dart';

// إنشاء عرض بيع — اختيار الأصناف يتم من أدوية المستودع المُضافة مسبقاً
// (wh_medicines_page.dart) فقط، لا كتابة حرّة ولا من الكاتالوج العام
// مباشرة.
class WhCreateOfferPage extends ConsumerStatefulWidget {
  const WhCreateOfferPage({super.key});

  @override
  ConsumerState<WhCreateOfferPage> createState() => _WhCreateOfferPageState();
}

/// شريحة بونص قيد التحرير: «اشترِ [buy] واحصل على [free] مجاناً».
class _BonusTierDraft {
  _BonusTierDraft()
      : buy = TextEditingController(),
        free = TextEditingController();

  final TextEditingController buy;
  final TextEditingController free;

  bool get isEmpty => buy.text.trim().isEmpty && free.text.trim().isEmpty;

  BonusTier? toTier() {
    final b = parseDecimalInput(buy.text);
    final f = parseDecimalInput(free.text);
    if (b == null || f == null || b <= 0 || f <= 0) return null;
    return BonusTier(buyQuantity: b, freeQuantity: f, label: '');
  }

  void dispose() {
    buy.dispose();
    free.dispose();
  }
}

class _OfferItemDraft {
  _OfferItemDraft(this.medicine, {double? defaultPrice, String currency = 'SYP'})
      : unit = TextEditingController(text: 'علبة'),
        quantity = TextEditingController(text: '100'),
        unitPrice = TextEditingController(
          text: defaultPrice != null && defaultPrice > 0
              // بمنازل العملة: تقريبُ 2.25 إلى «2» كان يُسقط سعر العرض
              // الافتراضي على رقم آخر قبل أن يراه المستودع.
              ? formatAmount(defaultPrice, currency).replaceAll(',', '')
              : '',
        ),
        discount = TextEditingController();

  final WarehouseMedicine medicine;
  final TextEditingController unit;
  final TextEditingController quantity;
  final TextEditingController unitPrice;
  final TextEditingController discount;
  bool isOpenQuantity = false;

  /// سلّم البونص لهذا الصنف — «(10+5) (5+2) (3+1)». فارغ = لا بونص.
  final List<_BonusTierDraft> bonusTiers = [];

  /// الشرائح الصالحة وحدها تُرسَل؛ الصفّ الفارغ يُهمَل بلا خطأ.
  List<BonusTier> validTiers() =>
      bonusTiers.map((t) => t.toTier()).whereType<BonusTier>().toList();

  /// صفٌّ مملوء جزئياً (كمية بلا مقابلها) — خطأُ إدخال لا إغفال.
  bool get hasIncompleteTier =>
      bonusTiers.any((t) => !t.isEmpty && t.toTier() == null);

  /// كميتا شراء متساويتان في سلّم واحد تناقضٌ لا خيار — والخادم يرفضه.
  bool get hasDuplicateTier {
    final buys = validTiers().map((t) => t.buyQuantity).toList();
    return buys.toSet().length != buys.length;
  }

  void dispose() {
    unit.dispose();
    quantity.dispose();
    unitPrice.dispose();
    discount.dispose();
    for (final t in bonusTiers) {
      t.dispose();
    }
  }
}

class _WhCreateOfferPageState extends ConsumerState<WhCreateOfferPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _upfrontPercentage = TextEditingController();
  final _paymentPeriodDays = TextEditingController();
  final _consignmentTerms = TextEditingController();

  DateTime _startsAt = DateTime.now();
  DateTime _expiresAt = DateTime.now().add(const Duration(days: 7));

  /// نوع العرض. الثابت يُرسَل بلا تاريخ انتهاء — وهو ما يجعله ثابتاً في
  /// الخادم (لا حقلَ «نوع» منفصلاً يناقض التاريخ).
  SalesOfferKind _kind = SalesOfferKind.timeLimited;

  /// عملة تسعير المستودع — تُعرَض ولا تُختار: الخادم يفرضها ويتجاهل أي
  /// عملة في جسم الطلب، فمنتقي عملةٍ هنا كان يَعِد بتحكّمٍ لا وجود له.
  /// تبديلها من «إعدادات الطلبيات».
  String _currency = 'SYP';
  List<TargetRegion> _targetRegions = [];
  final List<_OfferItemDraft> _items = [];
  bool _saving = false;

  // بونص على مستوى العرض كله = دواء مجاني (اختياري)
  WarehouseMedicine? _bonusMedicine;
  final _bonusQuantity = TextEditingController(text: '1');
  final _bonusUnit = TextEditingController(text: 'علبة');

  @override
  void initState() {
    super.initState();
    _loadCurrency();
  }

  Future<void> _loadCurrency() async {
    try {
      final settings = await ref.read(warehouseSettingsRepositoryProvider).get();
      if (!mounted) return;
      setState(() => _currency = settings.pricingCurrency);
    } catch (_) {
      // تعذّر جلب العملة لا يمنع إنشاء العرض: الخادم يفرضها على أي حال،
      // وكل ما يضيع هنا هو دقّة الرمز المعروض بجانب الحقول.
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _upfrontPercentage.dispose();
    _paymentPeriodDays.dispose();
    _consignmentTerms.dispose();
    _bonusQuantity.dispose();
    _bonusUnit.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startsAt : _expiresAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startsAt = picked;
      } else {
        _expiresAt = picked;
      }
    });
  }

  Future<void> _addMedicine() async {
    final picked = await showModalBottomSheet<List<WarehouseMedicine>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _MedicinePickerSheet(
        alreadyPicked: _items.map((d) => d.medicine.id).toSet(),
      ),
    );
    if (picked != null && picked.isNotEmpty) {
      setState(() => _items.addAll(picked.map((m) => _OfferItemDraft(
            m,
            // السعر المقترح هو سعر بيع المستودع نفسه: اليدوي إن حدّده،
            // وإلا ٧٤٪ من سعر المستهلك في النشرة. هو الرقم الذي تراه
            // الصيدليات في البحث المقارن، فيبدأ العرض منه بدل حقل فارغ —
            // والمستودع يعدّله إن أراد سعراً خاصاً بالعرض.
            defaultPrice: m.effectivePrice,
          ))));
    }
  }

  Future<void> _pickBonusMedicine() async {
    final picked = await showModalBottomSheet<List<WarehouseMedicine>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const _MedicinePickerSheet(alreadyPicked: {}, single: true),
    );
    if (picked != null && picked.isNotEmpty) {
      setState(() => _bonusMedicine = picked.first);
    }
  }

  void _removeItem(_OfferItemDraft draft) {
    setState(() {
      _items.remove(draft);
      draft.dispose();
    });
  }

  Future<void> _submit() async {
    // ── المراحل الثلاث تُفحَص لا المرئيّة وحدها ────────────────────────
    // الإرسال يقع من «المراجعة»، وحقولُ العنوان والأصناف ليست في الشجرة
    // حينها — فـ`_formKey.validate()` كان يعود صادقاً عنها كلّها.
    // والحارس يقرأ النموذج، ورسالتُه تسمّي الصنف بدل أن يردّ الخادم
    // برسالةٍ عامّة بعد رحلة شبكة.
    final blocker = _allStepsBlocker();
    if (blocker != null) {
      AppSnackbar.error(context, blocker);
      return;
    }

    setState(() => _saving = true);
    try {
      final items = _items
          .map((d) => SalesOfferItem(
                id: '',
                medicineName: d.medicine.displayName,
                catalogItemId: d.medicine.catalogItemId,
                quantity: d.isOpenQuantity ? 0 : (parseDecimalInput(d.quantity.text) ?? 1),
                unit: d.unit.text.trim(),
                unitPrice: parseDecimalInput(d.unitPrice.text) ?? 0,
                discountPercentage:
                    d.discount.text.trim().isEmpty ? null : parseDecimalInput(d.discount.text),
                bonusTiers: d.validTiers(),
              ))
          .toList();

      await ref.read(salesOfferRepositoryProvider).createOffer(
            title: _title.text.trim(),
            description: _description.text.trim().isEmpty ? null : _description.text.trim(),
            startsAt: _startsAt,
            expiresAt:
                _kind == SalesOfferKind.standing ? null : _expiresAt,
            targetRegions: _targetRegions,
            // الحقل مُبقًى في الطلب لأن أمر الخادم يطلبه، لكنه لا أثر له:
            // حارس الرؤية يتجاهله ويعرض العرض لكل صيدلية تغطّيها مناطقه
            // المستهدَفة. إرسال true يطابق السلوك الفعلي بدل مفتاح يوهم
            // المستخدم بتحكّمٍ لا يملكه.
            isPublicInRegion: true,
            upfrontPercentage: _upfrontPercentage.text.trim().isEmpty
                ? null
                : parseDecimalInput(_upfrontPercentage.text),
            paymentPeriodDays: _paymentPeriodDays.text.trim().isEmpty
                ? null
                : int.tryParse(_paymentPeriodDays.text),
            consignmentTerms:
                _consignmentTerms.text.trim().isEmpty ? null : _consignmentTerms.text.trim(),
            items: items,
            bonusMedicineName: _bonusMedicine?.displayName,
            bonusMedicineCatalogItemId: _bonusMedicine?.catalogItemId,
            bonusMedicineQuantity:
                _bonusMedicine == null ? null : (parseDecimalInput(_bonusQuantity.text) ?? 1),
            bonusMedicineUnit: _bonusMedicine == null ? null : _bonusUnit.text.trim(),
          );

      if (mounted) {
        // الخادم يُنشئ العرض بحالة «مسودة» لا «منشور»، فقول «تم الإنشاء»
        // وحده يترك المستودع ينتظر طلبيات على عرض لا تراه أي صيدلية.
        AppSnackbar.success(
            context, 'حُفظ العرض كمسودة — اضغط «نشر» ليصل الصيدليات');
        context.pop();
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// مرحلة المعالج الحالية.
  _OfferStep _step = _OfferStep.basics;

  /// حارسُ كل مرحلة — فارغٌ إن صلحت، وإلا سببُ تعذّرها.
  ///
  /// يُحسب ولا يُخزَّن: الحقول تتبدّل مع كل حرف، وحالةٌ محفوظة تتخلّف
  /// عنها بإطار.
  String? _blockerOf(_OfferStep step) => switch (step) {
        _OfferStep.basics => _title.text.trim().isEmpty
            ? 'اكتب عنواناً للعرض'
            : _targetRegions.isEmpty
                ? 'اختر منطقةً مستهدفة واحدة على الأقل'
                : _kind == SalesOfferKind.timeLimited &&
                        !_expiresAt.isAfter(_startsAt)
                    ? 'تاريخ الانتهاء يجب أن يلي تاريخ البدء'
                    : null,
        _OfferStep.items => _items.isEmpty
            ? 'أضف صنفاً واحداً على الأقل'
            : _itemsDataBlocker(),
        _OfferStep.review => null,
      };

  /// ── لماذا يُقرأ النموذج لا الحقول ──────────────────────────────────────
  ///
  /// `_formKey.validate()` لا يرى إلا ما هو مركَّبٌ في الشجرة الآن. والشاشة
  /// ثلاث مراحل تُبدَّل لا تُكدَّس، فحقول الأصناف غير موجودةٍ لحظةَ الإرسال
  /// من مرحلة «المراجعة» — وكل حارسٍ عليها يمرّ بلا أن يُنفَّذ.
  ///
  /// والقراءة من المسوّدات تنجو من ذلك: هي حالةُ الشاشة، باقيةٌ بين
  /// المراحل، فالحكم عليها حكمٌ على ما سيُرسَل فعلاً.
  ///
  /// والحدود هنا تطابق مدقّق الخادم حرفاً بحرف — الرحلة إلى الخادم لتكتشف
  /// خطأً تعرفه الشاشة هدرٌ، ورسالتُه لا تُسمّي الصنف.
  String? _itemsDataBlocker() {
    for (final d in _items) {
      final name = d.medicine.displayName;

      if (OfferRules.unit(d.unit.text) != null) {
        return 'حدّد وحدة الصنف في «$name»';
      }

      if (OfferRules.unitPrice(d.unitPrice.text) != null) {
        return 'سعر الوحدة في «$name» يجب أن يكون أكبر من صفر';
      }

      if (OfferRules.quantity(d.quantity.text, open: d.isOpenQuantity) != null) {
        return 'الكمية في «$name» غير صالحة — أو علّم «كمية مفتوحة»';
      }

      if (OfferRules.discount(d.discount.text) != null) {
        return 'نسبة الحسم في «$name» يجب أن تكون بين ٠ و١٠٠';
      }

      if (d.hasIncompleteTier) {
        return 'أكمِل شريحة البونص في «$name» — كلّ شريحة تحتاج كمية '
            'شراء وكمية مجانية، كلتاهما أكبر من صفر.';
      }

      if (d.hasDuplicateTier) {
        return 'في «$name» شريحتان بنفس كمية الشراء — اجعل لكل كمية '
            'شريحةً واحدة.';
      }
    }

    // هديّة العرض: اسمٌ بلا كمية نصفُ هديّة.
    if (OfferRules.bonusQuantity(_bonusQuantity.text,
            hasMedicine: _bonusMedicine != null) !=
        null) {
      return 'حدّد كمية دواء الهديّة «${_bonusMedicine!.displayName}»';
    }

    return null;
  }

  /// حارسُ المراحل الثلاث مجتمعةً — ما يُقرأ من النموذج لا من الشجرة.
  String? _allStepsBlocker() =>
      _blockerOf(_OfferStep.basics) ??
      _blockerOf(_OfferStep.items) ??
      _paymentTermsBlocker();

  /// شروط الدفع — حقولها في المرحلة الأولى فلا تُرى عند الإرسال.
  String? _paymentTermsBlocker() {
    if (OfferRules.upfrontPercentage(_upfrontPercentage.text) != null) {
      return 'نسبة الدفع المقدَّم يجب أن تكون بين ٠ و١٠٠';
    }

    if (OfferRules.paymentPeriodDays(_paymentPeriodDays.text) != null) {
      return 'مدّة السداد يجب أن تكون بين ٠ و'
          '${OfferRules.maxPaymentPeriodDays} يوماً';
    }

    return null;
  }

  /// ينتقل إلى المرحلة التالية بعد التحقّق من الحالية.
  void _next() {
    final blocker = _blockerOf(_step);
    if (blocker != null) {
      AppSnackbar.error(context, blocker);
      return;
    }

    // التحقّق النحوي للحقول مع حارس المرحلة: الأول يُمسك الصيغ
    // (رقمٌ في حقل نصّ) ويُلوّن الحقل نفسه، والثاني يُمسك المعنى
    // (لا صنف، لا منطقة). ويُشغَّل في المرحلتين لا في الأولى وحدها —
    // حقول الأصناف تختفي من الشجرة بعد تجاوزها فلا يُلوّنها شيء بعدُ.
    if (_step != _OfferStep.review &&
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _step = switch (_step) {
          _OfferStep.basics => _OfferStep.items,
          _OfferStep.items => _OfferStep.review,
          _OfferStep.review => _OfferStep.review,
        });
  }

  void _back() => setState(() => _step = switch (_step) {
        _OfferStep.review => _OfferStep.items,
        _OfferStep.items => _OfferStep.basics,
        _OfferStep.basics => _OfferStep.basics,
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('عرض بيع جديد')),

      // SingleChildScrollView لا ListView: الأخيرة تُزيل الحقول الخارجة عن
      // الشاشة من الشجرة، فتُلغى تسجيلها في الـForm ويتخطّاها `validate()`
      // ويُرجع true. كان الأثر أن عرضاً بعنوان فارغ يُرسَل ويردّه الخادم
      // بـ400 — الحقل كان قد اختفى حين وصل المستخدم إلى زر الحفظ.
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            _OfferStepBar(
              current: _step,
              onPick: (s) => setState(() => _step = s),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                    AppSpacing.lg, AppSpacing.page, AppSpacing.xl),
                child: Center(
                  child: ConstrainedBox(
                    // ── عرضٌ محدود للنموذج ────────────────────────────
                    // حقلُ نصٍّ بعرض ألفٍ وسبعمئة بكسل يُقرأ بصعوبة،
                    // والعين تضيع بين تسميته وقيمته. والجداول وحدها
                    // تتّسع — وهي في مرحلة المراجعة.
                    constraints: BoxConstraints(
                      maxWidth:
                          _step == _OfferStep.basics ? 760 : 1200,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: switch (_step) {
                        _OfferStep.basics => _basicsStep(context),
                        _OfferStep.items => _itemsStep(context),
                        _OfferStep.review => _reviewStep(context),
                      },
                    ),
                  ),
                ),
              ),
            ),

            // ── شريط الإجراء ثابتٌ أسفل الشاشة ──────────────────────
            // كان زرّ النشر في ذيل نموذجٍ طويل: من أضاف عشرين صنفاً
            // يُمرّر شاشتين ليجده.
            _OfferActionBar(
              step: _step,
              blocker: _blockerOf(_step),
              saving: _saving,
              itemCount: _items.length,
              onBack: _step == _OfferStep.basics ? null : _back,
              onNext: _step == _OfferStep.review ? null : _next,
              onSubmit: _step == _OfferStep.review ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }

  /// المرحلة الأولى: بيانات العرض ومَن يراه وشروط دفعه.
  List<Widget> _basicsStep(BuildContext context) => [
            _Section(
              title: 'بيانات العرض',
              children: [
                AppTextField(
                  controller: _title,
                  label: 'عنوان العرض',
                  hint: 'مثال: حزمة المضادات الحيوية',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _description,
                  label: 'وصف (اختياري)',
                  hint: 'ما يميّز هذا العرض',
                ),
                const SizedBox(height: AppSpacing.md),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'العملة',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  child: Text(
                    '${currencyName(_currency)} (${currencySymbol(_currency)})',
                    style: context.text.bodyMedium,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'عملة أسعارك كلها — تُبدَّل من «إعدادات الطلبيات» لا لكل '
                  'عرض على حدة.',
                  style: context.text.labelSmall
                      ?.copyWith(color: context.tokens.hint),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('نوع العرض', style: context.text.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final k in SalesOfferKind.values)
                      AppFilterChip(
                        label: k.label,
                        selected: _kind == k,
                        onTap: () => setState(() => _kind = k),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _kind == SalesOfferKind.standing
                      ? 'عرض ثابت: يبقى سارياً حتى تُلغيه بنفسك — كنشرة '
                            'أسعارٍ دائمة، بلا تاريخ انتهاء.'
                      : 'عرض لفترة محدّدة: ينتهي تلقائياً عند تاريخه '
                            'ويختفي عن الصيدليات.',
                  style: context.text.labelSmall
                      ?.copyWith(color: context.tokens.hint),
                ),

                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: _DatePickerField(label: 'يبدأ في', date: _startsAt, onTap: () => _pickDate(isStart: true))),
                    if (_kind == SalesOfferKind.timeLimited) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: _DatePickerField(label: 'ينتهي في', date: _expiresAt, onTap: () => _pickDate(isStart: false))),
                    ],
                  ],
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),
            _Section(
              title: 'من يرى العرض',
              children: [
                Text('المنطقة المستهدفة (يمكن إضافة أكثر من محافظة/مدينة)',
                    style: context.text.labelMedium),
                const SizedBox(height: AppSpacing.xs),
                MultiRegionPicker(
                  regions: _targetRegions,
                  onChanged: (v) => setState(() => _targetRegions = v),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'يراه كل صيدلية تقع ضمن المناطق المختارة.',
                  style: context.text.labelSmall
                      ?.copyWith(color: context.tokens.hint),
                ),
              ],
            ),

            // شروط الدفع صارت اختيارية لكل عرض بعد حذف «نوع العرض»
            const SizedBox(height: AppSpacing.md),
            _Section(
              title: 'شروط الدفع (اختيارية)',
              children: [
                // الحقلان كانا بلا حارسٍ على الطرفين: «دفعة مقدَّمة ٥٠٠٪»
                // و«مدّة سداد −٣٠ يوماً» تُحفظان وتُعرضان على الصيدلي.
                AppTextField(
                  controller: _upfrontPercentage,
                  label: 'نسبة الدفع المقدَّم (%)',
                  hint: '0',
                  keyboardType: TextInputType.number,
                  validator: OfferRules.upfrontPercentage,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _paymentPeriodDays,
                  label: 'مدة السداد (أيام)',
                  hint: '30',
                  keyboardType: TextInputType.number,
                  validator: OfferRules.paymentPeriodDays,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _consignmentTerms,
                  label: 'الشروط (اختياري)',
                  hint: 'تفاصيل إضافية للاتفاق',
                ),
              ],
            ),

      ];

  /// المرحلة الثانية: الأصناف وبونص العرض.
  List<Widget> _itemsStep(BuildContext context) => [
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Text(
                  _items.isEmpty
                      ? 'أصناف العرض'
                      : 'أصناف العرض (${_items.length})',
                  style: context.text.titleLarge,
                ),
                const SizedBox(width: AppSpacing.md),

                // ── الزرّ بارزٌ لا نصٌّ باهت ────────────────────────────
                // هو الفعل الذي لا يقوم العرض بدونه: عرضٌ بلا أصناف
                // يرفضه الخادم. وكان `TextButton` في طرف السطر يُقرأ
                // رابطاً ثانوياً.
                FilledButton.icon(
                  onPressed: _addMedicine,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(_items.isEmpty ? 'اختر الأصناف' : 'أضف المزيد'),
                ),
              ],
            ),

            // الرقم المقترح ليس التزاماً: نقول من أين جاء حتى يعرف المستودع
            // ما الذي يعدّله حين يعدّله.
            if (_items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                    top: AppSpacing.xs, bottom: AppSpacing.sm, right: 2),
                child: Text(
                  'سعر الوحدة مقترح من سعر بيعك للصنف (٧٤٪ من سعر المستهلك '
                  'ما لم تحدّد سعراً) — عدّله كما تشاء.',
                  style: context.text.labelSmall
                      ?.copyWith(color: context.tokens.hint),
                ),
              ),

            if (_items.isEmpty)
              // ── حالةٌ فارغة تدعو إلى الفعل لا تصفه ────────────────────
              // «لم تُضف أصناف بعد» تقول ما لم يحدث ولا تقول ما يُفعَل.
              // وهذه تقول من أين تأتي الأصناف وكيف تُنتقى.
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: InkWell(
                  onTap: _addMedicine,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.x2l),
                    decoration: BoxDecoration(
                      color: context.tokens.brandSurface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: context.colors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.medication_outlined,
                            size: 32, color: context.colors.primary),
                        const SizedBox(height: AppSpacing.sm),
                        Text('انتقِ أصنافك من «أدويتي»',
                            style: context.text.titleSmall),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'تُحدّد عدّةً دفعةً واحدة، ثم تضبط سعر كلٍّ وبونصه.',
                          style: context.text.bodySmall
                              ?.copyWith(color: context.tokens.hint),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              ..._items.map((draft) => _OfferItemCard(
                    draft: draft,
                    onRemove: () => _removeItem(draft),
                  )),

            const SizedBox(height: AppSpacing.lg),
            Text('بونص العرض (دواء مجاني — اختياري)',
                style: context.text.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            if (_bonusMedicine == null)
              OutlinedButton.icon(
                onPressed: _pickBonusMedicine,
                icon: const Icon(Icons.card_giftcard_outlined),
                label: const Text('إضافة دواء بونص'),
              )
            else
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: context.tokens.success.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.tokens.success.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.card_giftcard, size: 18, color: context.tokens.success),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_bonusMedicine!.displayName,
                              style: Theme.of(context).textTheme.titleSmall),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, size: 18, color: context.colors.error),
                          onPressed: () => setState(() => _bonusMedicine = null),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _bonusQuantity,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'كمية البونص', isDense: true),
                            // اسمٌ بلا كمية نصفُ هديّة: تُعرض على الصيدلي
                            // ناقصةً فلا يعرف ماذا ينال.
                            validator: (v) => OfferRules.bonusQuantity(
                                v, hasMedicine: _bonusMedicine != null),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: TextFormField(
                            controller: _bonusUnit,
                            decoration: const InputDecoration(labelText: 'الوحدة', isDense: true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

      ];

  /// المرحلة الثالثة: ما سيُنشأ، معروضاً كما سيراه الصيدلي.
  ///
  /// ── لماذا مرحلةٌ لا زرُّ تأكيد؟ ──────────────────────────────────────
  /// العرض يُنشأ بعشرين صنفاً وأسعارٍ وبونصاتٍ ومناطقَ ومدّة — وكلُّها
  /// وعدٌ لصيدليات. وزرُّ «هل أنت متأكد؟» يسأل عمّا لا يُرى، فيُجاب
  /// بنعمٍ بلا قراءة.
  ///
  /// وهذه تعرض الحصيلة: جدولُ الأصناف بصافي أسعارها، والمناطقُ معدودة،
  /// والمدّة بتاريخيها. فالتأكيد على ما رآه صاحبه.
  List<Widget> _reviewStep(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    final governorates =
        _targetRegions.map((r) => r.governorate).toSet().length;

    return [
      Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: tk.brandSurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title.text.trim(), style: context.text.titleLarge),
            if (_description.text.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(_description.text.trim(),
                  style: context.text.bodySmall?.copyWith(color: tk.hint)),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.sm,
              children: [
                _ReviewFact(
                  icon: Icons.inventory_2_outlined,
                  label: 'الأصناف',
                  value: '${_items.length}',
                ),
                _ReviewFact(
                  icon: Icons.event_outlined,
                  label: 'السريان',
                  value: _kind == SalesOfferKind.standing
                      ? 'عرض ثابت بلا نهاية'
                      : '${_day(_startsAt)} → ${_day(_expiresAt)}',
                ),
                _ReviewFact(
                  icon: Icons.place_outlined,
                  label: 'المناطق',
                  value: '${_targetRegions.length} منطقة '
                      'في $governorates محافظة',
                ),
                _ReviewFact(
                  icon: Icons.payments_outlined,
                  label: 'العملة',
                  value: currencySymbol(_currency),
                ),
              ],
            ),
          ],
        ),
      ),

      const SizedBox(height: AppSpacing.lg),
      AppSectionHeader(
        title: 'ما سيراه الصيدلي (${_items.length})',
        appIcon: AppIcons.pill,
      ),
      const SizedBox(height: AppSpacing.sm),

      _ReviewTableHeader(),
      for (var i = 0; i < _items.length; i++)
        _ReviewTableRow(
          index: i + 1,
          draft: _items[i],
          currency: _currency,
        ),

      if (_bonusMedicine != null) ...[
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: tk.goldSurface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: tk.gold),
          ),
          child: Row(
            children: [
              Icon(Icons.card_giftcard, size: 18, color: tk.goldStrong),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'بونص العرض: ${_bonusQuantity.text.trim()} '
                  '${_bonusUnit.text.trim()} '
                  '${_bonusMedicine!.displayName} مجاناً',
                  style:
                      context.text.bodySmall?.copyWith(color: tk.goldStrong),
                ),
              ),
            ],
          ),
        ),
      ],

      const SizedBox(height: AppSpacing.lg),
      Row(
        children: [
          AppIcon(AppIcons.info, size: 14, color: tk.hint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              // الحقيقة تُقال هنا لا بعد الحفظ: الخادم يُنشئ العرض
              // مسوّدةً، و«أُنشئ العرض» وحدها تترك صاحبه ينتظر طلبياتٍ
              // على عرضٍ لا تراه صيدلية.
              'يُحفَظ مسوّدةً أولاً — ثم تنشره من شاشة «عروضي» ليصل '
              'الصيدليات.',
              style: context.text.labelSmall?.copyWith(color: tk.hint),
            ),
          ),
        ],
      ),
    ];
  }

  static String _day(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/'
      '${d.day.toString().padLeft(2, '0')}';
}

/// مراحل إنشاء العرض.
enum _OfferStep {
  basics('بيانات العرض', Icons.description_outlined),
  items('الأصناف', Icons.medication_outlined),
  review('المراجعة', Icons.fact_check_outlined);

  const _OfferStep(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// شريط مراحل المعالج.
class _OfferStepBar extends StatelessWidget {
  const _OfferStepBar({required this.current, required this.onPick});

  final _OfferStep current;
  final ValueChanged<_OfferStep> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;
    final steps = _OfferStep.values;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.page, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outline)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 1,
                  margin:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  color: cs.outline,
                ),
              ),
            Builder(builder: (context) {
              final active = current == steps[i];
              final done = current.index > i;
              final fg = active
                  ? cs.primary
                  : done
                      ? tk.success
                      : tk.hint;

              return Material(
                color: active ? tk.brandSurface : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: InkWell(
                  // ما مضى يُنقَر للعودة، وما هو آتٍ لا: التقدّم يمرّ
                  // بزرّ المرحلة ليُفحَص ما فيها قبل مغادرتها.
                  onTap: done ? () => onPick(steps[i]) : null,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done || active ? fg : null,
                            border: done || active
                                ? null
                                : Border.all(color: cs.outline),
                          ),
                          child: done
                              ? Icon(Icons.check,
                                  size: 13, color: cs.surface)
                              : Text('${i + 1}',
                                  style: context.text.labelSmall?.copyWith(
                                      color:
                                          active ? cs.surface : tk.hint)),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Icon(steps[i].icon, size: 14, color: fg),
                        const SizedBox(width: AppSpacing.xs),
                        Text(steps[i].label,
                            style: context.text.labelMedium
                                ?.copyWith(color: fg)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

/// شريط الإجراء أسفل المعالج — يتبع المرحلة.
class _OfferActionBar extends StatelessWidget {
  const _OfferActionBar({
    required this.step,
    required this.blocker,
    required this.saving,
    required this.itemCount,
    required this.onBack,
    required this.onNext,
    required this.onSubmit,
  });

  final _OfferStep step;

  /// سبب تعذّر المرحلة — يُقال ولا يُترك للتخمين.
  final String? blocker;

  final bool saving;
  final int itemCount;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.lg),
      decoration: BoxDecoration(color: cs.surface, boxShadow: tk.navShadow),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (onBack != null)
              SizedBox(
                width: 140,
                child: AppButton(
                  label: 'رجوع',
                  variant: AppButtonVariant.outline,
                  onPressed: saving ? null : onBack,
                ),
              ),

            // سببُ التعطيل يُقال لا يُترك للتخمين — وإلا بقي الزرّ
            // رمادياً بلا تفسير.
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: blocker != null
                    ? Row(
                        children: [
                          AppIcon(AppIcons.alertTriangle,
                              size: 14, color: tk.warning),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(blocker!,
                                style: context.text.labelSmall
                                    ?.copyWith(color: tk.warning)),
                          ),
                        ],
                      )
                    : Text(
                        switch (step) {
                          _OfferStep.basics => 'التالي: انتقِ أصنافك',
                          _OfferStep.items =>
                            '$itemCount صنفاً — التالي: المراجعة',
                          _OfferStep.review =>
                            'راجِع ما سيراه الصيدلي قبل الحفظ',
                        },
                        style:
                            context.text.labelSmall?.copyWith(color: tk.hint),
                      ),
              ),
            ),

            SizedBox(
              width: 240,
              child: step == _OfferStep.review
                  ? AppButton(
                      label: 'حفظ العرض مسوّدةً',
                      icon: Icons.check_circle_outline,
                      loading: saving,
                      onPressed: saving ? null : onSubmit,
                    )
                  : AppButton(
                      label: 'التالي',
                      appIcon: AppIcons.chevronForwardRtl,
                      onPressed: blocker != null ? null : onNext,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// حقيقةٌ في بطاقة المراجعة.
class _ReviewFact extends StatelessWidget {
  const _ReviewFact({
    required this.icon,
    required this.label,
    required this.value,
  });

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

class _ReviewTableHeader extends StatelessWidget {
  const _ReviewTableHeader();

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
          SizedBox(width: 110, child: Text('سعر الوحدة', style: style)),
          SizedBox(width: 80, child: Text('الحسم', style: style)),
          SizedBox(width: 110, child: Text('الصافي', style: style)),
          SizedBox(width: 120, child: Text('البونص', style: style)),
        ],
      ),
    );
  }
}

class _ReviewTableRow extends StatelessWidget {
  const _ReviewTableRow({
    required this.index,
    required this.draft,
    required this.currency,
  });

  final int index;
  final _OfferItemDraft draft;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    final price = parseDecimalInput(draft.unitPrice.text) ?? 0;
    final discount = parseDecimalInput(draft.discount.text) ?? 0;
    final net = price * (1 - discount / 100);

    // الشرائح الصالحة وحدها: الصفّ المملوء جزئياً خطأُ إدخالٍ يمنع
    // المضيّ أصلاً، وعرضُه هنا نصفَ شريحةٍ يُربك.
    final tiers = draft
        .validTiers()
        .map((t) => '${formatQuantity(t.buyQuantity)}+'
            '${formatQuantity(t.freeQuantity)}')
        .join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: index.isEven
            ? cs.surfaceContainerHighest.withValues(alpha: 0.3)
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
            child: Text(draft.medicine.displayName,
                style: context.text.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 110,
            child: Text(
              draft.isOpenQuantity
                  ? 'مفتوحة'
                  : '${draft.quantity.text.trim()} ${draft.unit.text.trim()}',
              style: context.text.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              formatMoneyWith(price, currency),
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
                ? Text('${formatQuantity(discount)}٪',
                    style:
                        context.text.labelSmall?.copyWith(color: tk.success))
                : Text('—',
                    style: context.text.labelSmall?.copyWith(color: tk.hint)),
          ),
          SizedBox(
            width: 110,
            child: Text(formatMoneyWith(net, currency),
                style: context.priceBrandStyle),
          ),
          SizedBox(
            width: 120,
            child: tiers.isEmpty
                ? Text('—',
                    style: context.text.labelSmall?.copyWith(color: tk.hint))
                : Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: BonusBadge(label: tiers, compact: true),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({required this.label, required this.date, required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.calendar_today_outlined)),
        child: Text('${date.year}/${date.month}/${date.day}'),
      ),
    );
  }
}

class _OfferItemCard extends StatefulWidget {
  const _OfferItemCard({required this.draft, required this.onRemove});
  final _OfferItemDraft draft;
  final VoidCallback onRemove;

  @override
  State<_OfferItemCard> createState() => _OfferItemCardState();
}

class _OfferItemCardState extends State<_OfferItemCard> {
  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(draft.medicine.displayName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: Theme.of(context).colorScheme.error),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            InkWell(
              onTap: () => setState(() => draft.isOpenQuantity = !draft.isOpenQuantity),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Row(
                children: [
                  Checkbox(
                    value: draft.isOpenQuantity,
                    onChanged: (v) =>
                        setState(() => draft.isOpenQuantity = v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  Text('كمية مفتوحة / غير محددة',
                      style: context.text.bodySmall),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: draft.quantity,
                    enabled: !draft.isOpenQuantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'الكمية المتاحة', isDense: true),
                    validator: (v) =>
                        OfferRules.quantity(v, open: draft.isOpenQuantity),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: TextFormField(
                    controller: draft.unit,
                    decoration:
                        const InputDecoration(labelText: 'الوحدة', isDense: true),
                    validator: OfferRules.unit,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: draft.unitPrice,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'سعر الوحدة', isDense: true),
                    // الصفر كان يمرّ: الشرط كان «أصغر من صفر» لا «أصغر
                    // أو يساوي»، فيردّه الخادم بعد رحلة شبكة برسالةٍ
                    // عامّة لا تسمّي الصنف.
                    validator: OfferRules.unitPrice,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: TextFormField(
                    controller: draft.discount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'حسم % (اختياري)', isDense: true),
                    // بلا حدٍّ كان يُضرب في سعر السلّة: حسمُ ١٥٠٪ يجعله
                    // سالباً، والسالب يرفعه فوق المعلَن.
                    validator: OfferRules.discount,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _BonusTiersEditor(draft: draft),
          ],
        ),
      ),
    );
  }
}

// ── محرّر شرائح البونص ─────────────────────────────────────────────────
//
// صنفٌ واحد قد يحمل سلّماً كاملاً — «(10+5) (5+2) (3+1)» شائعة في نشرات
// المستودعات — فحقل «بونص %» الواحد كان يُسقط السلّم على رقم. والشرائح
// تُركَّب عند الشراء: الكمية 25 أمام (10+5) و(5+2) تستحقّ 12 مجاناً.
class _BonusTiersEditor extends StatefulWidget {
  const _BonusTiersEditor({required this.draft});

  final _OfferItemDraft draft;

  @override
  State<_BonusTiersEditor> createState() => _BonusTiersEditorState();
}

class _BonusTiersEditorState extends State<_BonusTiersEditor> {
  void _add() => setState(() => widget.draft.bonusTiers.add(_BonusTierDraft()));

  void _removeAt(int index) =>
      setState(() => widget.draft.bonusTiers.removeAt(index).dispose());

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final tiers = widget.draft.bonusTiers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'شرائح البونص (اختياري)',
                style: context.text.labelMedium,
              ),
            ),
            TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('إضافة شريحة'),
            ),
          ],
        ),
        if (tiers.isEmpty)
          Text(
            'مثال: «اشترِ 10 واحصل على 5» — أضف شريحةً لكل درجة في سلّمك.',
            style: context.text.labelSmall?.copyWith(color: tk.hint),
          ),
        for (var i = 0; i < tiers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: tiers[i].buy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'اشترِ', isDense: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: TextFormField(
                    controller: tiers[i].free,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'واحصل مجاناً', isDense: true),
                  ),
                ),
                IconButton(
                  onPressed: () => _removeAt(i),
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'حذف الشريحة',
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ورقة سفلية لاختيار دواء من قائمة أدوية المستودع المُضافة مسبقاً فقط —
// جوهر الطلب: لا كتابة حرّة ولا من الكاتالوج مباشرة.
class _MedicinePickerSheet extends ConsumerStatefulWidget {
  const _MedicinePickerSheet({required this.alreadyPicked, this.single = false});
  final Set<String> alreadyPicked;
  final bool single;

  @override
  ConsumerState<_MedicinePickerSheet> createState() => _MedicinePickerSheetState();
}

class _MedicinePickerSheetState extends ConsumerState<_MedicinePickerSheet> {
  final _search = TextEditingController();
  final Set<String> _selected = {};
  List<WarehouseMedicine>? _medicines;
  bool _loading = true;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(warehouseMedicineRepositoryProvider).getMine();
      setState(() {
        _medicines = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = ApiException.from(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.single ? 'اختر دواء البونص' : 'اختر أدوية من مستودعك',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'بحث...',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(child: _buildList(scrollController)),
              if (!widget.single && _selected.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                FilledButton(
                  onPressed: () => Navigator.pop(
                      context,
                      (_medicines ?? []).where((m) => _selected.contains(m.id)).toList()),
                  child: Text('إضافة (${_selected.length})'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(ScrollController scrollController) {
    if (_loading) return const AppDetailSkeleton();
    if (_error != null) return ErrorState.of(_error!, onRetry: _load);

    final query = _search.text.trim();
    final available = (_medicines ?? [])
        .where((m) => !widget.alreadyPicked.contains(m.id))
        .where((m) => query.isEmpty || m.displayName.contains(query) || m.genericName.contains(query))
        .toList();

    if (available.isEmpty) {
      return const EmptyState(
        message: 'لا توجد أدوية متاحة — أضف أدوية إلى مستودعك أولاً من صفحة "أدويتي"',
        icon: Icons.medication_outlined,
      );
    }

    return ListView.builder(
      controller: scrollController,
      itemCount: available.length,
      itemBuilder: (context, index) {
        final m = available[index];
        final selected = _selected.contains(m.id);
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (widget.single) {
              Navigator.pop(context, [m]);
            } else {
              setState(() => selected ? _selected.remove(m.id) : _selected.add(m.id));
            }
          },
          child: MedicineListTile(
            displayName: m.displayName,
            genericName: m.genericName,
            manufacturerName: m.manufacturerName,
            dosageForm: m.dosageForm,
            strength: m.strength,
            trailing: widget.single
                ? Icon(Icons.chevron_left, color: context.tokens.hint)
                : Icon(selected ? Icons.check_box : Icons.check_box_outline_blank,
                    color: selected ? context.colors.primary : context.tokens.hint),
          ),
        );
      },
    );
  }
}

// قسم في نموذج العرض: عنوان فوق بطاقة من نظام التصميم. الخلفية والحدّ
// والظل من الثيم (AppCard) لا من أبيض صريح، فيتبع الوضعين الفاتح والداكن.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm, right: 2),
          child: Text(title, style: context.text.titleSmall),
        ),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}
