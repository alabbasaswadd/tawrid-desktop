/// تصدير الجداول — Excel و PDF.
///
/// مكانٌ واحد لأن الشاشات التي تُصدّر ستّ، ونسخةٌ في كلٍّ منها تعني
/// ستّ ترويساتٍ تفترق عند أول تعديل: شعارٌ في واحدة وتاريخٌ بصيغةٍ
/// أخرى في الثانية.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:tawrid_app/shared/utils/xlsx.dart';



/// عمودٌ في جدول التصدير — عنوانٌ وقارئُ قيمة.
///
/// القيمة تُقرأ من الصفّ ولا تُمرَّر مبنيّةً: الصيغة تختلف بين Excel
/// و PDF — الأول يريد الرقم رقماً ليُجمَع، والثاني نصّاً مصوغاً.
class ExportColumn<T> {
  const ExportColumn({
    required this.header,
    required this.value,
    this.text,
    this.width = 14,
    this.pdfFlex = 2,
  });

  final String header;

  /// القيمة الخام — رقمٌ أو نصّ. تذهب إلى Excel كما هي.
  final Object? Function(T row) value;

  /// صيغتها للعرض في PDF. فارغٌ = تُكتب كما هي.
  final String Function(T row)? text;

  /// عرض العمود في Excel (وحدة Excel ≈ ٧ بكسل).
  final double width;

  /// وزن العمود في جدول PDF.
  final int pdfFlex;

  String render(T row) {
    final f = text;
    if (f != null) return f(row);
    final v = value(row);
    return v == null ? '' : '$v';
  }
}

/// اسمُ ملفٍ يقبله نظام الملفات.
///
/// ── لماذا؟ ────────────────────────────────────────────────────────────
/// أسماء التصدير تُبنى من بيانات المستخدم: «عرض ابن حيان 27/11». والشرطة
/// المائلة فاصلُ مسارٍ في ويندوز ولينكس معاً، فيُفهَم الاسم مجلّداً لا
/// ملفاً — ويخرج الحوار برسالة:
///
///     يتعذر على Windows العثور على C:\…\Temp\عرض ابن حيان 27
///
/// ورآه المستخدم على عرضٍ عنوانه تاريخُ إنشائه — وهو العنوان الافتراضي
/// لكل عرضٍ يُنشئه الاستيراد. أي أن التصدير كان يسقط على أكثر الحالات
/// شيوعاً لا على شاذّة.
///
/// والمحارف المرفوضة في ويندوز تسعة، وكلّها تُبدَّل بشرطةٍ عادية لا
/// تُحذَف — فيبقى «27-11» مقروءاً.
String safeFileName(String raw) {
  var name = raw
      .replaceAll(_forbidden, '-')

      // محارف التحكّم تُطرح: لا تُرى ولا يقبلها نظام ملفات.
      .replaceAll(_control, '')
      .trim();

  // النقطة أو المسافة في آخر الاسم تُحذَف في ويندوز صمتاً، فيلتصق
  // الامتداد بالاسم.
  name = name.replaceAll(_trailingDots, '');

  if (name.isEmpty) name = 'تصدير';

  // السقف ١٢٠ لا ٢٥٥: المسار كلّه محدود والاسم جزءٌ منه — ومجلّدٌ عميق
  // مع اسمٍ طويل يتجاوز الحدّ فيُرفَض الحفظ.
  return name.length <= 120 ? name : name.substring(0, 120);
}

final _forbidden = RegExp(r'[\\/:*?"<>|]');
final _control = RegExp(r'[\x00-\x1F]');
final _trailingDots = RegExp(r'[. ]+$');

