import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tawrid_app/app/router/routes.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/app_tokens_ext.dart';
import 'package:tawrid_app/models/ai_import_models.dart';
import 'package:tawrid_app/models/geo_models.dart';
import 'package:tawrid_app/models/sales_offer_models.dart';
import 'package:tawrid_app/repositories/warehouse_service_area_repository.dart';
import 'package:tawrid_app/shared/ui/ui.dart';
import 'package:tawrid_app/shared/widgets/multi_region_picker.dart';

/// بنود شركةٍ واحدة كما جُمعت من الملف.
class ImportOfferGroup {
  const ImportOfferGroup({
    required this.company,
    required this.rows,
    this.includeAllItems = false,
  });

  final String company;
  final List<ImportRow> rows;

  /// بُنيت المجموعة في وضع نشرة الأسعار — فتُمرَّر كذلك إلى الخادم.
  ///
  /// بلا نقلها كان الخادم يُعيد تصفية البنود بشرط «حَمَل خصماً أو
  /// بونصاً» فيُخرج نشرةَ الأسعار كلّها — وقد عدّها العميل بنوداً.
  final bool includeAllItems;

  int get discounted =>
      rows.where((r) => (r.discountPercentage ?? 0) > 0).length;
  int get bonused => rows.where((r) => r.bonusLabel != null).length;

  /// الشركة المجهولة: صفوفٌ لم يجد لها الوكيل شركة.
  bool get isUnnamed => company.isEmpty;

  String get label => isUnnamed ? 'بلا شركة' : company;

  /// عنوانٌ افتراضي يحمل تاريخه.
  ///
  /// الخادم يرفض عنواناً مستعملاً («القيمة مستعملة سابقاً — لا يمكن
  /// تكرارها»)، واستيراد ملفٍ من الشركة نفسها مرّتين أمرٌ عادي: قائمةُ
  /// أسعارٍ تصل كل شهر. فكان العنوان الثابت «عرض فاركو» يُسقط المزامنة
  /// كلّها في المرة الثانية. والتاريخ يُميّزه بلا أن يُطالَب المستخدم
  /// بابتكار اسمٍ في كل مرة — وهو يُحرّره إن شاء.
  String defaultTitle(DateTime on) {
    final stamp = '${on.day}/${on.month}';
    return isUnnamed ? 'عرض مستورد $stamp' : 'عرض $company $stamp';
  }

  /// خطّةٌ بالقيم الافتراضية — بلا شاشةٍ ولا سؤال.
  ///
  /// كل حقلٍ في شاشة الإعداد له افتراضٌ صحيح: العنوان من الشركة، والمدّة
  /// شهرٌ من اليوم، والاستهداف كامل تغطية المستودع. فسؤال المستخدم عنها
  /// في كل ملفٍ تأكيدٌ على ما لن يُغيّره.
  ImportOfferPlan defaultPlan({
    required DateTime now,
    required List<TargetRegion> regions,
  }) =>
      ImportOfferPlan(
        company: company,
        title: defaultTitle(now),
        startsAt: now,
        expiresAt: now.add(const Duration(days: 30)),
        isPublicInRegion: true,
        targetRegions: regions,
        includeAllItems: includeAllItems,
      );
}

/// مناطق التغطية مسطَّحةً إلى استهداف — المصدر الوحيد للافتراض.
List<TargetRegion> regionsOfCoverage(List<Governorate> governorates) => [
      for (final g in governorates)
        for (final c in g.cities)
          TargetRegion(governorate: g.name, city: c.name),
    ];

/// إعداد العروض قبل المزامنة.
///
/// خطوةٌ قائمة بذاتها لأن ما تحتاجه ليس في الملف: ملفُّ أسعارٍ يحمل
/// أصنافاً وشروطاً تجارية، ولا يحمل مناطقَ ولا مدداً — وهما شرطُ إنشاء
/// العرض في الخادم.
///
/// وتخطيطها لسطح المكتب لا للهاتف: الشاشة عريضة، وعمودٌ واحد في وسطها
/// يترك ثلثيها فارغين ويُطيل التمرير بلا سبب. فالعروض شبكةٌ تملأ العرض،
/// والاستهداف في ترويسةٍ ثابتة فوقها — قرارٌ واحد يسري على الكل، ومكانُه
/// حيث يُرى دائماً لا حيث يُبحَث عنه بالتمرير.
class ImportOfferSetupPage extends ConsumerStatefulWidget {
  const ImportOfferSetupPage({
    required this.groups,
    this.embedded = false,
    this.onChanged,
    super.key,
  });

