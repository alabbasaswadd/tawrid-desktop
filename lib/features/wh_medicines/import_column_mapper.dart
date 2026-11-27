import 'package:flutter/material.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/app_tokens_ext.dart';
import 'package:tawrid_app/models/ai_import_models.dart';
import 'package:tawrid_app/shared/ui/ui.dart';

/// حقلٌ يُسنَد إلى عمود.
///
/// الاسم والسعر أوّلاً لأنهما المقصودان: الاسم هو هويّة الصنف، والسعر
/// هو ما يُخطئه الوكيل حين يحمل الملف عمودَي سعر.
enum _Field {
  name('الصنف', 'اسم الدواء كما كُتب', true),
  price('السعر', 'سعر البيع للصيدلية', true),
  company('الشركة', 'المصنّعة أو المورّدة', false),
  quantity('الكمية', 'عدد الوحدات', false),
  unit('الوحدة', 'علبة · شريط · كرتونة', false),
  discount('الخصم ٪', 'نسبةٌ من صفر إلى مئة', false),
  bonus('البونص', 'بصيغة «١٠+١»', false),
  strength('العيار', 'بالملغ', false);

  const _Field(this.label, this.hint, this.essential);

  final String label;
  final String hint;

  /// حقلٌ لا يقوم الاستيراد بدونه — يُميَّز في القائمة.
  final bool essential;
}

/// نتيجة الشاشة — خريطةٌ أقرّها المستخدم.
class ColumnMapResult {
  const ColumnMapResult({required this.map, required this.clearUnmapped});

  /// الحقل → فهرس عموده. الغائب يعني «اترك ما قرأه الوكيل».
  final Map<String, int> map;

  final bool clearUnmapped;

  int? operator [](String field) => map[field];
}

/// تصحيح خريطة الأعمدة.
///
/// ── لماذا هذه الشاشة؟ ───────────────────────────────────────────────────
/// الوكيل يُفسّر الأعمدة من الدفعة الأولى ويُقفل تفسيره على الملف كلّه.
/// وملفٌ فيه «سعر عموم» و«سعر مستهلك» — إن اختار الثاني — تصير كل
/// أسعاره خاطئة. وكان التفسير يُعرَض للقراءة فقط: شرائحُ لا تُنقَر. فلا
/// علاج إلا تعديل سبعمئة سعرٍ يدوياً أو إعادة الرفع أملاً في جوابٍ آخر.
///
/// ── ولماذا بلا نداءٍ جديد؟ ─────────────────────────────────────────────
/// لأن الخطأ في الاختيار لا في الفهم: الوكيل رأى العمودين وعرفهما، لكنه
/// اختار الخطأ منهما. والخلايا الخام محفوظة، فالتصحيح قراءةٌ حتمية —
/// فوريةٌ على سبعمئة صفّ وبلا ثمن.
///
/// ── وكيف يعرف المستخدم أي عمودٍ هو أيّها؟ ──────────────────────────────
/// بالقيم لا بالترويسة: الشاشة تعرض ثلاث قيمٍ حقيقية من ملفه تحت كل
/// عمود. فمن يرى «1.63 · 3.58 · 2.28» يعرف أنه السعر، ومن يرى
/// «GMP · GMP · GMP» يعرف أنها الشركة — ولو كانت الترويسة غائبة أصلاً.
class ImportColumnMapper extends StatefulWidget {
  const ImportColumnMapper({required this.rows, this.agentColumns = const [], super.key});

  /// صفوف المهمة — تُقرأ منها الخلايا الخام والقيم المعروضة.
  final List<ImportRow> rows;

  /// وصف الوكيل لكل عمود — يُعرَض تحت القيم كقرينةٍ لا كحقيقة.
  final List<String> agentColumns;

  @override
  State<ImportColumnMapper> createState() => _ImportColumnMapperState();
}

class _ImportColumnMapperState extends State<ImportColumnMapper> {
  /// الحقل → فهرس العمود المختار.
  final Map<_Field, int> _picked = {};

  bool _clearUnmapped = false;

