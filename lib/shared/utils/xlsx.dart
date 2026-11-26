/// توليد ملف Excel حقيقي (.xlsx) بلا حزمةٍ خارجية.
///
/// ── لماذا يدوياً؟ ──────────────────────────────────────────────────────
/// حزمة `excel` تتعارض مع `pdf` على نسخة `image`، وحلُّ التعارض يعني
/// تثبيت إحداهما على نسخةٍ قديمة — وكلتاهما تُصدّر للمستخدم.
///
/// و CSV كان البديل الأسهل، لكنه يخذل العربية: Excel يفتحه بترميز
/// النظام فتصير الأسماء رموزاً، ولا يحمل عرض عمودٍ ولا اتجاه ورقة.
/// والـ xlsx صيغةٌ مفتوحة: ZIP فيه بضعة ملفات XML، وما يلزم منها للجدول
/// البسيط أربعة.
///
/// ── الاتجاه ────────────────────────────────────────────────────────────
/// الورقة تُفتَح من اليمين (`rightToLeft`)، فالعمود الأول يقع يميناً كما
/// يتوقّعه قارئ عربي — وبلا ذلك يُقلَب الجدول كلّه.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';



/// قيمةُ خليّة: نصٌّ أو رقم.
///
/// التمييز لازم: الرقم المكتوب نصّاً لا يُجمَع ولا يُرتَّب في Excel،
/// وعمودُ أسعارٍ لا يُجمَع نصفُ فائدة الجدول.
sealed class XlsxCell {
  const XlsxCell();

  factory XlsxCell.text(String value) = XlsxText;
  factory XlsxCell.number(num value) = XlsxNumber;

  /// يختار النوع بنفسه — للقيم التي قد تكون فارغة.
  static XlsxCell auto(Object? value) => switch (value) {
        null => const XlsxText(''),
        num n => XlsxNumber(n),
        _ => XlsxText('$value'),
      };
}

class XlsxText extends XlsxCell {
  const XlsxText(this.value);
  final String value;
}

class XlsxNumber extends XlsxCell {
  const XlsxNumber(this.value);
  final num value;
}

/// ورقةٌ واحدة: اسمٌ وترويسةٌ وصفوف.
class XlsxSheet {
  const XlsxSheet({
    required this.name,
    required this.headers,
    required this.rows,
    this.columnWidths = const [],
  });

  /// اسم التبويب. Excel يرفض محارف `[]:*?/\` ويقصّ ما جاوز ٣١ محرفاً —
  /// يُنظَّف عند البناء لا يُترك ليُفسد الملف.
  final String name;

  final List<String> headers;
  final List<List<XlsxCell>> rows;

  /// عرض كل عمود بوحدة Excel (نحو ٧ بكسل للوحدة). فارغٌ = افتراضي.
  final List<double> columnWidths;
}

