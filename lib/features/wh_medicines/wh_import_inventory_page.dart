import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/app_tokens_ext.dart';
import 'package:tawrid_app/core/network/api_exception.dart';
import 'package:tawrid_app/core/realtime/inventory_import_hub.dart';
import 'package:tawrid_app/models/ai_import_models.dart';
import 'package:tawrid_app/repositories/inventory_import_repository.dart';
import 'package:tawrid_app/shared/ui/ui.dart';

/// استيراد المخزون من ملف Excel بمساعدة وكيل الـ AI.
///
/// كل العمل في الخادم: الملف يُرفع، ويقرؤه الخادم وينادي الوكيل ويطابق مع
/// الكتالوج الوطني ويبثّ تقدّمه على قناة فورية. وهذه الشاشة تعرض ما يجري،
/// ثم تُراجِع، ثم تُطبّق وتعرض ماذا أُضيف وماذا عُدِّل.
///
/// لا يُكتب شيء في «أدويتي» قبل خطوة التطبيق.
class WhImportInventoryPage extends ConsumerStatefulWidget {
  const WhImportInventoryPage({super.key});

  @override
  ConsumerState<WhImportInventoryPage> createState() =>
      _WhImportInventoryPageState();
}

class _WhImportInventoryPageState extends ConsumerState<WhImportInventoryPage> {
  ImportJob? _job;
  ImportReport? _report;
  String? _error;

  String _activity = '';
  double _progress = 0;
  int _uploadPercent = 0;
  bool _uploading = false;

  /// تعديلات المستخدم في المراجعة — تُرسل عند التطبيق.
  final Map<String, double?> _priceOverrides = {};
  final Map<String, String> _catalogOverrides = {};
  List<ImportRow> _rows = const [];

  final List<StreamSubscription<void>> _subs = [];

