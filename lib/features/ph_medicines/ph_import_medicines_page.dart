import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/app_tokens_ext.dart';
import 'package:tawrid_app/shared/ui/ui.dart';

// بيانات وهمية تُظهر كيف ستبدو القائمة المستوردة.
class _FakeMed {
  const _FakeMed(this.name, this.manufacturer, this.price);
  final String name;
  final String manufacturer;
  final String price;
}

const _fakeRows = [
  _FakeMed('أموكسيسيلين 500مجم', 'GSK Pharma', '12.50'),
  _FakeMed('أوميبرازول 20مجم', 'AstraZeneca', '8.75'),
  _FakeMed('ميتفورمين 1000مجم', 'Merck KGaA', '6.20'),
  _FakeMed('لوسارتان 50مجم', 'Pharmalex', '15.00'),
  _FakeMed('سيتيريزين 10مجم', 'UCB Pharma', '4.90'),
  _FakeMed('أتورفاستاتين 20مجم', 'Pfizer', '22.00'),
  _FakeMed('سالبوتامول 100mcg', 'GSK Pharma', '18.50'),
];

enum _Phase { idle, importing, done }

enum _FileType { excel, pdf }

class PhImportMedicinesPage extends StatefulWidget {
  const PhImportMedicinesPage({super.key});

  @override
  State<PhImportMedicinesPage> createState() => _PhImportMedicinesPageState();
}

class _PhImportMedicinesPageState extends State<PhImportMedicinesPage>
    with TickerProviderStateMixin {
  _Phase _phase = _Phase.idle;
  _FileType? _selectedType;
  final List<_FakeMed> _rows = [];
  Timer? _rowTimer;

  late final AnimationController _doneCtrl;
  late final Animation<double> _doneScale;
  late final Animation<double> _doneFade;

  late final AnimationController _progressCtrl;
  late final Animation<double> _progressValue;

  @override
  void initState() {
    super.initState();

    _doneCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _doneScale = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _doneCtrl, curve: Curves.elasticOut),
    );
    _doneFade = CurvedAnimation(parent: _doneCtrl, curve: Curves.easeOut);

    _progressCtrl = AnimationController(vsync: this);
    _progressValue =
        CurvedAnimation(parent: _progressCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _rowTimer?.cancel();
    _doneCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  void _startImport(_FileType type) {
    _rowTimer?.cancel();
    setState(() {
      _phase = _Phase.importing;
      _selectedType = type;
      _rows.clear();
    });

    // شريط التقدّم يمتدّ على طول مدة ظهور الصفوف.
    final totalDuration =
        Duration(milliseconds: 400 * (_fakeRows.length + 1) + 500);
    _progressCtrl.duration = totalDuration;
    _progressCtrl.forward(from: 0);

    var idx = 0;
    _rowTimer = Timer.periodic(const Duration(milliseconds: 420), (t) {
      if (idx >= _fakeRows.length) {
        t.cancel();
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          setState(() => _phase = _Phase.done);
          _doneCtrl.forward(from: 0);
        });
        return;
      }
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _rows.add(_fakeRows[idx++]));
    });
  }

  void _reset() {
    _rowTimer?.cancel();
    _progressCtrl.stop();
    setState(() {
      _phase = _Phase.idle;
      _selectedType = null;
      _rows.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: InnerTopBar(title: 'استيراد الأدوية'),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        child: switch (_phase) {
          _Phase.idle => _IdleBody(onImport: _startImport),
          _Phase.importing => _ImportingBody(
              rows: _rows,
              progress: _progressValue,
              fileType: _selectedType!,
            ),
          _Phase.done => _DoneBody(
              scale: _doneScale,
              fade: _doneFade,
              onReset: _reset,
            ),
        },
      ),
    );
  }
}

// ── الحالة الأولى: اختيار نوع الملف ─────────────────────────────────────────