  final List<ImportOfferGroup> groups;

  /// مضمَّنةً داخل مراحل الاستيراد لا شاشةً قائمة بذاتها.
  ///
  /// الفرق سطحٌ لا جوهر: لا Scaffold ولا شريط إجراءٍ أسفلها — المرحلة
  /// تملك شريطها، وشريطان أحدهما فوق الآخر يُربكان.
  ///
  /// وتُضمَّن ولا تُنسَخ: المنطق هنا (الافتراضات، والحاجب، والتغطية
  /// الفارغة) واحدٌ في الحالتين، ونسخةٌ ثانية منه تفترق عند أول تعديل.
  final bool embedded;

  /// يُنادى عند كل تغيير: الخطّة الجارية وسببُ تعذّرها إن تعذّرت.
  ///
  /// المالك هو من يُقرّر متى تُستعمل — فالمرحلة تحتاج أن تعرف الخطّة
  /// قبل أن يضغط المستخدم شيئاً، لا بعد «حفظ».
  final void Function(List<ImportOfferPlan> plans, String? blocker)? onChanged;

  @override
  ConsumerState<ImportOfferSetupPage> createState() =>
      _ImportOfferSetupPageState();
}

class _ImportOfferSetupPageState extends ConsumerState<ImportOfferSetupPage> {
  final Set<String> _enabled = {};
  final Map<String, TextEditingController> _titles = {};

  List<TargetRegion> _regions = [];

  /// هل لمس المستخدم الاستهداف؟
  ///
  /// بلا هذا كان الافتراضي يُعاد فرضه عند كل إعادة بناء، فلا يستطيع أحد
  /// إزالة منطقة — تعود فوراً.
  bool _regionsTouched = false;

