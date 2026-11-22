import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/app_tokens_ext.dart';
import 'package:tawrid_app/shared/ui/ui.dart';

class WhImportInventoryPage extends StatefulWidget {
  const WhImportInventoryPage({super.key});

  @override
  State<WhImportInventoryPage> createState() => _WhImportInventoryPageState();
}

enum _ImportState { idle, loading, done }

class _WhImportInventoryPageState extends State<WhImportInventoryPage>
    with SingleTickerProviderStateMixin {
  _ImportState _state = _ImportState.idle;
  String? _fileName;
  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
      dialogTitle: 'اختر ملف المخزون',
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _fileName = result.files.single.name;
      _state = _ImportState.loading;
    });
    _spinCtrl.repeat();

    // محاكاة المعالجة ثم عرض «قريباً»
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    _spinCtrl.stop();
    setState(() => _state = _ImportState.done);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const InnerTopBar(title: 'استيراد المخزون'),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.x3l),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: switch (_state) {
                _ImportState.idle => _IdleView(onTap: _pickFile),
                _ImportState.loading =>
                  _LoadingView(fileName: _fileName, controller: _spinCtrl),
                _ImportState.done => const _DoneView(),
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── الحالة الأولى: زر الاختيار ───────────────────────────────────────────
class _IdleView extends StatelessWidget {
  const _IdleView({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: tk.brandSurface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Center(
            child: AppIcon(AppIcons.fileText, size: 36, color: cs.primary),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'استيراد مخزونك',
          style: context.text.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'استورد قائمة أدويتك مباشرةً من ملف Excel\n'
          'بصيغة .xlsx أو .xls أو .csv',
          style: context.text.bodyMedium?.copyWith(color: tk.hint),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.x3l),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            label: 'اختر ملف Excel',
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // تلميح صغير
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(AppIcons.fileText, size: 14, color: tk.hint),
            const SizedBox(width: 4),
            Text(
              'xlsx · xls · csv',
              style: context.text.labelSmall?.copyWith(color: tk.hint),
            ),
          ],
        ),
      ],
    );
  }
}

// ── حالة المعالجة: أنيميشن دوران ─────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.fileName, required this.controller});
  final String? fileName;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RotationTransition(
                turns: controller,
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    strokeWidth: 5,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
              ),
              AppIcon(AppIcons.fileText, size: 36, color: cs.primary),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'جاري معالجة الملف…',
          style: context.text.titleMedium,
          textAlign: TextAlign.center,
        ),
        if (fileName != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            fileName!,
            style: context.text.bodySmall?.copyWith(color: tk.hint),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _AnimatedDots(),
      ],
    );
  }
}

class _AnimatedDots extends StatefulWidget {
  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _dot = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          setState(() => _dot = (_dot + 1) % 4);
          _ctrl.forward(from: 0);
        }
      });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = List.generate(3, (i) => i < _dot % 4 ? '●' : '○').join('  ');
    return Text(dots, style: context.text.bodyMedium?.copyWith(
      color: context.colors.primary,
      letterSpacing: 4,
    ));
  }
}

// ── حالة الانتهاء: قريباً ─────────────────────────────────────────────────
class _DoneView extends StatelessWidget {
  const _DoneView();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: tk.brandSurface,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Center(
            child: AppIcon(AppIcons.clock, size: 36, color: cs.primary),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'قريباً',
          style: context.text.titleLarge?.copyWith(
            color: cs.primary,
            fontSize: 32,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'ميزة الاستيراد التلقائي من Excel\nقيد التطوير وستكون متاحة قريباً',
          style: context.text.bodyMedium?.copyWith(color: tk.hint),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.x3l),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: tk.brandSurface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(AppIcons.bell, size: 16, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'سنُعلمك فور الإطلاق',
                style: context.text.bodySmall?.copyWith(color: cs.primary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