  /// خلايا كل صفّ، مفكَّكةً مرّةً لا في كل إعادة بناء.
  late final List<List<String>> _cells = widget.rows
      .map((r) => _split(r.rawCells))
      .where((c) => c.isNotEmpty)
      .toList();

  /// عدد الأعمدة — أطولُ صفّ.
  ///
  /// لا أوّلُه: xlsx يحذف الخلايا الفارغة في آخر السطر، فصفٌّ بلا بونص
  /// أقصر من أخيه — والأخذ بالأول يُخفي عموداً كاملاً.
  late final int _columns =
      _cells.fold(0, (max, c) => c.length > max ? c.length : max);

  @override
  void initState() {
    super.initState();
    _guessFromAgent();
  }

  /// يستنتج الخريطة الحالية بمقارنة ما قرأه الوكيل بالخلايا الخام.
  ///
  /// ── لماذا استنتاجاً لا قراءةً؟ ────────────────────────────────────────
  /// لأن الوكيل لا يُعيد فهارس أعمدة بل قيماً مقروءة، ووصفُه للأعمدة
  /// نصٌّ حرّ لا يُطابَق عليه. فالطريق الوحيد أن نبحث عن القيمة التي
  /// قرأها في خلايا الصفّ نفسه.
  ///
  /// ويُصوَّت عليه عبر عدّة صفوف: صفٌّ واحد قد يحمل السعر والكمية
  /// متساويين صدفةً، وعشرةٌ لا تتفق على ذلك.
  void _guessFromAgent() {
    for (final field in _Field.values) {
      final votes = <int, int>{};

      for (var i = 0; i < widget.rows.length && i < 20; i++) {
        final row = widget.rows[i];
        final cells = _split(row.rawCells);
        if (cells.isEmpty) continue;

        final target = _valueOf(row, field);
        if (target == null || target.isEmpty) continue;

        for (var c = 0; c < cells.length; c++) {
          if (_sameValue(cells[c], target)) {
            votes[c] = (votes[c] ?? 0) + 1;
          }
        }
      }

      if (votes.isEmpty) continue;

      final best = votes.entries.reduce((a, b) => a.value >= b.value ? a : b);

      // صوتٌ واحد ليس استنتاجاً: قد يكون تصادفاً بين عمودين.
      if (best.value >= 2) _picked[field] = best.key;
    }
  }

  /// ما قرأه الوكيل لهذا الحقل في هذا الصفّ — نصّاً للمقارنة.
  static String? _valueOf(ImportRow row, _Field field) => switch (field) {
        _Field.name => row.sourceLabel ?? row.name,
        _Field.price => _num(row.price),
        _Field.company => row.company,
        _Field.quantity => row.quantity?.toString(),
        _Field.unit => row.unit,
        _Field.discount => _num(row.discountPercentage),
        _Field.bonus => row.bonusLabel,
        _Field.strength => _num(row.strength),
      };

