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

enum _FileKind { excel, pdf }

class _WhImportInventoryPageState extends State<WhImportInventoryPage>
    with SingleTickerProviderStateMixin {
  _ImportState _state = _ImportState.idle;
  String? _fileName;
  _FileKind? _fileKind;
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

  Future<void> _pickFile(_FileKind kind) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kind == _FileKind.excel
          ? ['xlsx', 'xls', 'csv']
          : ['pdf'],
      dialogTitle: kind == _FileKind.excel
          ? 'اختر ملف Excel'
          : 'اختر ملف PDF',
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _fileName = result.files.single.name;
      _fileKind = kind;
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
                _ImportState.idle => _IdleView(onPick: _pickFile),
                _ImportState.loading => _LoadingView(
                    fileName: _fileName,
                    fileKind: _fileKind,
                    controller: _spinCtrl,
                  ),
                _ImportState.done => const _DoneView(),
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── الحالة الأولى: اختيار نوع الملف ─────────────────────────────────────
class _IdleView extends StatelessWidget {
  const _IdleView({required this.onPick});
  final void Function(_FileKind) onPick;

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
            child: AppIcon(AppIcons.clipboardList, size: 36, color: cs.primary),
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
          'استورد مخزونك مباشرةً من ملف Excel أو PDF',
          style: context.text.bodyMedium?.copyWith(color: tk.hint),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.x3l),

        // بطاقتا الاختيار: Excel و PDF جنباً لجنب
        Row(
          children: [
            Expanded(
              child: _FileTypeCard(
                icon: AppIcons.fileText,
                label: 'Excel',
                ext: '.xlsx / .xls / .csv',
                accentColor: const Color(0xFF217346),
                surfaceColor: const Color(0xFFE8F5EE),
                onTap: () => onPick(_FileKind.excel),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _FileTypeCard(
                icon: AppIcons.fileText,
                label: 'PDF',
                ext: '.pdf',
                accentColor: const Color(0xFFD32F2F),
                surfaceColor: const Color(0xFFFDEBEB),
                onTap: () => onPick(_FileKind.pdf),
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.x2l),

        AppCard(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            children: [
              AppIcon(AppIcons.info, size: 16, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'تأكّد من تطابق أعمدة الملف مع القالب المعتمد قبل الاستيراد',
                  style: context.text.bodySmall?.copyWith(color: tk.hint),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FileTypeCard extends StatelessWidget {
  const _FileTypeCard({
    required this.icon,
    required this.label,
    required this.ext,
    required this.accentColor,
    required this.surfaceColor,
    required this.onTap,
  });

  final AppIcons icon;
  final String label;
  final String ext;
  final Color accentColor;
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
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Center(
              child: AppIcon(icon, size: 26, color: accentColor),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            label,
            style: context.text.titleMedium?.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ext,
            style: context.text.labelSmall
                ?.copyWith(color: context.tokens.hint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── حالة المعالجة: أنيميشن دوران ─────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView({
    required this.fileName,
    required this.fileKind,
    required this.controller,
  });
  final String? fileName;
  final _FileKind? fileKind;
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
          fileKind == _FileKind.pdf
              ? 'جاري قراءة ملف PDF…'
              : 'جاري معالجة ملف Excel…',
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
