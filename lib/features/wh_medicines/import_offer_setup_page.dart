import 'package:flutter/material.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/app_tokens_ext.dart';
import 'package:tawrid_app/models/ai_import_models.dart';
import 'package:tawrid_app/models/sales_offer_models.dart';
import 'package:tawrid_app/shared/ui/ui.dart';
import 'package:tawrid_app/shared/widgets/multi_region_picker.dart';

/// بنود شركةٍ واحدة كما جُمعت من الملف.
class ImportOfferGroup {
  const ImportOfferGroup({required this.company, required this.rows});

  final String company;
  final List<ImportRow> rows;

  int get discounted => rows.where((r) => (r.discountPercentage ?? 0) > 0).length;
  int get bonused => rows.where((r) => r.bonusLabel != null).length;

  /// الشركة المجهولة: صفوفٌ لم يجد لها الوكيل شركة.
  bool get isUnnamed => company.isEmpty;

  String get label => isUnnamed ? 'بلا شركة' : company;
}

/// إعداد العروض قبل المزامنة.
///
/// خطوةٌ قائمة بذاتها لأن ما تحتاجه ليس في الملف: ملفُّ أسعارٍ يحمل
/// أصنافاً وشروطاً تجارية، ولا يحمل مناطقَ ولا مدداً — وهما شرطُ إنشاء
/// العرض في الخادم. فلا سبيل إلى اشتقاقهما، ويختارهما صاحب المستودع.
///
/// والاستهداف واحدٌ لكل العروض عمداً: المستودع يخدم مناطقه نفسها مهما
/// تعدّدت شركاته، وطلبُ استهدافٍ مستقلٍّ لكل شركة يُضاعف العمل بلا أن
/// يُضيف قراراً. وما يختلف بين العروض — العنوان وإنشاؤه من عدمه — يبقى
/// لكل شركة.
class ImportOfferSetupPage extends StatefulWidget {
  const ImportOfferSetupPage({required this.groups, super.key});

  final List<ImportOfferGroup> groups;

  @override
  State<ImportOfferSetupPage> createState() => _ImportOfferSetupPageState();
}

class _ImportOfferSetupPageState extends State<ImportOfferSetupPage> {
  /// أي الشركات يُنشأ لها عرض — الكل ابتداءً، فهذا سبب وصوله إلى هنا.
  final Set<String> _enabled = {};
  final Map<String, TextEditingController> _titles = {};

  List<TargetRegion> _regions = [];
  DateTime _startsAt = DateTime.now();
  DateTime? _expiresAt = DateTime.now().add(const Duration(days: 30));

  /// عرضٌ بلا انتهاء — «دائم» في لغة الخادم (ExpiresAt فارغ).
  bool _standing = false;