/// يبني ملف xlsx من ورقةٍ أو أكثر.
Uint8List buildXlsx(List<XlsxSheet> sheets) {
  if (sheets.isEmpty) {
    throw ArgumentError('لا ورقة في الملف');
  }

  final archive = Archive();

  void add(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add('[Content_Types].xml', _contentTypes(sheets.length));
  add('_rels/.rels', _rootRels);
  add('xl/workbook.xml', _workbook(sheets));
  add('xl/_rels/workbook.xml.rels', _workbookRels(sheets.length));
  add('xl/styles.xml', _styles);

  for (var i = 0; i < sheets.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', _sheet(sheets[i]));
  }

  // بلا ضغط: الملفات نصّية صغيرة، والضغط يُضيف زمناً لا يُحسّ به المستخدم
  // ويُدخل احتمال عطبٍ في مكانٍ لا نملك تشخيصه.
  final zip = ZipEncoder().encode(archive);
  return Uint8List.fromList(zip);
}

// ─────────────────────────────────────────────────────────────────────

String _escape(String s) {
  final buf = StringBuffer();
  for (final ch in s.runes) {
    // Excel يرفض محارف التحكّم ويُعلن الملف تالفاً — تُطرح بلا ضجّة.
    if (ch < 0x20 && ch != 0x09 && ch != 0x0A && ch != 0x0D) continue;

    switch (ch) {
      case 0x26:
        buf.write('&amp;');
      case 0x3C:
        buf.write('&lt;');
      case 0x3E:
        buf.write('&gt;');
      case 0x22:
        buf.write('&quot;');
      case 0x27:
        buf.write('&apos;');
      default:
        buf.writeCharCode(ch);
    }
  }
  return buf.toString();
}

/// اسم تبويبٍ يقبله Excel.
String _sheetName(String raw, int index) {
  var name = raw.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  if (name.isEmpty) name = 'ورقة $index';
  return name.length <= 31 ? name : name.substring(0, 31);
}

/// مرجع الخليّة بحروف أعمدة Excel — A ثم Z ثم AA.
String _ref(int col, int row) {
  var n = col;
  final letters = StringBuffer();
  do {
    letters.write(String.fromCharCode(65 + n % 26));
    n = n ~/ 26 - 1;
  } while (n >= 0);

  return '${letters.toString().split('').reversed.join()}${row + 1}';
}

String _sheet(XlsxSheet sheet) {
  final buf = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main">')
    // ── الورقة تُفتَح من اليمين ──────────────────────────────────────
    // قارئٌ عربي يتوقّع العمود الأول يميناً، وبلا هذا يُقلَب الجدول.
    ..write('<sheetViews><sheetView rightToLeft="1" workbookViewId="0"/>'
        '</sheetViews>');

  if (sheet.columnWidths.isNotEmpty) {
    buf.write('<cols>');
    for (var i = 0; i < sheet.columnWidths.length; i++) {
      // بلا كسرٍ لاحق: `30.0` مقبولة لكنها ضجيج، و Excel يكتبها `30`.
      final w = sheet.columnWidths[i];
      final width = w == w.roundToDouble()
          ? w.toStringAsFixed(0)
          : w.toStringAsFixed(2);

      buf.write('<col min="${i + 1}" max="${i + 1}" '
          'width="$width" customWidth="1"/>');
    }
    buf.write('</cols>');
  }

  buf.write('<sheetData>');

  // الترويسة بنمطٍ عريض (s="1") — تُميَّز بالنظر وتُجمَّد في Excel.
  buf.write('<row r="1">');
  for (var c = 0; c < sheet.headers.length; c++) {
    buf.write('<c r="${_ref(c, 0)}" t="inlineStr" s="1">'
        '<is><t>${_escape(sheet.headers[c])}</t></is></c>');
  }
  buf.write('</row>');

  for (var r = 0; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    buf.write('<row r="${r + 2}">');
    for (var c = 0; c < row.length; c++) {
      final ref = _ref(c, r + 1);
      switch (row[c]) {
        case XlsxNumber(:final value):
          buf.write('<c r="$ref"><v>$value</v></c>');
        case XlsxText(:final value):
          // `inlineStr` لا جدول نصوصٍ مشترك: الجدول المشترك يُوفّر حجماً
          // في ملفاتٍ بآلاف التكرارات، ويُضيف ملفاً رابعاً وفهرسةً
          // تُخطئ بسهولة. وملفاتنا مئاتُ أسطر.
          buf.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">'
              '${_escape(value)}</t></is></c>');
      }
    }
    buf.write('</row>');
  }

  buf.write('</sheetData></worksheet>');
  return buf.toString();
}

String _contentTypes(int sheetCount) {
  final buf = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
        'content-types">')
    ..write('<Default Extension="rels" ContentType="application/'
        'vnd.openxmlformats-package.relationships+xml"/>')
    ..write('<Default Extension="xml" ContentType="application/xml"/>')
    ..write('<Override PartName="/xl/workbook.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
    ..write('<Override PartName="/xl/styles.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');

  for (var i = 1; i <= sheetCount; i++) {
    buf.write('<Override PartName="/xl/worksheets/sheet$i.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.'
        'spreadsheetml.worksheet+xml"/>');
  }

  buf.write('</Types>');
  return buf.toString();
}

const _rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

String _workbook(List<XlsxSheet> sheets) {
  final buf = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<workbook xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/'
        'officeDocument/2006/relationships"><sheets>');

  for (var i = 0; i < sheets.length; i++) {
    buf.write('<sheet name="${_escape(_sheetName(sheets[i].name, i + 1))}" '
        'sheetId="${i + 1}" r:id="rId${i + 1}"/>');
  }

  buf.write('</sheets></workbook>');
  return buf.toString();
}

String _workbookRels(int sheetCount) {
  final buf = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/'
        '2006/relationships">');

  for (var i = 1; i <= sheetCount; i++) {
    buf.write('<Relationship Id="rId$i" Type="http://schemas.openxmlformats.'
        'org/officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet$i.xml"/>');
  }

  // الأنماط آخر معرّف — بعد الأوراق كلها.
  buf.write('<Relationship Id="rId${sheetCount + 1}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships/styles" Target="styles.xml"/>');

  buf.write('</Relationships>');
  return buf.toString();
}

/// نمطان لا أكثر: عاديّ (٠) وعريضٌ للترويسة (١).
const _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<fonts count="2">'
    '<font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font>'
    '</fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/>'
    '</border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" '
    'borderId="0"/></cellStyleXfs>'
    '<cellXfs count="2">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" '
    'applyFont="1"/>'
    '</cellXfs>'
    '</styleSheet>';
