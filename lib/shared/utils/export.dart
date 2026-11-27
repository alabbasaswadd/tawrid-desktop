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

  /// عمود ترقيمٍ أوّل — «١، ٢، ٣…».
  bool numbered = true,
}) async {
  final sheet = XlsxSheet(
    name: sheetName,
    headers: [
      if (numbered) _rowNumberHeader,
      ...columns.map((c) => c.header),
    ],
    columnWidths: [
      if (numbered) _rowNumberWidth,
      ...columns.map((c) => c.width),
    ],
    rows: [
      for (var i = 0; i < rows.length; i++)
        [
          // رقماً لا نصّاً: عمودٌ نصّيٌّ في Excel يُرتَّب «١، ١٠، ٢».
          if (numbered) XlsxCell.auto(i + 1),
          for (final c in columns) XlsxCell.auto(c.value(rows[i])),
        ],
    ],
  );

  return saveBytes(
    bytes: buildXlsx([sheet]),
    fileName: fileName,
    extension: 'xlsx',
  );
}

/// رأسُ عمود الترقيم وعرضُه — واحدٌ في Excel وPDF.
///
/// الترقيم في المُصدِّر لا في أعمدة كل شاشة: ستُّ شاشاتٍ تُصدّر، وعمودٌ
/// يُكتب في كلٍّ منها ستُّ نسخٍ تفترق — وواحدةٌ تُنسى. وهو هنا أيضاً
/// يعرف ترتيب الصفّ، وتعريفُ العمود لا يعرف إلا الصفّ نفسه.
const String _rowNumberHeader = '#';
const double _rowNumberWidth = 6;
const int _rowNumberPdfFlex = 1;

/// سطرٌ في ترويسة الـ PDF — تسميةٌ وقيمة.
typedef PdfFact = ({String label, String value});

/// يبني مستند PDF عربياً كامل الاتجاه، بشعار توريد في ترويسته.
Future<Uint8List> buildTablePdf<T>({
  required String title,
  String? subtitle,
  required List<ExportColumn<T>> columns,
  required List<T> rows,
  List<PdfFact> facts = const [],

  /// اسم المستودع المُصدِّر — يُكتب في الترويسة تحت العنوان.
  ///
  /// التقرير يُرسَل إلى صيدليةٍ أو يُطبَع ويُحفَظ، وبلا اسمٍ يقول من
  /// أصدره يصير ورقةَ أسعارٍ بلا صاحب — والشعار شعارُ المنصّة لا
  /// شعارُ المستودع.
  String? issuer,

  /// سطرُ إجماليٍّ أسفل الجدول — لكل عمودٍ خليّته.
  List<String>? totals,

  /// عمود ترقيمٍ أوّل — «١، ٢، ٣…».
  bool numbered = true,
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
      // ── سقفُ الصفحات يُرفَع، وسببُه دقيق ─────────────────────────────
      //
      // `MultiPage` يحرس نفسه من ودجةٍ لا تتقدّم بعدّادٍ يزيد مع كل
      // صفحة ويُصفَّر حين تنتهي الودجة من الفتّ:
      //
      //     if (!span.hasMoreWidgets) { sameCount = 0; _index++; }
      //
      // و`Table.hasMoreWidgets` **ثابتةٌ على true** في الحزمة. فالعدّاد
      // لا يُصفَّر ما دام الجدول يُفَتّ — أي أن جدولاً واحداً لا يملأ
      // أكثر من `maxPages` صفحة مهما كان تقدّمه سليماً. والافتراضي
      // عشرون.
      //
      // فـ«أدويتي» بأربعمئة صنف في ثمانية أعمدة تحتاج اثنتين وعشرين
      // صفحة — تسقط بـTooManyPagesException ورسالتها تقول «أكثر من
      // عشرين صفحة» فتُقرَأ عطباً في الودجة وهي سقفٌ صريح.
      //
      // والألف بعيدةٌ عن أيّ تقريرٍ حقيقي (أربعون ألف صنف)، ومحدودةٌ
      // مع ذلك: الحارس يبقى قائماً لمن يُدخل صفّاً لا يتّسع أصلاً —
      // و`_clipCell` تمنع ذلك من جهته.
      maxPages: 1000,

      // الاتجاه على المستند كلّه لا على كل نصّ: يسري على الجداول
      // والأعمدة فيقع العمود الأول يميناً.
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: base, bold: bold),

      // عريضةٌ حين تكثر الأعمدة: جدولٌ بثمانية أعمدة على A4 طوليّ
      // يقطع كل خليّةٍ سطرين.
      pageFormat: columns.length + (numbered ? 1 : 0) > 6
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
          issuer: issuer,
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
          numbered: numbered,
          brand: brand,
          rowAlt: rowAlt,
        ),
      ],
    ),
  );

  return doc.save();
}