  DateTime _startsAt = DateTime.now();
  DateTime? _expiresAt = DateTime.now().add(const Duration(days: 30));
  bool _standing = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    for (final g in widget.groups) {
      _enabled.add(g.company);
      _titles[g.company] = TextEditingController(text: g.defaultTitle(now));
    }
  }

  @override
  void dispose() {
    for (final c in _titles.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// يملأ الاستهداف من مناطق تغطية المستودع.
  ///
  /// هو الافتراضي الصحيح لا تسهيلاً: المستودع لا يبيع خارج ما يخدمه،
  /// والخادم يرفض عرضاً يستهدف منطقةً خارج نطاقه. فالبدء بكامل التغطية
  /// يُصيب في الغالب، ويُضيّقه من يريد تضييقه.
  void _seedRegions(List<Governorate> governorates) {
    if (_regionsTouched || _regions.isNotEmpty) return;

    _regions = regionsOfCoverage(governorates);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startsAt : (_expiresAt ?? now),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startsAt = picked;
        // بدءٌ بعد الانتهاء عرضٌ لا يُرى أبداً — يُزاح الانتهاء معه.
        if (_expiresAt != null && !_expiresAt!.isAfter(picked)) {
          _expiresAt = picked.add(const Duration(days: 30));
        }
      } else {
        _expiresAt = picked;
      }
    });
  }

  /// لا مناطق تغطيةٍ للمستودع أصلاً — لا شيء يُختار منه.
  ///
  /// الفرق بينها وبين «لم يختر بعد» هو الفرق بين طريقٍ مسدود وخطوةٍ
  /// ناقصة: المنتقي يعرض مناطق تغطية المستودع وحدها، فإن كانت فارغة
  /// بقي فارغاً مهما فعل المستخدم. وقولُ «اختر منطقةً» حينها يُحمّله
  /// ذنب شيءٍ لا يملكه — ويتركه أمام شاشةٍ لا مخرج منها.
  bool _noCoverage = false;

  String? get _blocker {
    if (_enabled.isEmpty) return 'اختر شركةً واحدة على الأقل';
    if (_noCoverage) {
      return 'مستودعك بلا مناطق تغطية — حدّدها أولاً لتُنشأ العروض';
    }
    if (_regions.isEmpty) return 'اختر منطقةً واحدة على الأقل';

    for (final company in _enabled) {
      if ((_titles[company]?.text.trim() ?? '').isEmpty) {
        return 'اكتب عنواناً لكل عرضٍ مُفعَّل';
      }
    }

    if (!_standing && _expiresAt != null && !_expiresAt!.isAfter(_startsAt)) {
      return 'تاريخ الانتهاء يجب أن يلي تاريخ البدء';
    }

    return null;
  }

  /// الخطّة كما هي الآن — بصرف النظر عن صلاحيتها.
  List<ImportOfferPlan> get _plans => widget.groups
      .where((g) => _enabled.contains(g.company))
      .map((g) => ImportOfferPlan(
            company: g.company,
            title: _titles[g.company]!.text.trim(),
            startsAt: _startsAt,
            expiresAt: _standing ? null : _expiresAt,
            isPublicInRegion: true,
            targetRegions: _regions,
            includeAllItems: g.includeAllItems,
          ))
      .toList();

  /// يُبلّغ المالك بالخطّة الجارية — بعد الإطار لا أثناءه.
  ///
  /// `onChanged` يُحدّث حالة المالك، ونداؤها داخل `build` يُطلب إعادةُ
  /// بناءٍ أثناء بناء — وهو ما يرفضه Flutter.
  void _notify() {
    final cb = widget.onChanged;
    if (cb == null) return;

    final plans = _plans;
    final blocker = _blocker;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb(plans, blocker);
    });
  }

  void _submit() {
    if (_blocker != null) return;

    final plans = widget.groups
        .where((g) => _enabled.contains(g.company))
        .map((g) => ImportOfferPlan(
              company: g.company,
              title: _titles[g.company]!.text.trim(),
              startsAt: _startsAt,
              expiresAt: _standing ? null : _expiresAt,
              isPublicInRegion: true,
              targetRegions: _regions,
              includeAllItems: g.includeAllItems,
            ))
        .toList();

    Navigator.of(context).pop(plans);
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final blocker = _blocker;

    // المناطق المخدومة — تُملأ مرةً حين تصل.
    ref.listen(myServiceGovernoratesProvider, (_, next) {
      final areas = next.value;
      if (areas != null && areas.isNotEmpty) setState(() => _seedRegions(areas));
    });
    final served = ref.watch(myServiceGovernoratesProvider).value;
    if (served != null && served.isNotEmpty) _seedRegions(served);
    _noCoverage = served != null && served.isEmpty;

    _notify();

    final content = Column(
        children: [
          if (_noCoverage)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                  AppSpacing.md, AppSpacing.page, 0),
              child: _NoCoverageNotice(
                onFix: () => context.push(TRoutes.whServiceAreas),
              ),
            ),
          _TargetingHeader(
            regions: _regions,
            onRegionsChanged: (v) => setState(() {
              _regionsTouched = true;
              _regions = v;
            }),
            startsAt: _startsAt,
            expiresAt: _expiresAt,
            standing: _standing,
            onPickStart: () => _pickDate(isStart: true),
            onPickEnd: () => _pickDate(isStart: false),
            onStandingChanged: (v) => setState(() => _standing = v),
          ),

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // عمودٌ لكل ٤٢٠ بكسل: البطاقة أضيق من ذلك تضغط العنوان
                // وشاراته، وأعرض منها تترك فراغاً في شاشةٍ عريضة.
                final columns =
                    (constraints.maxWidth / 420).floor().clamp(1, 4);

                return GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.page),
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    // ارتفاعٌ ثابت لا نسبة عرض: البطاقة محتواها معروف
                    // (عنوان وشارات وحقل)، والنسبة تُطيلها كلّما اتّسعت
                    // الشاشة فتصير مربّعاتٍ فارغة.
                    mainAxisExtent: 208,
                  ),
                  itemCount: widget.groups.length,
                  itemBuilder: (_, i) {
                    final g = widget.groups[i];
                    return _CompanyCard(
                      group: g,
                      enabled: _enabled.contains(g.company),
                      controller: _titles[g.company]!,
                      onToggle: () => setState(() {
                        if (!_enabled.remove(g.company)) {
                          _enabled.add(g.company);
                        }
                      }),
                      onShowItems: () => showOfferItemsDialog(context, g),
                    );
                  },
                );
              },
            ),
          ),

          // الشريط للشاشة القائمة بذاتها وحدها: المرحلة تملك شريطها،
          // وشريطان أحدهما فوق الآخر يُربكان.
          if (!widget.embedded)
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md,
                AppSpacing.page, AppSpacing.lg),
            decoration: BoxDecoration(
              color: context.colors.surface,
              boxShadow: tk.navShadow,
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // سبب التعطيل يُقال لا يُترك للتخمين.
                  Expanded(
                    child: blocker != null
                        ? Row(
                            children: [
                              AppIcon(AppIcons.alertTriangle,
                                  size: 14, color: tk.warning),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(blocker,
                                    style: context.text.labelSmall
                                        ?.copyWith(color: tk.warning)),
                              ),
                            ],
                          )
                        : Text(
                            'سيُنشأ ${_enabled.length} '
                            '${_enabled.length == 1 ? "عرض" : "عروض"} '
                            'على ${_regions.length} منطقة',
                            style: context.text.labelSmall
                                ?.copyWith(color: tk.hint),
                          ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 150,
                    child: AppButton(
                      label: 'بلا عروض',
                      variant: AppButtonVariant.outline,
                      onPressed: () =>
                          Navigator.of(context).pop(<ImportOfferPlan>[]),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 260,
                    child: AppButton(
                      label: 'مزامنة وإنشاء العروض',
                      appIcon: AppIcons.check,
                      onPressed: blocker == null ? _submit : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

    // مضمَّنةً تُسلَّم كما هي؛ وقائمةً بذاتها تُلبَس هيكل الشاشة.
    if (widget.embedded) return content;

    return Scaffold(
      appBar: const InnerTopBar(title: 'إعداد العروض'),
      body: content,
    );
  }
}

/// لافتةٌ تقول إن المستودع بلا تغطية، وتدلّ على موضع ضبطها.
class _NoCoverageNotice extends StatelessWidget {
  const _NoCoverageNotice({required this.onFix});
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tk.warningSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tk.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          AppIcon(AppIcons.alertTriangle, size: 20, color: tk.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('مستودعك بلا مناطق تغطية',
                    style: context.text.labelMedium
                        ?.copyWith(color: tk.warning)),
                const SizedBox(height: 2),
                Text(
                  'العرض يُستهدَف بمناطق، ولا يُعرَض هنا إلا ما يخدمه '
                  'مستودعك. حدّد تغطيتك ثم عُد — أو تابع المزامنة بلا عروض '
                  'وأنشئها لاحقاً.',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 180,
            child: AppButton(
              label: 'تحديد مناطق التغطية',
              variant: AppButtonVariant.outline,
              appIcon: AppIcons.mapPin,
              onPressed: onFix,
            ),
          ),
        ],
      ),
    );
  }
}