  @override
  void initState() {
    super.initState();
    for (final g in widget.groups) {
      _enabled.add(g.company);
      _titles[g.company] = TextEditingController(
        text: g.isUnnamed ? 'عرض مستورد' : 'عرض ${g.company}',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _titles.values) {
      c.dispose();
    }
    super.dispose();
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

    return Scaffold(
      appBar: const InnerTopBar(title: 'إعداد العروض'),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg,
                  AppSpacing.page, AppSpacing.lg),
              children: [
                _NoteCard(count: widget.groups.length),
                const SizedBox(height: AppSpacing.lg),

                AppSectionHeader(
                  title: 'العروض (${_enabled.length} من ${widget.groups.length})',
                  appIcon: AppIcons.gift,
                ),
                const SizedBox(height: AppSpacing.sm),

                for (final g in widget.groups) ...[
                  _CompanyCard(
                    group: g,
                    enabled: _enabled.contains(g.company),
                    controller: _titles[g.company]!,
                    onToggle: () => setState(() {
                      if (!_enabled.remove(g.company)) _enabled.add(g.company);
                    }),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],

                const SizedBox(height: AppSpacing.md),
                AppSectionHeader(
                  title: 'من يرى هذه العروض',
                  appIcon: AppIcons.mapPin,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المناطق المستهدفة',
                          style: context.text.labelMedium),
                      const SizedBox(height: AppSpacing.xs),
                      MultiRegionPicker(
                        regions: _regions,
                        onChanged: (v) => setState(() => _regions = v),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'يُطبَّق الاستهداف نفسه على كل العروض المُنشأة من هذا الملف.',
                        style: context.text.labelSmall
                            ?.copyWith(color: tk.hint),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.md),
                AppSectionHeader(title: 'المدّة', appIcon: AppIcons.calendar),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _DateField(
                              label: 'يبدأ في',
                              date: _startsAt,
                              onTap: () => _pickDate(isStart: true),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: _standing
                                ? _StandingHint(hint: tk.hint)
                                : _DateField(
                                    label: 'ينتهي في',
                                    date: _expiresAt ?? _startsAt,
                                    onTap: () => _pickDate(isStart: false),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          // AppCheckbox عرضٌ لا تفاعل — النقر على الصفّ
                          // كلّه لا على المربّع وحده: هدفٌ أوسع لليد.
                          Expanded(
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _standing = !_standing),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.sm),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.xs),
                                child: Row(
                                  children: [
                                    AppCheckbox(
                                      selection: _standing
                                          ? AppCheckState.all
                                          : AppCheckState.none,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                          'عرض دائم بلا تاريخ انتهاء',
                                          style: context.text.bodySmall),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // سبب التعطيل يُقال لا يُترك للتخمين: زرٌّ رماديٌّ بلا
                  // تفسير يُوقف المستخدم بلا أن يدلّه على ما ينقص.
                  if (blocker != null) ...[
                    Text(blocker,
                        style: context.text.labelSmall
                            ?.copyWith(color: tk.warning)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'بلا عروض',
                          variant: AppButtonVariant.outline,
                          // المزامنة تمضي والمخزون يُكتب، ولا يُنشأ عرض.
                          onPressed: () =>
                              Navigator.of(context).pop(<ImportOfferPlan>[]),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        flex: 2,
                        child: AppButton(
                          label: 'مزامنة وإنشاء العروض',
                          appIcon: AppIcons.check,
                          onPressed: blocker == null ? _submit : null,
                        ),
                      ),
                    ],
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

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tk.brandSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.info, size: 18, color: context.colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'وجد الوكيل شروطاً تجارية (خصم أو بونص) في $count '
              '${count == 1 ? "شركة" : "شركات"}. تُنشأ العروض '
              '«مسوّدة» فلا يراها أحد حتى تنشرها من شاشة العروض.',
              style: context.text.bodySmall,
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
    final tk = context.tokens;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        AppCheckbox(
                          selection: enabled
                              ? AppCheckState.all
                              : AppCheckState.none,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(group.label,
                              style: context.text.labelLarge),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(
                label: '${group.rows.length} بنداً',
                tone: StatusTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (group.discounted > 0)
                StatusBadge(
                  label: 'خصم على ${group.discounted}',
                  tone: StatusTone.info,
                ),
              if (group.bonused > 0)
                BonusBadge(label: 'بونص على ${group.bonused}'),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              controller: controller,
              label: 'عنوان العرض',
              hint: 'ما يراه الصيدلي في قائمة العروض',
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'لن يُنشأ عرض لهذه الشركة — أصنافها تُزامَن في مخزونك كالمعتاد.',
              style: context.text.labelSmall?.copyWith(color: tk.hint),
            ),
          ],
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
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: context.text.labelSmall
                    ?.copyWith(color: context.tokens.hint)),
            const SizedBox(height: 2),
            Row(
              children: [
                AppIcon(AppIcons.calendar, size: 14, color: cs.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${date.year}/${date.month}/${date.day}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StandingHint extends StatelessWidget {
  const _StandingHint({required this.hint});
  final Color hint;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        child: Text('بلا تاريخ انتهاء',
            style: context.text.bodySmall?.copyWith(color: hint)),
      );
}