class _IdleBody extends StatelessWidget {
  const _IdleBody({required this.onImport});
  final void Function(_FileType) onImport;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.page, vertical: AppSpacing.x3l),
      child: Column(
        children: [
          // أيقونة مركزية
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: tk.brandSurface,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: AppIcon(AppIcons.clipboardList, size: 44, color: cs.primary),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'استيراد قائمة الأدوية',
            style: context.text.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'اختر صيغة الملف الذي تريد استيراد بيانات الأدوية منه',
            style: context.text.bodyMedium?.copyWith(color: tk.hint),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.x3l),

          // بطاقتا الاختيار
          Row(
            children: [
              Expanded(
                child: _FileTypeCard(
                  icon: AppIcons.fileText,
                  label: 'Excel',
                  ext: '.xlsx / .xls',
                  color: const Color(0xFF217346),
                  surfaceColor: const Color(0xFFE8F5EE),
                  onTap: () => onImport(_FileType.excel),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _FileTypeCard(
                  icon: AppIcons.fileText,
                  label: 'PDF',
                  ext: '.pdf',
                  color: const Color(0xFFD32F2F),
                  surfaceColor: const Color(0xFFFDEBEB),
                  onTap: () => onImport(_FileType.pdf),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.x2l),

          // ملاحظة قالب
          AppCard(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                AppIcon(AppIcons.info, size: 18, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'تأكّد من تطابق أعمدة الملف مع القالب المعتمد قبل الاستيراد',
                    style:
                        context.text.bodySmall?.copyWith(color: tk.hint),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileTypeCard extends StatelessWidget {
  const _FileTypeCard({
    required this.icon,
    required this.label,
    required this.ext,
    required this.color,
    required this.surfaceColor,
    required this.onTap,
  });

  final AppIcons icon;
  final String label;
  final String ext;
  final Color color;
  final Color surfaceColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Center(child: AppIcon(icon, size: 28, color: color)),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            label,
            style: context.text.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ext,
            style: context.text.labelSmall
                ?.copyWith(color: context.tokens.hint),
          ),
        ],
      ),
    );
  }
}

// ── الحالة الثانية: جاري الاستيراد مع أنيميشن الصفوف ────────────────────────

class _ImportingBody extends StatelessWidget {
  const _ImportingBody({
    required this.rows,
    required this.progress,
    required this.fileType,
  });

  final List<_FakeMed> rows;
  final Animation<double> progress;
  final _FileType fileType;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;
    final typeLabel = fileType == _FileType.excel ? 'Excel' : 'PDF';

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(AppIcons.fileText, size: 20, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'جاري قراءة ملف $typeLabel...',
                style: context.text.bodyMedium
                    ?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // شريط التقدّم
          AnimatedBuilder(
            animation: progress,
            builder: (_, _) => ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                value: progress.value,
                minHeight: 6,
                backgroundColor: tk.brandSurface,
                valueColor: AlwaysStoppedAnimation(cs.primary),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ترويسة الجدول
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: tk.brandSurface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text('اسم الدواء',
                      style: context.text.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('الشركة',
                      style: context.text.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('السعر',
                      textAlign: TextAlign.end,
                      style: context.text.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),

          // صفوف الأدوية الظاهرة واحداً بعد واحد
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(AppRadius.md)),
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: cs.outlineVariant),
                itemBuilder: (_, i) => _AnimatedMedRow(med: rows[i]),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.sm),
          Text(
            'تمّت قراءة ${rows.length} من ${_fakeRows.length} صفوف',
            style: context.text.labelSmall?.copyWith(color: tk.hint),
          ),
        ],
      ),
    );
  }
}

// صفّ أنيميشن — يظهر بانزلاق + تلاشٍ خفيف عند إضافته للقائمة.
class _AnimatedMedRow extends StatefulWidget {
  const _AnimatedMedRow({required this.med});
  final _FakeMed med;

  @override
  State<_AnimatedMedRow> createState() => _AnimatedMedRowState();
}

class _AnimatedMedRowState extends State<_AnimatedMedRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0.08, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    // يبدأ الأنيميشن بعد الرسم الأول مباشرةً.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 10),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Text(
                  widget.med.name,
                  style: context.text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  widget.med.manufacturer,
                  style: context.text.labelSmall
                      ?.copyWith(color: context.tokens.hint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  widget.med.price,
                  textAlign: TextAlign.end,
                  style: context.priceBrandStyle
                      .copyWith(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── الحالة الثالثة: قريباً ────────────────────────────────────────────────────

class _DoneBody extends StatelessWidget {
  const _DoneBody({
    required this.scale,
    required this.fade,
    required this.onReset,
  });

  final Animation<double> scale;
  final Animation<double> fade;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return FadeTransition(
      opacity: fade,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3l),
          child: ScaleTransition(
            scale: scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // أيقونة الساعة المحاطة بهالة
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        tk.brandSurface,
                        tk.brandSurface.withValues(alpha: 0),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: tk.brandSurface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.25),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: AppIcon(AppIcons.clock, size: 36, color: cs.primary),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.x2l),

                // شارة «قريباً»
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: 6),
                  decoration: BoxDecoration(
                    color: tk.brandSurface,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                        color: cs.primary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'قريباً',
                    style: context.text.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                Text(
                  'ستتوفر هذه الميزة قريباً',
                  style: context.text.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: AppSpacing.sm),

                Text(
                  'نعمل على إضافة استيراد الأدوية من ملفات Excel وPDF\nفي التحديثات القادمة من التطبيق',
                  style:
                      context.text.bodyMedium?.copyWith(color: tk.hint),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: AppSpacing.x3l),

                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: 'حسناً',
                    onPressed: onReset,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