  // استطلاعٌ احتياطي: القناة الفورية تسريعٌ لا ضمان، وإن سقطت يجب أن
  // تُكمل الشاشة بدل أن تتجمّد على آخر إطار وصلها.
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _listenToHub();
    _resumeActive();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _poll?.cancel();
    super.dispose();
  }

  // ── القناة الفورية ────────────────────────────────────────────────────
  Future<void> _listenToHub() async {
    final hub = ref.read(inventoryImportHubProvider);
    await hub.connect();

    _subs.add(hub.progress.listen((event) {
      if (!mounted || event.jobId != _job?.jobId) return;
      setState(() {
        _activity = event.activity;
        if (event.total > 0) {
          // التقدّم المعروض يُشتقّ من المرحلة ونسبتها، بنفس أوزان الخادم
          // حتى لا يختلف الشريط بين مصدرَي التحديث فيتراجع أمام العين.
          _progress = _weighted(event.phase, event.done / event.total);
        }
      });
    }));

    _subs.add(hub.ready.listen((jobId) {
      if (!mounted || jobId != _job?.jobId) return;
      _loadJob(jobId);
    }));

    _subs.add(hub.failed.listen((event) {
      if (!mounted || event.jobId != _job?.jobId) return;
      setState(() {
        _error = event.message;
        _job = null;
        _progress = 0;
      });
      _poll?.cancel();
    }));

    _subs.add(hub.onReconnected.listen((_) {
      // ما فات أثناء الانقطاع لا يُعوَّض إطاراً إطاراً — تُقرأ الحالة
      // من الخادم فتكون صحيحة مهما طال الانقطاع.
      final jobId = _job?.jobId;
      if (jobId != null) _loadJob(jobId, silent: true);
    }));
  }

  static double _weighted(ImportStatus phase, double fraction) =>
      switch (phase) {
        ImportStatus.analyzing => 0.05 + 0.70 * fraction.clamp(0, 1),
        ImportStatus.matching => 0.75 + 0.20 * fraction.clamp(0, 1),
        ImportStatus.ready || ImportStatus.applied => 1,
        _ => 0,
      };

  /// مهمة كانت جارية قبل إغلاق الشاشة — تُستأنف بدل أن تضيع.
  Future<void> _resumeActive() async {
    try {
      final job = await ref.read(inventoryImportRepositoryProvider).active();
      if (!mounted || job == null) return;
      _adopt(job);
      if (job.status == ImportStatus.ready) {
        await _loadJob(job.jobId);
      } else {
        _startPolling();
      }
    } on ApiException {
      // لا مهمة أو تعذّر السؤال — الشاشة تبدأ من الصفر بلا إزعاج.
    }
  }

  // ── الرفع ─────────────────────────────────────────────────────────────
  Future<void> _pick() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      // xls القديم صيغةٌ ثنائية مختلفة لا يقرؤها الخادم — يُحفَظ xlsx أولاً.
      allowedExtensions: const ['xlsx', 'csv'],
      dialogTitle: 'اختر ملف Excel',
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'تعذّر قراءة الملف من الجهاز');
      return;
    }

    setState(() {
      _error = null;
      _report = null;
      _rows = const [];
      _priceOverrides.clear();
      _catalogOverrides.clear();
      _uploading = true;
      _uploadPercent = 0;
      _progress = 0;
      _activity = 'يرفع الملف…';
    });

    try {
      final started = await ref.read(inventoryImportRepositoryProvider).start(
            bytes: bytes,
            fileName: file.name,
            onProgress: (sent, total) {
              if (!mounted || total <= 0) return;
              setState(() => _uploadPercent = (sent / total * 100).round());
            },
          );
      if (!mounted) return;

      setState(() {
        _uploading = false;
        _job = ImportJob(
          jobId: started.jobId,
          fileName: started.fileName,
          status: started.status,
          totalRows: started.totalRows,
          activity: 'في انتظار بدء التحليل…',
        );
        _activity = 'قرأ الخادم ${started.totalRows} صفاً — يبدأ التحليل…';
      });

      _startPolling();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = e.message;
      });
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      final job = _job;
      if (!mounted || job == null || !job.status.isRunning) return;
      _loadJob(job.jobId, silent: true, includeRows: false);
    });
  }

  Future<void> _loadJob(
    String jobId, {
    bool silent = false,
    bool includeRows = true,
  }) async {
    try {
      final job = await ref
          .read(inventoryImportRepositoryProvider)
          .get(jobId, includeRows: includeRows);
      if (!mounted) return;
      _adopt(job);
    } on ApiException catch (e) {
      if (!mounted || silent) return;
      setState(() => _error = e.message);
    }
  }

  void _adopt(ImportJob job) {
    setState(() {
      _job = job;
      _activity = job.activity ?? _activity;
      // الشريط لا يتراجع: إطارٌ متأخّر من القناة قد يحمل رقماً أقلّ ممّا
      // وصل، وتراجعه أمام العين يبدو عطلاً.
      _progress = job.progress > _progress ? job.progress : _progress;
      if (job.rows.isNotEmpty) _rows = job.rows;
      if (job.status == ImportStatus.failed) _error = job.failureMessage;
    });

    if (!job.status.isRunning) _poll?.cancel();
    if (job.status == ImportStatus.ready && job.rows.isEmpty) {
      _loadJob(job.jobId);
    }
  }

  // ── المراجعة ──────────────────────────────────────────────────────────
  void _toggle(int index) {
    final row = _rows[index];
    if (!row.isActionable) return;
    final next = [..._rows];
    next[index] = row.copyWith(selected: !row.selected);
    setState(() => _rows = next);
  }

  void _toggleAll() {
    final actionable = _rows.where((r) => r.isActionable);
    final allOn = actionable.isNotEmpty && actionable.every((r) => r.selected);
    setState(() {
      _rows = _rows
          .map((r) => r.isActionable ? r.copyWith(selected: !allOn) : r)
          .toList();
    });
  }

  Future<void> _chooseCandidate(int index) async {
    final row = _rows[index];
    if (row.candidates.isEmpty) return;

    final chosen = await showModalBottomSheet<ImportCandidate>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.colors.surface,
      builder: (_) => _CandidateSheet(row: row),
    );
    if (chosen == null || !mounted) return;

    final next = [..._rows];
    next[index] = row.copyWith(
      matched: chosen,
      matchStatus: ImportMatch.matched,
      selected: true,
    );
    setState(() {
      _rows = next;
      _catalogOverrides[row.id] = chosen.catalogItemId;
    });
  }

  Future<void> _editPrice(int index) async {
    final row = _rows[index];
    final controller = TextEditingController(
      text: row.price?.toString() ?? '',
    );

    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.surface,
        title: Text(row.matched?.displayName ?? row.name,
            style: ctx.text.titleMedium),
        content: AppTextField(
          controller: controller,
          label: 'السعر',
          hint: 'اتركه فارغاً ليُشتقّ تلقائياً',
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;

    final price = value.isEmpty ? null : double.tryParse(value);
    if (value.isNotEmpty && price == null) return; // نصّ ليس رقماً — يُهمَل

    final next = [..._rows];
    next[index] = ImportRow(
      id: row.id,
      rowNumber: row.rowNumber,
      rawCells: row.rawCells,
      name: row.name,
      strength: row.strength,
      form: row.form,
      manufacturer: row.manufacturer,
      quantity: row.quantity,
      price: price,
      confidence: row.confidence,
      note: row.note,
      matchStatus: row.matchStatus,
      selected: true,
      matched: row.matched,
      candidates: row.candidates,
      previousPrice: row.previousPrice,
      outcome: row.outcome,
      outcomeMessage: row.outcomeMessage,
    );

    setState(() {
      _rows = next;
      _priceOverrides[row.id] = price;
    });
  }

  Future<void> _apply() async {
    final job = _job;
    if (job == null) return;

    final selected = _rows
        .where((r) => r.selected && r.isActionable)
        .map((r) => r.id)
        .toList();
    if (selected.isEmpty) return;

    setState(() {
      _activity = 'يزامن مع مخزونك…';
      _progress = 1;
      _error = null;
    });

    try {
      final report =
          await ref.read(inventoryImportRepositoryProvider).apply(
                job.jobId,
                selectedRowIds: selected,
                priceOverrides: _priceOverrides,
                catalogOverrides: _catalogOverrides,
              );
      if (!mounted) return;
      setState(() => _report = report);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  void _reset() {
    _poll?.cancel();
    setState(() {
      _job = null;
      _report = null;
      _error = null;
      _rows = const [];
      _progress = 0;
      _activity = '';
      _priceOverrides.clear();
      _catalogOverrides.clear();
    });
  }

  // ── الرسم ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final job = _job;

    final Widget body;
    if (_report != null) {
      body = _ReportView(
        report: _report!,
        onDone: () => Navigator.of(context).maybePop(),
        onAgain: _reset,
      );
    } else if (_uploading) {
      body = _WorkingView(
        phase: ImportStatus.pending,
        activity: 'يرفع الملف… $_uploadPercent٪',
        progress: _uploadPercent / 100,
        fileName: null,
      );
    } else if (job != null && job.status.isRunning) {
      body = _WorkingView(
        phase: job.status,
        activity: _activity.isEmpty ? (job.activity ?? '') : _activity,
        progress: _progress,
        fileName: job.fileName,
      );
    } else if (job != null && job.status == ImportStatus.ready) {
      body = _ReviewView(
        job: job,
        rows: _rows,
        error: _error,
        onToggle: _toggle,
        onToggleAll: _toggleAll,
        onPickCandidate: _chooseCandidate,
        onEditPrice: _editPrice,
        onApply: _apply,
        onRestart: _reset,
      );
    } else {
      body = _IdleView(onPick: _pick, error: _error);
    }

    return Scaffold(
      appBar: const InnerTopBar(title: 'استيراد المخزون'),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(_stageKey), child: body),
      ),
    );
  }

  /// مفتاح المرحلة — يُبدّل الانتقال عند تغيّر المرحلة لا عند كل إطار تقدّم،
  /// وإلا أُعيد بناء الشاشة بتلاشٍ كامل ثلاث مرات في الثانية.
  String get _stageKey {
    if (_report != null) return 'report';
    if (_uploading) return 'upload';
    final status = _job?.status;
    if (status == null) return 'idle';
    if (status.isRunning) return 'working';
    if (status == ImportStatus.ready) return 'review';
    return 'idle';
  }
}

