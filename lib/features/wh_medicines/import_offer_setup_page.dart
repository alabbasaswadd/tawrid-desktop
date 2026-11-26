import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  const ImportOfferGroup({required this.company, required this.rows});

  final String company;
  final List<ImportRow> rows;

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
  const ImportOfferSetupPage({required this.groups, super.key});

  final List<ImportOfferGroup> groups;

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

  String? get _blocker {
    if (_enabled.isEmpty) return 'اختر شركةً واحدة على الأقل';
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

    return Scaffold(
      appBar: const InnerTopBar(title: 'إعداد العروض'),
      body: Column(
        children: [
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
                    );
                  },
                );
              },
            ),
          ),

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
  });

  final ImportOfferGroup group;
  final bool enabled;
  final TextEditingController controller;
  final VoidCallback onToggle;

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
                StatusBadge(
                  label: '${group.rows.length} بنداً',
                  tone: StatusTone.neutral,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
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