/// يحفظ بايتات في ملفٍ يختار المستخدم مكانه.
///
/// يُعيد المسار، أو `null` إن تراجع المستخدم.
///
/// ولا يُكتب في مجلّد التنزيلات مباشرةً: الملف وثيقةٌ يبحث عنها صاحبها
/// لاحقاً، وحفظُها حيث لم يُسأل يجعله يبحث.
Future<String?> saveBytes({
  required Uint8List bytes,
  required String fileName,
  required String extension,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'احفظ الملف',
    fileName: '${safeFileName(fileName)}.$extension',
    type: FileType.custom,
    allowedExtensions: [extension],

    // ── البايتات تُمرَّر لا تُكتب يدوياً ────────────────────────────────
    // على الجوّال لا يُعيد `saveFile` مساراً قابلاً للكتابة أصلاً، وعلى
    // سطح المكتب يكتبها المنتقي بنفسه متى مُرّرت. وكتابتُها بـ`dart:io`
    // تُدخل تفريعاً على المنصّة في مكانٍ لا يحتاجه.
    bytes: bytes,
  );

  return path;
}

/// يُصدّر جدولاً إلى ملف Excel.
Future<String?> exportToExcel<T>({
  required String fileName,
  required String sheetName,
  required List<ExportColumn<T>> columns,
  required List<T> rows,
}) async {
  final sheet = XlsxSheet(
    name: sheetName,
    headers: columns.map((c) => c.header).toList(),
    columnWidths: columns.map((c) => c.width).toList(),
    rows: [
      for (final row in rows)
        [for (final c in columns) XlsxCell.auto(c.value(row))],
    ],
  );

  return saveBytes(
    bytes: buildXlsx([sheet]),
    fileName: fileName,
    extension: 'xlsx',
  );
}

/// سطرٌ في ترويسة الـ PDF — تسميةٌ وقيمة.
typedef PdfFact = ({String label, String value});

/// يبني مستند PDF عربياً كامل الاتجاه، بشعار توريد في ترويسته.
Future<Uint8List> buildTablePdf<T>({
  required String title,
  String? subtitle,
  required List<ExportColumn<T>> columns,
  required List<T> rows,
  List<PdfFact> facts = const [],

  /// سطرُ إجماليٍّ أسفل الجدول — لكل عمودٍ خليّته.
  List<String>? totals,
}) async {
  // خطُّ Cairo من الشبكة كما في فاتورة الطلبية: هو خطّ العلامة، وبلاه
  // تُرسَم العربية مربّعاتٍ فارغة في بعض القارئات.
  final base = await PdfGoogleFonts.cairoRegular();
  final bold = await PdfGoogleFonts.cairoBold();

  final logo = await _loadLogo();

  const brand = PdfColor.fromInt(0xFF042623);
  const brandLight = PdfColor.fromInt(0xFFE2EDEB);
  const rowAlt = PdfColor.fromInt(0xFFF4F7F7);

  final now = DateTime.now();
  final stamp = '${now.year}/${now.month.toString().padLeft(2, '0')}/'
      '${now.day.toString().padLeft(2, '0')}';

  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      // الاتجاه على المستند كلّه لا على كل نصّ: يسري على الجداول
      // والأعمدة فيقع العمود الأول يميناً.
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: base, bold: bold),

      // عريضةٌ حين تكثر الأعمدة: جدولٌ بثمانية أعمدة على A4 طوليّ
      // يقطع كل خليّةٍ سطرين.
      pageFormat: columns.length > 6
          ? PdfPageFormat.a4.landscape
          : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 32),

      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('توريد — $stamp',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.Text('صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ],
      ),

      build: (ctx) => [
        _pdfHeader(
          title: title,
          subtitle: subtitle,
          stamp: stamp,
          logo: logo,
          brand: brand,
        ),

        if (facts.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          _pdfFacts(facts, brandLight, brand),
        ],

        pw.SizedBox(height: 14),
        _pdfTable(
          columns: columns,
          rows: rows,
          totals: totals,
          brand: brand,
          rowAlt: rowAlt,
        ),
      ],
    ),
  );

  return doc.save();
}