// ── الحالة الأولى ────────────────────────────────────────────────────────
class _IdleView extends StatelessWidget {
  const _IdleView({required this.onPick, this.error});

  final VoidCallback onPick;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.x2l, AppSpacing.page, AppSpacing.x3l),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BreathingIcon(
                icon: AppIcons.clipboardList,
                background: tk.brandSurface,
                color: cs.primary,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('استيراد قائمة الأدوية',
                  style: context.text.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'ارفع ملف Excel، ويقرأ وكيل الـ AI أعمدته ويطابق أصنافه مع '
                'الكتالوج الوطني — ولا يُضاف شيء لمخزونك قبل مراجعتك',
                style: context.text.bodyMedium?.copyWith(color: tk.hint),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.x2l),

              if (error != null) ...[
                _NoticeCard(
                  appIcon: AppIcons.alertTriangle,
                  tone: StatusTone.danger,
                  title: 'تعذّر الاستيراد',
                  body: error!,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              AppButton(
                label: 'اختر ملف Excel',
                appIcon: AppIcons.fileText,
                onPressed: onPick,
              ),
              const SizedBox(height: AppSpacing.x2l),

              AppCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AppIcon(AppIcons.info, size: 16, color: cs.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Text('كيف يعمل', style: context.text.labelLarge),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const _Hint('لا يلزم قالب معيّن — الوكيل يستنتج الأعمدة'),
                    const _Hint('يفصل العيار والشكل الدوائي عن اسم الدواء'),
                    const _Hint('تراجع النتيجة قبل أن يُكتب شيء في مخزونك'),
                    const _Hint('الصيغ المدعومة: xlsx و csv'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child:
                AppIcon(AppIcons.check, size: 12, color: context.tokens.hint),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text,
                style: context.text.bodySmall
                    ?.copyWith(color: context.tokens.hint)),
          ),
        ],
      ),
    );
  }
}