/// يُصدّر جدولاً إلى PDF ويحفظه حيث يختار المستخدم.
///
/// يُعيد المسار، أو `null` إن تراجع.
///
/// ── لماذا حوارُ حفظٍ لا حوارُ مشاركة؟ ─────────────────────────────────
/// كان يُنادي `Printing.sharePdf`، وهو يفتح حوار النظام الذي يطبع
/// ويُرسل — ويحفظ عبر «طباعة إلى PDF» لا بحفظٍ مباشر. فمن أراد ملفاً
/// في مجلّدٍ يعرفه كان عليه أن يمرّ بالطابعة، ولا يُقال له أين ذهب.
///
/// والـExcel يحفظ بحوارٍ يختار فيه المكان ويُعيد المسار، فافترقت
/// الصيغتان في فعلٍ واحد. وهذا يُوحّدهما. والطباعة لم تضع: لها بندٌ
/// خاصّ في القائمة ينادي [printPdf].
Future<String?> exportToPdf<T>({
  required String fileName,
  required String title,
  String? subtitle,
  String? issuer,
  required List<ExportColumn<T>> columns,
  required List<T> rows,
  List<PdfFact> facts = const [],
  List<String>? totals,
  bool numbered = true,
}) async {
  final bytes = await buildTablePdf(
    title: title,
    subtitle: subtitle,
    issuer: issuer,
    columns: columns,
    rows: rows,
    facts: facts,
    totals: totals,
    numbered: numbered,
  );

  return saveBytes(bytes: bytes, fileName: fileName, extension: 'pdf');
}

/// يبني التقرير ويفتح حوار الطباعة/المشاركة في النظام.
///
/// فعلٌ آخر لا بديلٌ عن [exportToPdf]: من يريد ورقةً مطبوعة لا يريد
/// ملفاً على قرصه، ومن يريد الملف لا يريد المرور بالطابعة.
Future<void> printPdf<T>({
  required String fileName,
  required String title,
  String? subtitle,
  String? issuer,
  required List<ExportColumn<T>> columns,
  required List<T> rows,
  List<PdfFact> facts = const [],
  List<String>? totals,
  bool numbered = true,
}) async {
  final bytes = await buildTablePdf(
    title: title,
    subtitle: subtitle,
    issuer: issuer,
    columns: columns,
    rows: rows,
    facts: facts,
    totals: totals,
    numbered: numbered,
  );

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
  required String? issuer,
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
                  // ── اسم المستودع تحت العنوان ────────────────────
                  // أبرز من التاريخ وأخفت من العنوان: التقرير يُرسَل
                  // إلى صيدلية أو يُطبَع ويُحفظ، وأول سؤالٍ عنه «من
                  // أصدره؟» — والشعار شعارُ المنصّة لا شعارُ المستودع.
                  if (issuer != null && issuer.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(issuer.trim(),
                        style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey800)),
                  ],
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

/// سقفُ نصّ الخليّة الواحدة في جدول PDF.
///
/// ── لماذا سقفٌ أصلاً؟ ──────────────────────────────────────────────────
/// لأن `MultiPage` لا يفتّ صفّ جدولٍ بين صفحتين — يفتّ بين الصفوف لا
/// داخلها. فخليّةٌ نصُّها أطول من صفحة تُنتج صفّاً لا يتّسع في أي
/// صفحة، فيدور المولّد بلا تقدّم حتى يرمي:
///
///     TooManyPagesException: This widget created more than 20 pages
///
/// والرسالة تقول «عشرون صفحة» فيُظنّ السقفُ عدداً يُرفَع — وهو في
/// الحقيقة عدّادُ صفحاتٍ متتاليةٍ **بلا تقدّم**، أي حارسُ دورانٍ لا
/// حارسُ حجم. فرفعُه يُطيل الدوران ولا يُنهيه.
///
/// ووقع ذلك على تصدير العروض: عمود «المناطق» يضمّ مناطق العرض كلّها
/// في خليّةٍ واحدة، ومستودعٌ يخدم عشرين مدينةً يُخرج خليّةً تفيض عن
/// الصفحة — فيسقط التصدير كلّه من أجل عرضٍ واحد.
///
/// ── ولماذا هنا لا في كل شاشة؟ ─────────────────────────────────────────
/// لأن الحارس يجب أن يكون في المُصدِّر: ستُّ شاشاتٍ تُصدّر، وأيُّ حقلٍ
/// يُضاف غداً قد يطول. وقطعُه هنا يجعل التصدير لا يسقط أبداً مهما
/// جاءه من نصّ.
///
/// والمئتان سخيّة: خليّةُ جدولٍ أطول منها لا تُقرأ في جدولٍ أصلاً —
/// والقيمة الكاملة تبقى في Excel، فلا يضيع شيء.
const int _maxCellChars = 200;