/// يُصدّر جدولاً إلى PDF ويفتح حوار الطباعة/الحفظ.
Future<void> exportToPdf<T>({
  required String fileName,
  required String title,
  String? subtitle,
  required List<ExportColumn<T>> columns,
  required List<T> rows,
  List<PdfFact> facts = const [],
  List<String>? totals,
}) async {
  final bytes = await buildTablePdf(
    title: title,
    subtitle: subtitle,
    columns: columns,
    rows: rows,
    facts: facts,
    totals: totals,
  );

  // `sharePdf` لا `saveBytes`: يفتح حوار النظام الذي يطبع ويحفظ ويُرسل
  // معاً — وهي الأفعال الثلاثة التي تُطلَب من تقرير.
  await Printing.sharePdf(
      bytes: bytes, filename: '${safeFileName(fileName)}.pdf');
}

// ─────────────────────────────────────────────────────────────────────

/// شعار توريد — يُقرأ مرّةً ويبقى.
///
/// القراءة من الأصول تُكلّف مئتي كيلوبايت في كل تصدير، والمستخدم قد
/// يُصدّر عشر مرات في الجلسة.
pw.MemoryImage? _logoCache;
bool _logoTried = false;

Future<pw.MemoryImage?> _loadLogo() async {
  if (_logoTried) return _logoCache;
  _logoTried = true;

  try {
    final data = await rootBundle.load('assets/images/logo.png');
    _logoCache = pw.MemoryImage(data.buffer.asUint8List());
  } on Object catch (e) {
    // شعارٌ لم يُقرأ لا يُسقط تقريراً: الجدول هو المقصود، والترويسة
    // تُرسَم باسمها وحده.
    debugPrint('[export] تعذّرت قراءة الشعار: $e');
    _logoCache = null;
  }

  return _logoCache;
}

pw.Widget _pdfHeader({
  required String title,
  required String? subtitle,
  required String stamp,
  required pw.MemoryImage? logo,
  required PdfColor brand,
}) =>
    pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(title,
                      style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: brand)),
                  if (subtitle != null) ...[
                    pw.SizedBox(height: 3),
                    pw.Text(subtitle,
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey700)),
                  ],
                  pw.SizedBox(height: 3),
                  pw.Text('صُدّر في $stamp',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey600)),
                ],
              ),
            ),
            if (logo != null)
              pw.Container(
                width: 58,
                height: 58,
                alignment: pw.Alignment.center,
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              )
            else
              pw.Text('توريد',
                  style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: brand)),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(height: 2, color: brand),
      ],
    );

pw.Widget _pdfFacts(List<PdfFact> facts, PdfColor bg, PdfColor fg) =>
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Wrap(
        spacing: 26,
        runSpacing: 6,
        children: [
          for (final f in facts)
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('${f.label}: ',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700)),
                pw.Text(f.value,
                    style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: fg)),
              ],
            ),
        ],
      ),
    );

pw.Widget _pdfTable<T>({
  required List<ExportColumn<T>> columns,
  required List<T> rows,
  required List<String>? totals,
  required PdfColor brand,
  required PdfColor rowAlt,
}) {
  pw.Widget cell(String text, {bool header = false, bool total = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: header ? 9 : 8.5,
            fontWeight:
                header || total ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: header ? PdfColors.white : PdfColors.black,
          ),
        ),
      );

  // `Table` بأوزانٍ لا `TableHelper`: الأخير يبني من نصوصٍ خام ولا
  // يقبل تلويناً للسطور ولا وزناً للأعمدة.
  final widths = <int, pw.TableColumnWidth>{
    for (var i = 0; i < columns.length; i++)
      i: pw.FlexColumnWidth(columns[i].pdfFlex.toDouble()),
  };

  return pw.Table(
    columnWidths: widths,
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    children: [
      pw.TableRow(
        decoration: pw.BoxDecoration(color: brand),
        children: [for (final c in columns) cell(c.header, header: true)],
      ),
      for (var i = 0; i < rows.length; i++)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isOdd ? rowAlt : PdfColors.white,
          ),
          children: [for (final c in columns) cell(c.render(rows[i]))],
        ),
      if (totals != null)
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFE2EDEB),
          ),
          children: [
            for (var i = 0; i < columns.length; i++)
              cell(i < totals.length ? totals[i] : '', total: true),
          ],
        ),
    ],
  );
}