/// ترويسة الاستهداف — قرارٌ واحد يسري على كل العروض، ثابتٌ فوق الشبكة.
class _TargetingHeader extends StatelessWidget {
  const _TargetingHeader({
    required this.regions,
    required this.onRegionsChanged,
    required this.startsAt,
    required this.expiresAt,
    required this.standing,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onStandingChanged,
  });

  final List<TargetRegion> regions;
  final ValueChanged<List<TargetRegion>> onRegionsChanged;
  final DateTime startsAt;
  final DateTime? expiresAt;
  final bool standing;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final ValueChanged<bool> onStandingChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outline)),
      ),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    AppIcon(AppIcons.mapPin, size: 14, color: cs.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Text('المناطق المستهدفة',
                        style: context.text.labelMedium),
                    const SizedBox(width: AppSpacing.sm),
                    Text('افتراضياً كل مناطق تغطيتك',
                        style: context.text.labelSmall
                            ?.copyWith(color: tk.hint)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                MultiRegionPicker(
                    regions: regions, onChanged: onRegionsChanged),
              ],
            ),
          ),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DateField(
                  label: 'يبدأ في', date: startsAt, onTap: onPickStart),
              const SizedBox(width: AppSpacing.md),
              if (!standing)
                _DateField(
                    label: 'ينتهي في',
                    date: expiresAt ?? startsAt,
                    onTap: onPickEnd),
            ],
          ),

          InkWell(
            onTap: () => onStandingChanged(!standing),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppCheckbox(
                    selection:
                        standing ? AppCheckState.all : AppCheckState.none,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('عرض دائم', style: context.text.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({
    required this.group,
    required this.enabled,
    required this.controller,
    required this.onToggle,
    required this.onShowItems,
  });

  final ImportOfferGroup group;
  final bool enabled;
  final TextEditingController controller;
  final VoidCallback onToggle;

  /// يفتح نافذة البنود — ما سيراه الصيدلي بالضبط.
  final VoidCallback onShowItems;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    // المُفعَّل يُميَّز بحدٍّ وسطحٍ لا بلونٍ مختلف: البطاقة المُطفأة تبقى
    // مقروءة — هي خيارٌ متاح لا شيء مُستبعَد.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: enabled ? tk.brandSurface : cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: enabled ? cs.primary.withValues(alpha: 0.6) : cs.outline,
          width: enabled ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Row(
              children: [
                AppCheckbox(
                  selection:
                      enabled ? AppCheckState.all : AppCheckState.none,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(group.label,
                      style: context.text.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              // ── عدد البنود بابُها لا خبرُها ────────────────────────────
              // «١٢ بنداً» رقمٌ يُثير السؤال ولا يُجيبه، وصاحب المستودع
              // يُقرّ عرضاً سيراه الصيادلة بأسعاره — فحقُّه أن يرى ما
              // فيه قبل أن يُقرّه، لا أن يثق بعدٍّ مجرّد.
              _ItemsButton(
                count: group.rows.length,
                onTap: onShowItems,
              ),
              if (group.discounted > 0)
                StatusBadge(
                    label: 'خصم على ${group.discounted}',
                    tone: StatusTone.info),
              if (group.bonused > 0)
                BonusBadge(label: 'بونص على ${group.bonused}'),
            ],
          ),
          const Spacer(),
          if (enabled)
            AppTextField(
              controller: controller,
              label: 'عنوان العرض',
              hint: 'ما يراه الصيدلي',
            )
          else
            Text(
              'لن يُنشأ عرض — أصنافها تُزامَن في مخزونك كالمعتاد.',
              style: context.text.labelSmall?.copyWith(color: tk.hint),
            ),
        ],
      ),
    );
  }
}