/// أيقونة تتنفّس — حركةٌ هادئة تُشعِر أن الشاشة حيّة بلا أن تُلفت.
class _BreathingIcon extends StatefulWidget {
  const _BreathingIcon({
    required this.icon,
    required this.background,
    required this.color,
  });

  final AppIcons icon;
  final Color background;
  final Color color;

  @override
  State<_BreathingIcon> createState() => _BreathingIconState();
}

class _BreathingIconState extends State<_BreathingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.97, end: 1.03).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: widget.background,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Center(
          child: AppIcon(widget.icon, size: 36, color: widget.color),
        ),
      ),
    );
  }
}

// ── «ماذا يجري الآن» ─────────────────────────────────────────────────────
class _WorkingView extends StatelessWidget {
  const _WorkingView({
    required this.phase,
    required this.activity,
    required this.progress,
    required this.fileName,
  });

  final ImportStatus phase;
  final String activity;
  final double progress;
  final String? fileName;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.x2l, AppSpacing.page, AppSpacing.x3l),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProgressRing(progress: progress),
              const SizedBox(height: AppSpacing.x2l),

              // نصّ ما يجري يتبدّل بتلاشٍ لا بقفزة — القفز بين جملتين
              // يجعل الشاشة تبدو مضطربة.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  activity,
                  key: ValueKey(activity),
                  style: context.text.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),

              if (fileName != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  fileName!,
                  style: context.text.bodySmall?.copyWith(color: tk.hint),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: AppSpacing.x2l),
              _PhaseStepper(current: phase),
              const SizedBox(height: AppSpacing.x2l),

              Text(
                'يمكنك إغلاق الشاشة — العمل يتابع في الخادم وتجده عند عودتك',
                style: context.text.labelSmall?.copyWith(color: tk.hint),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// حلقة تقدّم تتحرّك بسلاسة بين القيم بدل أن تقفز عند كل إطار.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: progress.clamp(0, 1)),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => SizedBox(
        width: 120,
        height: 120,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: CircularProgressIndicator(
                // صفراً تدور بلا قيمة: العمل بدأ ولا نسبة له بعد، وشريطٌ
                // واقفٌ على الصفر يبدو تجمّداً.
                value: value <= 0.01 ? null : value,
                strokeWidth: 6,
                strokeCap: StrokeCap.round,
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                backgroundColor: tk.brandSurface,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${(value * 100).round()}٪',
                    style: context.text.titleLarge?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                DotsLoader(color: cs.primary, size: 5),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// مراحل العمل الثلاث — المنجزة والجارية والقادمة، بحركة على الجارية.
class _PhaseStepper extends StatelessWidget {
  const _PhaseStepper({required this.current});
  final ImportStatus current;

  static const _phases = [
    (ImportStatus.pending, 'قراءة الملف', AppIcons.fileText),
    (ImportStatus.analyzing, 'تحليل الوكيل', AppIcons.messageSquare),
    (ImportStatus.matching, 'مطابقة الكتالوج', AppIcons.pill),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return Row(
      children: [
        for (var i = 0; i < _phases.length; i++) ...[
          if (i > 0)
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  end: current.code >= _phases[i].$1.code ? 1 : 0,
                ),
                duration: const Duration(milliseconds: 500),
                builder: (_, value, _) => Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    gradient: LinearGradient(
                      // التعبئة تمتدّ من بداية القراءة (اليمين في RTL).
                      begin: AlignmentDirectional.centerStart,
                      end: AlignmentDirectional.centerEnd,
                      stops: [value, value],
                      colors: [cs.primary, cs.outlineVariant],
                    ),
                  ),
                ),
              ),
            ),
          _PhaseDot(
            label: _phases[i].$2,
            icon: _phases[i].$3,
            done: current.code > _phases[i].$1.code,
            active: current == _phases[i].$1,
            hint: tk.hint,
          ),
        ],
      ],
    );
  }
}