String _clipCell(String text) =>
    text.length <= _maxCellChars ? text : '${text.substring(0, _maxCellChars)}…';

pw.Widget _pdfTable<T>({
  required List<ExportColumn<T>> columns,
  required List<T> rows,
  required List<String>? totals,
  required bool numbered,
  required PdfColor brand,
  required PdfColor rowAlt,
}) {
  pw.Widget cell(String text, {bool header = false, bool total = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: pw.Text(
          _clipCell(text),
          style: pw.TextStyle(
            fontSize: header ? 9 : 8.5,
            fontWeight:
                header || total ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: header ? PdfColors.white : PdfColors.black,
          ),
        ),
      );

  // ── الأعمدة تُقلَب لترتسم من اليمين ────────────────────────────────
  // `pw.Table` لا يرث `textDirection` من الصفحة: يرصف خلاياه من اليسار
  // مهما كان اتجاه المستند. فكان العمود الأول (الصنف) يقع أقصى اليسار،
  // ويبدأ القارئ العربي من آخر الأعمدة — «الحالة» قبل أن يعرف الصنف.
  //
  // والقلب هنا لا في `columns`: هي مشتركةٌ مع تصدير Excel، وترتيبها
  // الطبيعي (الأول = بداية القراءة) هو الصحيح هناك وفي كل نداء.
  final ordered = columns.reversed.toList();

  // عمودُ الترقيم آخرَ الخلايا بعد القلب — أي أقصى اليمين، حيث تبدأ
  // القراءة. وهو موضعُ «التسلسل» في كل جدولٍ عربيّ مطبوع.

  // `Table` بأوزانٍ لا `TableHelper`: الأخير يبني من نصوصٍ خام ولا
  // يقبل تلويناً للسطور ولا وزناً للأعمدة.
  final widths = <int, pw.TableColumnWidth>{
    for (var i = 0; i < ordered.length; i++)
      i: pw.FlexColumnWidth(ordered[i].pdfFlex.toDouble()),
    if (numbered)
      ordered.length: const pw.FlexColumnWidth(_rowNumberPdfFlex * 1.0),
  };

  /// خليّة الإجمالي لعمودٍ بعد القلب — `totals` تتبع ترتيب `columns`.
  String totalAt(int reversedIndex) {
    if (totals == null) return '';
    final original = columns.length - 1 - reversedIndex;
    return original < totals.length ? totals[original] : '';
  }

  return pw.Table(
    columnWidths: widths,
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    children: [
      pw.TableRow(
        decoration: pw.BoxDecoration(color: brand),
        children: [
          for (final c in ordered) cell(c.header, header: true),
          if (numbered) cell(_rowNumberHeader, header: true),
        ],
      ),
      for (var i = 0; i < rows.length; i++)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isOdd ? rowAlt : PdfColors.white,
          ),
          children: [
            for (final c in ordered) cell(c.render(rows[i])),
            if (numbered) cell('${i + 1}'),
          ],
        ),
      if (totals != null)
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFE2EDEB),
          ),
          children: [
            for (var i = 0; i < ordered.length; i++)
              cell(totalAt(i), total: true),
            // خليّةٌ فارغة تحت الترقيم: مجموعُ أرقام التسلسل لا معنى له.
            if (numbered) cell('', total: true),
          ],
        ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────
// أدواتٌ لجداول PDF المبنيّة بـ`TableHelper` خارج هذا الملف (الفواتير).
//
// `pw.Table` — وهو ما يبنيه `TableHelper` — لا يرث اتجاه الصفحة، فيرصف
// خلاياه من اليسار دائماً. فجدولٌ رؤوسه «التسلسل · الصنف · السعر» يبدأ
// من اليسار، والقارئ العربي يبدأ من آخره.
//
// والعلاج قلبُ الصفوف والأوزان معاً عند البناء — ولو قُلب أحدهما وحده
// لوقع وزنُ «الصنف» العريض على عمود «التسلسل» الضيّق.
// ─────────────────────────────────────────────────────────────────────

/// صفُّ جدول PDF مقلوباً ليُرسَم من اليمين.
///
/// يُطبَّق على الرؤوس وعلى كل صفّ بيانات — بالترتيب نفسه، وإلا اختلف
/// عمودٌ عن رأسه.
List<T> pdfRtlRow<T>(List<T> cells) => cells.reversed.toList();

/// أوزانُ الأعمدة مقلوبةً لتتبع [pdfRtlRow].
///
/// [count] عدد الأعمدة، و[widths] بمفاتيحها الأصلية (قبل القلب).
Map<int, pw.TableColumnWidth> pdfRtlWidths(
  int count,
  Map<int, pw.TableColumnWidth> widths,
) =>
    {
      for (var i = 0; i < count; i++) i: ?widths[count - 1 - i],
    };