/// عدّاد البنود، زرّاً — نقرةٌ تفتح ما فيها.
class _ItemsButton extends StatelessWidget {
  const _ItemsButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(AppIcons.listRows, size: 12, color: cs.primary),
              const SizedBox(width: AppSpacing.xs),
              Text('$count بنداً',
                  style: context.text.labelSmall?.copyWith(color: cs.primary)),
              const SizedBox(width: AppSpacing.xs),
              // الشيفرون يسار النصّ — اصطلاح روابط التفاصيل في RTL.
              AppIcon(AppIcons.chevronForwardRtl, size: 12, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// يفتح نافذة بنود العرض.
///
/// نافذةٌ لا صفحة: قرارُ المستخدم في شاشة الإعداد، والذهابُ إلى صفحةٍ
/// أخرى وعودةٌ منها يقطع عليه ما كان فيه. والشاشة عريضة تسع النافذة
/// بجدولها كاملاً.
Future<void> showOfferItemsDialog(
  BuildContext context,
  ImportOfferGroup group,
) =>
    showDialog<void>(
      context: context,
      builder: (_) => _OfferItemsDialog(group: group),
    );

/// بنود عرضٍ واحد، جدولاً — ما سيراه الصيدلي بالضبط.
class _OfferItemsDialog extends StatelessWidget {
  const _OfferItemsDialog({required this.group});

  final ImportOfferGroup group;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    final rows = [...group.rows]
      ..sort((a, b) => a.rowNumber.compareTo(b.rowNumber));

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── الترويسة ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md,
                  AppSpacing.md, AppSpacing.md),
              decoration: BoxDecoration(
                color: tk.brandSurface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.lg)),
              ),
              child: Row(
                children: [
                  AppIcon(AppIcons.gift, size: 18, color: cs.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('بنود عرض ${group.label}',
                            style: context.text.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          '${rows.length} بنداً'
                          '${group.discounted > 0 ? " · خصم على ${group.discounted}" : ""}'
                          '${group.bonused > 0 ? " · بونص على ${group.bonused}" : ""}',
                          style: context.text.labelSmall
                              ?.copyWith(color: tk.hint),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: AppIcon(AppIcons.x, size: 16, color: tk.hint),
                    tooltip: 'إغلاق',
                  ),
                ],
              ),
            ),

            const _ItemsHeaderRow(),

            Flexible(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: cs.outline),
                itemBuilder: (_, i) => _ItemRow(row: rows[i], index: i),
              ),
            ),

            // ── التذييل ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: cs.outline)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'الأسعار كما قرأها الوكيل من ملفك — تُصحَّح من شاشة '
                      'المراجعة قبل المزامنة.',
                      style:
                          context.text.labelSmall?.copyWith(color: tk.hint),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 140,
                    child: AppButton(
                      label: 'إغلاق',
                      variant: AppButtonVariant.outline,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ترويسة الجدول — ثابتة فوق التمرير فلا تُنسى الأعمدة في منتصف القائمة.
class _ItemsHeaderRow extends StatelessWidget {
  const _ItemsHeaderRow();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final style = context.text.labelSmall?.copyWith(color: context.tokens.hint);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: cs.outline)),
      ),
      child: Row(
        children: [
          SizedBox(width: 44, child: Text('السطر', style: style)),
          Expanded(flex: 4, child: Text('الصنف', style: style)),
          SizedBox(width: 90, child: Text('الكمية', style: style)),
          SizedBox(width: 110, child: Text('السعر', style: style)),
          SizedBox(width: 80, child: Text('الخصم', style: style)),
          SizedBox(width: 90, child: Text('البونص', style: style)),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.row, required this.index});

  final ImportRow row;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    // تظليل السطور الزوجية: الجدول عريض، والعين تتيه بين عموده الأول
    // وعموده الأخير بلا خطٍّ يقودها.
    return Container(
      color: index.isEven ? null : cs.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text('${row.rowNumber}',
                style: context.text.labelSmall?.copyWith(color: tk.hint)),
          ),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(row.name,
                    style: context.text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                // العيار والشكل تحت الاسم لا في عمودٍ ثالث: هما تمييزٌ
                // له لا بيانٌ مستقلّ، وعمودٌ لهما يُضيّق عمود الاسم.
                if (row.strength != null || row.form != null)
                  Text(
                    [
                      if (row.strength != null) '${_n(row.strength!)} ملغ',
                      if (row.form != null) row.form!,
                    ].join(' · '),
                    style:
                        context.text.labelSmall?.copyWith(color: tk.hint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              '${row.quantity ?? 1} ${row.unit ?? "علبة"}',
              style: context.text.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              row.price != null ? _n(row.price!) : '—',
              style: row.price != null
                  ? context.priceStyle
                  : context.text.labelSmall?.copyWith(color: tk.hint),
            ),
          ),
          SizedBox(
            width: 80,
            child: (row.discountPercentage ?? 0) > 0
                ? Text('${_n(row.discountPercentage!)}٪',
                    style: context.text.labelSmall
                        ?.copyWith(color: tk.success))
                : Text('—',
                    style: context.text.labelSmall
                        ?.copyWith(color: tk.hint)),
          ),
          SizedBox(
            width: 90,
            child: row.bonusLabel != null
                ? BonusBadge(label: row.bonusLabel!)
                : Text('—',
                    style: context.text.labelSmall
                        ?.copyWith(color: tk.hint)),
          ),
        ],
      ),
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: context.text.labelSmall
                    ?.copyWith(color: context.tokens.hint)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(AppIcons.calendar, size: 14, color: cs.primary),
                const SizedBox(width: AppSpacing.xs),
                Text('${date.year}/${date.month}/${date.day}',
                    style: context.text.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