class _PhaseDot extends StatelessWidget {
  const _PhaseDot({
    required this.label,
    required this.icon,
    required this.done,
    required this.active,
    required this.hint,
  });

  final String label;
  final AppIcons icon;
  final bool done;
  final bool active;
  final Color hint;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    final color = done || active ? cs.primary : hint;
    final background = done
        ? cs.primary
        : active
            ? tk.brandSurface
            : Colors.transparent;

    Widget dot = AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(
          color: done || active ? cs.primary : cs.outlineVariant,
          width: 1.5,
        ),
      ),
      child: Center(
        child: AppIcon(
          done ? AppIcons.check : icon,
          size: 18,
          color: done ? cs.onPrimary : color,
        ),
      ),
    );

    // المرحلة الجارية وحدها تنبض — فيعرف المستخدم أين يقف العمل الآن.
    if (active) dot = _Pulse(child: dot);

    return SizedBox(
      width: 92,
      child: Column(
        children: [
          dot,
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: color,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1.08).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
        ),
        child: widget.child,
      );
}

// ── المراجعة ─────────────────────────────────────────────────────────────
class _ReviewView extends StatelessWidget {
  const _ReviewView({
    required this.job,
    required this.rows,
    required this.onToggle,
    required this.onToggleAll,
    required this.onPickCandidate,
    required this.onEditPrice,
    required this.onApply,
    required this.onRestart,
    this.error,
  });

  final ImportJob job;
  final List<ImportRow> rows;
  final String? error;
  final void Function(int index) onToggle;
  final VoidCallback onToggleAll;
  final void Function(int index) onPickCandidate;
  final void Function(int index) onEditPrice;
  final VoidCallback onApply;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;

