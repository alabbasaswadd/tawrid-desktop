import 'package:flutter/material.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/app_tokens_ext.dart';
import 'package:tawrid_app/shared/ui/app_icon.dart';
import 'package:tawrid_app/shared/utils/export.dart';
import 'package:tawrid_app/shared/widgets/app_states.dart';

/// زرّ تصديرٍ موحَّد — Excel أو PDF من قائمةٍ واحدة.
///
/// مكوّنٌ مشترك لأن التصدير يظهر في ست شاشات، ونسخةٌ في كلٍّ منها تعني
/// ست رسائل نجاحٍ مختلفة وست معالجاتٍ للخطأ — وواحدةٌ منها تُنسى.
///
/// والصيغتان في زرٍّ واحد لا زرّين: هما فعلٌ واحد بوجهين، وزرّان
/// متجاوران يُزاحمان شريط الأدوات في شاشةٍ فيها أزرارٌ أهمّ.
class ExportButton<T> extends StatefulWidget {
  const ExportButton({
    required this.fileName,
    required this.title,
    required this.columns,
    required this.rows,
    this.subtitle,
    this.sheetName,
    this.facts = const [],
    this.totals,
    this.compact = false,
    super.key,
  });

  /// اسم الملف بلا امتداد — يُقترَح في حوار الحفظ.
  final String fileName;

  /// عنوان التقرير في ترويسة الـ PDF.
  final String title;

  final String? subtitle;

  /// اسم تبويب Excel. فارغٌ = [title].
  final String? sheetName;

  final List<ExportColumn<T>> columns;
  final List<T> rows;

  /// حقائق تُعرَض فوق جدول الـ PDF — «عدد الأصناف: ٢٠».
  final List<PdfFact> facts;

  /// سطر إجماليٍّ أسفل الجدول.
  final List<String>? totals;

  /// أيقونةٌ وحدها بلا نصّ — لأشرطة الأدوات الضيّقة.
  final bool compact;

  @override
  State<ExportButton<T>> createState() => _ExportButtonState<T>();
}

class _ExportButtonState<T> extends State<ExportButton<T>> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, 'تعذّر التصدير: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _excel() => _run(() async {
        final path = await exportToExcel(
          fileName: widget.fileName,
          sheetName: widget.sheetName ?? widget.title,
          columns: widget.columns,
          rows: widget.rows,
        );

        if (!mounted) return;

        // المسار يُقال لا «تمّ الحفظ» وحدها: صاحبه يريد أن يعرف أين
        // ذهب الملف، وهو ما يبحث عنه بعد دقيقة.
        if (path != null) {
          AppSnackbar.success(context, 'حُفظ الملف: $path');
        }
      });

  Future<void> _pdf() => _run(() => exportToPdf(
        fileName: widget.fileName,
        title: widget.title,
        subtitle: widget.subtitle,
        columns: widget.columns,
        rows: widget.rows,
        facts: widget.facts,
        totals: widget.totals,
      ));

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    // جدولٌ فارغ لا يُصدَّر: ملفٌ بترويسةٍ وحدها يُربك من يفتحه.
    final enabled = widget.rows.isNotEmpty && !_busy;

    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: widget.rows.isEmpty ? 'لا شيء لتصديره' : 'تصدير',
      onSelected: (v) => v == 'excel' ? _excel() : _pdf(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'excel',
          child: Row(
            children: [
              AppIcon(AppIcons.fileText, size: 16, color: tk.success),
              const SizedBox(width: AppSpacing.sm),
              const Text('تصدير Excel'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'pdf',
          child: Row(
            children: [
              AppIcon(AppIcons.fileText, size: 16, color: tk.danger),
              const SizedBox(width: AppSpacing.sm),
              const Text('تصدير PDF'),
            ],
          ),
        ),
      ],
      child: widget.compact
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : AppIcon(AppIcons.fileImport,
                      size: 18, color: enabled ? cs.primary : tk.hint),
            )
          : Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: enabled ? cs.outline : cs.outline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    AppIcon(AppIcons.fileImport,
                        size: 14, color: enabled ? cs.primary : tk.hint),
                  const SizedBox(width: AppSpacing.sm),
                  Text('تصدير',
                      style: context.text.labelMedium
                          ?.copyWith(color: enabled ? cs.primary : tk.hint)),
                ],
              ),
            ),
    );
  }
}