  static String? _num(double? v) {
    if (v == null || v == 0) return null;
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  /// هل الخليّة هي القيمة نفسها؟
  ///
  /// مقارنةٌ متساهلة: الوكيل ينظّف ويُحوّل («1,63» تصير 1.63، و«10+1»
  /// تصير طبقتين)، فالتطابق الحرفي يفشل على أكثر الحقول.
  static bool _sameValue(String cell, String target) {
    final a = _loose(cell);
    final b = _loose(target);
    if (a.isEmpty || b.isEmpty) return false;

    return a == b || a.contains(b) || b.contains(a);
  }

  static String _loose(String s) {
    final buf = StringBuffer();
    for (final ch in s.toLowerCase().runes) {
      // الأرقام العربية تُوحَّد، والفواصل والمسافات تُطرح — فيبقى
      // الجوهر قابلاً للمقارنة.
      if (ch >= 0x0660 && ch <= 0x0669) {
        buf.writeCharCode(ch - 0x0660 + 0x30);
      } else if (ch == 0x2C || ch == 0x66B) {
        buf.write('.');
      } else if (ch == 0x20 || ch == 0x060C) {
        continue;
      } else {
        buf.writeCharCode(ch);
      }
    }
    return buf.toString();
  }

  static List<String> _split(String raw) {
    final at = raw.indexOf('|');
    final body = at < 0 ? raw : raw.substring(at + 1);
    return body.split('|').map((c) => c.trim()).toList();
  }

  /// ثلاث قيمٍ غير فارغة من هذا العمود — دليلُ المستخدم على ما فيه.
  List<String> _samples(int column) {
    final out = <String>[];
    for (final cells in _cells) {
      if (column >= cells.length) continue;
      final v = cells[column].trim();
      if (v.isEmpty) continue;
      out.add(v);
      if (out.length == 3) break;
    }
    return out;
  }

  /// الحقل المُسنَد إلى هذا العمود — أو فارغ.
  _Field? _fieldOf(int column) {
    for (final e in _picked.entries) {
      if (e.value == column) return e.key;
    }
    return null;
  }

  void _assign(int column, _Field? field) {
    setState(() {
      // ── الحقل لعمودٍ واحد ────────────────────────────────────────────
      // إسناده لعمودين يجعل القراءة غير محدّدة. فاختيارُه هنا يُزيله
      // من حيث كان — وهو ما يتوقّعه من يُصحّح: «لا، السعر هذا العمود».
      _picked.removeWhere((_, v) => v == column);
      if (field != null) _picked[field] = column;
    });
  }

  String? get _blocker {
    if (_picked.isEmpty) return 'أسنِد عموداً واحداً على الأقل';
    if (!_picked.containsKey(_Field.name) && _clearUnmapped) {
      return 'لا يمكن مسح عمود الصنف — المخزون لا يقبل صفاً بلا اسم';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;
    final blocker = _blocker;

    return Scaffold(
      appBar: const InnerTopBar(title: 'تصحيح الأعمدة'),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md,
                AppSpacing.page, AppSpacing.md),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(bottom: BorderSide(color: cs.outline)),
            ),
            child: Row(
              children: [
                AppIcon(AppIcons.info, size: 16, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'اختر لكل عمودٍ ما يحمله. القيم تحته من ملفك — فإن '
                    'رأيت السعر في عمودٍ غير المُسنَد، أسنِده وستُقرأ '
                    'الصفوف كلّها من جديد.',
                    style: context.text.bodySmall,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _columns == 0
                ? const UiEmpty(
                    message: 'لا أعمدة تُقرأ',
                    description: 'الملف لم يُحفَظ بخلاياه الخام',
                    appIcon: AppIcons.alertTriangle,
                  )
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.page),
                    children: [
                      LayoutBuilder(
                        builder: (context, box) {
                          // بطاقةٌ لكل ٣٢٠ بكسل: أضيق منها تقطع القيم
                          // المعروضة فتفقد فائدتها.
                          final cols =
                              columnsFor(box.maxWidth, minTile: 320, max: 4);

                          return Column(
                            children: [
                              for (var i = 0; i < _columns; i += cols) ...[
                                if (i > 0)
                                  const SizedBox(height: AppSpacing.md),
                                IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (var j = i; j < i + cols; j++) ...[
                                        if (j > i)
                                          const SizedBox(
                                              width: AppSpacing.md),
                                        Expanded(
                                          child: j < _columns
                                              ? _ColumnCard(
                                                  index: j,
                                                  samples: _samples(j),
                                                  agentNote: j <
                                                          widget.agentColumns
                                                              .length
                                                      ? widget
                                                          .agentColumns[j]
                                                      : null,
                                                  assigned: _fieldOf(j),
                                                  taken: _picked.keys.toSet(),
                                                  onAssign: (f) =>
                                                      _assign(j, f),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: AppSpacing.lg),
                      InkWell(
                        onTap: () =>
                            setState(() => _clearUnmapped = !_clearUnmapped),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: Row(
                            children: [
                              AppCheckbox(
                                selection: _clearUnmapped
                                    ? AppCheckState.all
                                    : AppCheckState.none,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('امسح ما لم أُسنِده',
                                        style: context.text.labelMedium),
                                    Text(
                                      'افتراضاً يبقى ما قرأه الوكيل كما '
                                      'هو. علّم هنا إن أردت إفراغ حقلٍ '
                                      'قرأه من عمودٍ لا يخصّه.',
                                      style: context.text.labelSmall
                                          ?.copyWith(color: tk.hint),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),

          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md,
                AppSpacing.page, AppSpacing.lg),
            decoration:
                BoxDecoration(color: cs.surface, boxShadow: tk.navShadow),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
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
                            '${_picked.length} '
                            '${_picked.length == 1 ? "حقلاً" : "حقول"} '
                            'مُسنَدة — ستُقرأ ${widget.rows.length} صفاً من جديد',
                            style: context.text.labelSmall
                                ?.copyWith(color: tk.hint),
                          ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 140,
                    child: AppButton(
                      label: 'تراجع',
                      variant: AppButtonVariant.outline,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 240,
                    child: AppButton(
                      label: 'طبّق على كل الصفوف',
                      appIcon: AppIcons.check,
                      onPressed: blocker != null
                          ? null
                          : () => Navigator.of(context).pop(
                                ColumnMapResult(
                                  map: {
                                    for (final e in _picked.entries)
                                      e.key.name: e.value,
                                  },
                                  clearUnmapped: _clearUnmapped,
                                ),
                              ),
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

/// بطاقةُ عمودٍ: قيمُه الحقيقية، وما يُسنَد إليه.
class _ColumnCard extends StatelessWidget {
  const _ColumnCard({
    required this.index,
    required this.samples,
    required this.agentNote,
    required this.assigned,
    required this.taken,
    required this.onAssign,
  });

  final int index;
  final List<String> samples;

  /// وصف الوكيل لهذا العمود — قرينةٌ لا حقيقة.
  final String? agentNote;

  final _Field? assigned;

  /// الحقول المُسنَدة لأعمدةٍ أخرى — تُعرَض مع موضعها لا تُخفى.
  final Set<_Field> taken;

  final ValueChanged<_Field?> onAssign;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;
    final on = assigned != null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: on ? tk.brandSurface : cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: on ? cs.primary.withValues(alpha: 0.5) : cs.outline,
          width: on ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('العمود ${index + 1}',
                  style: context.text.labelMedium
                      ?.copyWith(color: on ? cs.primary : tk.hint)),
              const Spacer(),
              if (assigned?.essential ?? false)
                StatusBadge(label: 'أساسي', tone: StatusTone.brand),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // ── القيم هي الدليل ──────────────────────────────────────────
          // الترويسة قد تغيب أو تكذب، والقيم لا: من يرى «1.63 · 3.58»
          // يعرف أنه سعر، ومن يرى «GMP · GMP» يعرف أنها شركة.
          if (samples.isEmpty)
            Text('العمود فارغ',
                style: context.text.labelSmall?.copyWith(color: tk.hint))
          else
            for (final s in samples)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  s,
                  style: context.text.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

          if ((agentNote ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('قراءة الوكيل: $agentNote',
                style: context.text.labelSmall
                    ?.copyWith(color: tk.hint, fontStyle: FontStyle.italic),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],

          const Spacer(),
          const SizedBox(height: AppSpacing.sm),

          DropdownButtonFormField<_Field?>(
            initialValue: assigned,
            isDense: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              filled: true,
              fillColor: cs.surface,
            ),
            items: [
              const DropdownMenuItem<_Field?>(
                value: null,
                child: Text('— لا يُستعمل'),
              ),
              for (final f in _Field.values)
                DropdownMenuItem<_Field?>(
                  value: f,
                  child: Row(
                    children: [
                      Text(f.label),

                      // الحقل المأخوذ لا يُخفى: إخفاؤه يجعل المستخدم
                      // يظنّه غير متاح. ونقرُه ينقله إلى هنا — وهو ما
                      // يريده حين يُصحّح.
                      if (taken.contains(f) && f != assigned) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Text('(منقول)',
                            style: context.text.labelSmall
                                ?.copyWith(color: tk.hint)),
                      ],
                    ],
                  ),
                ),
            ],
            onChanged: onAssign,
          ),

          if (assigned != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(assigned!.hint,
                style: context.text.labelSmall?.copyWith(color: tk.hint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}