    final selected = rows.where((r) => r.selected && r.isActionable).toList();
    final newCount =
        selected.where((r) => r.matchStatus != ImportMatch.owned).length;
    final updateCount =
        selected.where((r) => r.matchStatus == ImportMatch.owned).length;
    final needsConfirm =
        rows.where((r) => r.matchStatus == ImportMatch.ambiguous).length;
    final notFound =
        rows.where((r) => r.matchStatus == ImportMatch.notFound).length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.lg),
            children: [
              _SummaryCard(summary: job.summary),

              if (error != null) ...[
                const SizedBox(height: AppSpacing.md),
                _NoticeCard(
                  appIcon: AppIcons.alertTriangle,
                  tone: StatusTone.danger,
                  title: 'تعذّرت المزامنة',
                  body: error!,
                ),
              ],

              const SizedBox(height: AppSpacing.lg),

              Row(
                children: [
                  Expanded(
                    child: _CountTile(
                      value: newCount,
                      label: 'جديد',
                      icon: AppIcons.plus,
                      tone: StatusTone.success,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _CountTile(
                      value: updateCount,
                      label: 'تحديث سعر',
                      icon: AppIcons.tag,
                      tone: StatusTone.info,
                    ),
                  ),
                ],
              ),
              if (needsConfirm > 0 || notFound > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _CountTile(
                        value: needsConfirm,
                        label: 'يلزم تأكيد',
                        icon: AppIcons.alertTriangle,
                        tone: StatusTone.warning,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _CountTile(
                        value: notFound,
                        label: 'غير موجود',
                        icon: AppIcons.x,
                        tone: StatusTone.danger,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: AppSpacing.lg),

              AppSectionHeader(
                title: 'الأصناف (${rows.length})',
                appIcon: AppIcons.pill,
                trailing: GestureDetector(
                  onTap: onToggleAll,
                  child: Text('تحديد الكل',
                      style: context.text.labelMedium
                          ?.copyWith(color: context.colors.primary)),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              if (rows.isEmpty)
                const UiEmpty(
                  message: 'لا أصناف',
                  description: 'لم يتعرّف الوكيل على أي صنف في هذا الملف',
                  appIcon: AppIcons.pill,
                )
              else
                for (var i = 0; i < rows.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _Appear(
                      index: i,
                      child: _MatchRow(
                        row: rows[i],
                        onToggle: () => onToggle(i),
                        onPickCandidate: () => onPickCandidate(i),
                        onEditPrice: () => onEditPrice(i),
                      ),
                    ),
                  ),
            ],
          ),
        ),

        // شريط الإجراء ثابتٌ أسفل الشاشة — فلا يُضيع المستخدم زرّ المزامنة
        // في قائمةٍ طويلة.
        Container(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.lg),
          decoration: BoxDecoration(
            color: context.colors.surface,
            boxShadow: tk.navShadow,
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'ملف آخر',
                    variant: AppButtonVariant.outline,
                    onPressed: onRestart,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 2,
                  child: AppButton(
                    label: selected.isEmpty
                        ? 'لا شيء محدَّد'
                        : 'مزامنة ${selected.length} صنفاً',
                    appIcon: AppIcons.check,
                    onPressed: selected.isEmpty ? null : onApply,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// ظهورٌ متتالٍ للعناصر — القائمة تتجمّع أمام العين بدل أن تقع دفعةً واحدة.
class _Appear extends StatelessWidget {
  const _Appear({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // التأخير يُقصَر ثم يتوقّف عند حدّ: قائمةٌ بمئة صنف لا يجوز أن ينتظر
    // آخرها ثوانٍ ليظهر.
    final delay = Duration(milliseconds: (index.clamp(0, 12)) * 45);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320) + delay,
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.tone,
  });

  final int value;
  final String label;
  final AppIcons icon;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final (fg, bg) = switch (tone) {
      StatusTone.success => (tk.success, tk.successSurface),
      StatusTone.warning => (tk.warning, tk.warningSurface),
      StatusTone.danger => (tk.danger, tk.dangerSurface),
      _ => (context.colors.primary, tk.brandSurface),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          AppIcon(icon, size: 18, color: fg),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // الرقم يتدرّج إلى قيمته بدل أن يحلّ فجأة — فيُلاحَظ تغيّره
                // عند كل تحديد.
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: value.toDouble()),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOut,
                  builder: (_, v, _) => Text(
                    '${v.round()}',
                    style: context.text.titleMedium
                        ?.copyWith(color: fg, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(label,
                    style: context.text.labelSmall?.copyWith(color: tk.hint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final ImportSummary summary;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(AppIcons.messageSquare, size: 18, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Text('ملخّص الوكيل', style: context.text.labelLarge),
            ],
          ),
          if (summary.text.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(summary.text, style: context.text.bodySmall),
          ],
          if (summary.columns.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('الأعمدة كما فُهمت',
                style: context.text.labelSmall?.copyWith(color: tk.hint)),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final c in summary.columns)
                  StatusBadge(label: c, tone: StatusTone.neutral),
              ],
            ),
          ],
          for (final w in summary.warnings) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: AppIcon(AppIcons.alertTriangle,
                      size: 14, color: tk.warning),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(w,
                      style:
                          context.text.bodySmall?.copyWith(color: tk.warning)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.row,
    required this.onToggle,
    required this.onPickCandidate,
    required this.onEditPrice,
  });

  final ImportRow row;
  final VoidCallback onToggle;
  final VoidCallback onPickCandidate;
  final VoidCallback onEditPrice;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final item = row.matched;

    final (label, tone) = switch (row.matchStatus) {
      ImportMatch.matched => ('مطابق', StatusTone.success),
      ImportMatch.owned => ('لديك — تحديث السعر', StatusTone.info),
      ImportMatch.ambiguous => ('أكّد الصنف', StatusTone.warning),
      ImportMatch.notFound => ('غير موجود', StatusTone.danger),
    };

    return AppCard(
      onTap: row.isActionable ? onToggle : null,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.isActionable)
            AnimatedScale(
              scale: row.selected ? 1 : 0.9,
              duration: const Duration(milliseconds: 180),
              child: AppCheckbox(
                selection:
                    row.selected ? AppCheckState.all : AppCheckState.none,
              ),
            )
          else
            AppIcon(AppIcons.x, size: 18, color: tk.danger),
          const SizedBox(width: AppSpacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item?.displayName ?? row.name,
                    style: context.text.labelLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(_subtitle(item, row),
                    style: context.text.labelSmall?.copyWith(color: tk.hint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    StatusBadge(label: label, tone: tone),
                    if (row.candidates.length > 1) ...[
                      const SizedBox(width: AppSpacing.sm),
                      GestureDetector(
                        onTap: onPickCandidate,
                        child: Row(
                          children: [
                            AppIcon(AppIcons.chevronForwardRtl,
                                size: 12, color: context.colors.primary),
                            const SizedBox(width: 2),
                            Text('تغيير',
                                style: context.text.labelSmall?.copyWith(
                                    color: context.colors.primary)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (row.note != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(row.note!,
                      style:
                          context.text.labelSmall?.copyWith(color: tk.warning),
                      maxLines: 2),
                ],
              ],
            ),
          ),

          const SizedBox(width: AppSpacing.sm),
          GestureDetector(
            onTap: row.isActionable ? onEditPrice : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    if (row.isActionable)
                      AppIcon(AppIcons.pencil, size: 11, color: tk.hint),
                    if (row.isActionable) const SizedBox(width: 3),
                    Text(
                      row.price == null ? 'بلا سعر' : _num(row.price!),
                      style: row.price == null
                          ? context.text.labelSmall?.copyWith(color: tk.hint)
                          : context.priceBrandStyle,
                    ),
                  ],
                ),
                if (row.previousPrice != null &&
                    row.previousPrice != row.price)
                  Text('كان ${_num(row.previousPrice!)}',
                      style: context.text.labelSmall?.copyWith(
                        color: tk.hint,
                        decoration: TextDecoration.lineThrough,
                      )),
                Text('سطر ${row.rowNumber}',
                    style: context.text.labelSmall?.copyWith(color: tk.hint)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _subtitle(ImportCandidate? item, ImportRow row) {
    final parts = <String>[];
    if (item != null) {
      if (item.strength > 0) parts.add(_num(item.strength));
      if (item.manufacturerName.isNotEmpty) parts.add(item.manufacturerName);
      if (item.sakoCode.isNotEmpty) parts.add(item.sakoCode);
    } else {
      // بلا مطابقة يُعرَض ما قرأه الوكيل، ليعرف المستخدم لماذا فشلت.
      if (row.strength != null) parts.add(_num(row.strength!));
      if (row.form != null) parts.add(row.form!);
      if (row.manufacturer != null) parts.add(row.manufacturer!);
    }
    return parts.isEmpty ? 'كما ورد: ${row.name}' : parts.join(' · ');
  }
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class _CandidateSheet extends StatelessWidget {
  const _CandidateSheet({required this.row});
  final ImportRow row;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionHeader(
              title: 'اختر الصنف الصحيح',
              subtitle: 'كما ورد في الملف: ${row.name}',
              appIcon: AppIcons.pill,
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: row.candidates.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) {
                  final c = row.candidates[i];
                  final isCurrent = c.catalogItemId == row.matched?.catalogItemId;

                  return _Appear(
                    index: i,
                    child: AppCard(
                      onTap: () => Navigator.of(context).pop(c),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.displayName,
                                    style: context.text.labelLarge),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (c.strength > 0) _num(c.strength),
                                    if (c.manufacturerName.isNotEmpty)
                                      c.manufacturerName,
                                    if (c.sakoCode.isNotEmpty) c.sakoCode,
                                  ].join(' · '),
                                  style: context.text.labelSmall
                                      ?.copyWith(color: tk.hint),
                                ),
                              ],
                            ),
                          ),
                          if (isCurrent)
                            const StatusBadge(
                                label: 'الحالي', tone: StatusTone.brand),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── التقرير النهائي: ماذا أُضيف وماذا عُدِّل ──────────────────────────────
class _ReportView extends StatelessWidget {
  const _ReportView({
    required this.report,
    required this.onDone,
    required this.onAgain,
  });

  final ImportReport report;
  final VoidCallback onDone;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final ok = report.total > 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.x2l, AppSpacing.page, AppSpacing.x3l),
      children: [
        Center(
          child: _SuccessBadge(
            ok: ok,
            color: ok ? tk.success : tk.warning,
            background: ok ? tk.successSurface : tk.warningSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          ok ? 'تمّت المزامنة' : 'لم يُزامَن شيء',
          style: context.text.titleLarge
              ?.copyWith(color: ok ? tk.success : tk.warning),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          ok
              ? '${report.added.length} صنفاً جديداً · '
                  '${report.modified.length} سعراً مُحدَّثاً'
              : 'لم يتغيّر شيء في مخزونك',
          style: context.text.bodySmall?.copyWith(color: tk.hint),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.x2l),

        if (report.added.isNotEmpty)
          _ReportSection(
            title: 'أُضيف إلى أدويتي',
            icon: AppIcons.plus,
            tone: StatusTone.success,
            items: report.added,
            showPrevious: false,
          ),

        if (report.modified.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _ReportSection(
            title: 'عُدِّل سعره',
            icon: AppIcons.tag,
            tone: StatusTone.info,
            items: report.modified,
            showPrevious: true,
          ),
        ],

        if (report.hasFailures) ...[
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(AppIcons.alertTriangle, size: 16, color: tk.danger),
                    const SizedBox(width: AppSpacing.sm),
                    Text('تعذّر ${report.failed.length}',
                        style: context.text.labelLarge
                            ?.copyWith(color: tk.danger)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final f in report.failed.take(10))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      'السطر ${f.rowNumber} — ${f.name}: ${f.message}',
                      style:
                          context.text.bodySmall?.copyWith(color: tk.hint),
                    ),
                  ),
                if (report.failed.length > 10)
                  Text('…و${report.failed.length - 10} غيرها',
                      style:
                          context.text.labelSmall?.copyWith(color: tk.hint)),
              ],
            ),
          ),
        ],

        if (report.skippedCount > 0) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'تُرك ${report.skippedCount} صفاً بلا تغيير',
            style: context.text.labelSmall?.copyWith(color: tk.hint),
            textAlign: TextAlign.center,
          ),
        ],

        const SizedBox(height: AppSpacing.x2l),
        AppButton(
          label: 'عودة إلى أدويتي',
          appIcon: AppIcons.check,
          onPressed: onDone,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'استيراد ملف آخر',
          variant: AppButtonVariant.text,
          onPressed: onAgain,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'سعرٌ لم يُحدَّد يبقى مشتقّاً تلقائياً من سعر المستهلك',
          style: context.text.labelSmall?.copyWith(color: context.colors.outline),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// علامة النجاح تظهر بارتداد — لحظة الإنجاز تستحق تمييزاً.
class _SuccessBadge extends StatefulWidget {
  const _SuccessBadge({
    required this.ok,
    required this.color,
    required this.background,
  });

  final bool ok;
  final Color color;
  final Color background;

  @override
  State<_SuccessBadge> createState() => _SuccessBadgeState();
}

class _SuccessBadgeState extends State<_SuccessBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: widget.background,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: AppIcon(
            widget.ok ? AppIcons.check : AppIcons.alertTriangle,
            size: 38,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({
    required this.title,
    required this.icon,
    required this.tone,
    required this.items,
    required this.showPrevious,
  });

  final String title;
  final AppIcons icon;
  final StatusTone tone;
  final List<ImportAppliedItem> items;
  final bool showPrevious;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final fg = switch (tone) {
      StatusTone.success => tk.success,
      StatusTone.info => tk.info,
      _ => context.colors.primary,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: '$title (${items.length})',
          appIcon: icon,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < items.length; i++)
          _Appear(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    AppIcon(icon, size: 14, color: fg),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(items[i].displayName,
                              style: context.text.labelMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          if (items[i].manufacturerName.isNotEmpty)
                            Text(items[i].manufacturerName,
                                style: context.text.labelSmall
                                    ?.copyWith(color: tk.hint),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),

                    // للمُعدَّل: من كم إلى كم. السعر الجديد وحده خبرٌ ناقص.
                    Row(
                      children: [
                        if (showPrevious && items[i].previousPrice != null) ...[
                          Text(
                            _num(items[i].previousPrice!),
                            style: context.text.labelSmall?.copyWith(
                              color: tk.hint,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 4),
                          AppIcon(AppIcons.chevronForwardRtl,
                              size: 10, color: tk.hint),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          items[i].price == null
                              ? 'مشتقّ'
                              : _num(items[i].price!),
                          style: items[i].price == null
                              ? context.text.labelSmall
                                  ?.copyWith(color: tk.hint)
                              : context.priceBrandStyle,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// بطاقة تنبيه موحّدة للخطأ/التحذير داخل هذه الشاشة.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.appIcon,
    required this.tone,
    required this.title,
    required this.body,
  });

  final AppIcons appIcon;
  final StatusTone tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final (fg, bg) = switch (tone) {
      StatusTone.danger => (tk.danger, tk.dangerSurface),
      StatusTone.warning => (tk.warning, tk.warningSurface),
      _ => (tk.info, tk.brandSurface),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AppIcon(appIcon, size: 16, color: fg),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: context.text.labelLarge?.copyWith(color: fg)),
                const SizedBox(height: 2),
                Text(body, style: context.text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
