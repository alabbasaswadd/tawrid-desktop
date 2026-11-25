// نماذج استيراد المخزون بالـ AI — مطابقة لعقد
// `tawrid-api/warehouse/medicines/import` في الباكند.
//
// التحليل كلّه في الخادم: الملف يُرفع، والخادم يقرؤه وينادي الوكيل ويطابق
// مع الكتالوج ويبثّ تقدّمه. فلا قارئ Excel هنا ولا مفتاح وكيل في الجهاز.

/// مرحلة المهمة — أرقامها هي `InventoryImportStatusEnum` في الخادم.
enum ImportStatus {
  pending(1),
  analyzing(2),
  matching(3),
  ready(4),
  applying(5),
  applied(6),
  failed(7),

  /// أوقفها صاحبها — حالةٌ مستقلّة عن [failed] عمداً: الفشل عطلٌ يستحق
  /// رسالةً، والإلغاء قرارٌ لا خطأ فيه.
  cancelled(8);

  const ImportStatus(this.code);
  final int code;

  static ImportStatus fromCode(int? code) =>
      ImportStatus.values.firstWhere(
        (s) => s.code == code,
        orElse: () => ImportStatus.pending,
      );

  bool get isRunning =>
      this == ImportStatus.pending ||
      this == ImportStatus.analyzing ||
      this == ImportStatus.matching;

  bool get isDone => this == ImportStatus.applied;
}

/// نتيجة مطابقة صفّ مع الكتالوج — `InventoryImportMatchEnum`.
enum ImportMatch {
  matched(1),
  ambiguous(2),
  notFound(3),
  owned(4);

  const ImportMatch(this.code);
  final int code;

  static ImportMatch fromCode(int? code) => ImportMatch.values.firstWhere(
        (m) => m.code == code,
        orElse: () => ImportMatch.notFound,
      );
}

/// ما حدث للصفّ عند التطبيق — `InventoryImportOutcomeEnum`.
enum ImportOutcome {
  pending(0),
  added(1),
  repriced(2),
  skipped(3),
  failed(4);

  const ImportOutcome(this.code);
  final int code;

  static ImportOutcome fromCode(int? code) => ImportOutcome.values.firstWhere(
        (o) => o.code == code,
        orElse: () => ImportOutcome.pending,
      );
}

/// جواب الرفع — يعود فوراً قبل أن يبدأ الوكيل.
class ImportStarted {
  const ImportStarted({
    required this.jobId,
    required this.fileName,
    required this.totalRows,
    required this.status,
  });

  final String jobId;
  final String fileName;
  final int totalRows;
  final ImportStatus status;

  factory ImportStarted.fromJson(Map<String, dynamic> j) => ImportStarted(
        jobId: j['jobId'] as String,
        fileName: j['fileName'] as String? ?? '',
        totalRows: (j['totalRows'] as num?)?.toInt() ?? 0,
        status: ImportStatus.fromCode((j['status'] as num?)?.toInt()),
      );
}

/// مرشّح من الكتالوج.
class ImportCandidate {
  const ImportCandidate({
    required this.catalogItemId,
    required this.displayName,
    this.sakoCode = '',
    this.strength = 0,
    this.manufacturerName = '',
    this.pricePublic = 0,
  });

  final String catalogItemId;
  final String displayName;
  final String sakoCode;
  final double strength;
  final String manufacturerName;
  final double pricePublic;

  factory ImportCandidate.fromJson(Map<String, dynamic> j) => ImportCandidate(
        catalogItemId: j['catalogItemId'] as String,
        displayName: j['displayName'] as String? ?? '',
        sakoCode: j['sakoCode'] as String? ?? '',
        strength: (j['strength'] as num?)?.toDouble() ?? 0,
        manufacturerName: j['manufacturerName'] as String? ?? '',
        pricePublic: (j['pricePublic'] as num?)?.toDouble() ?? 0,
      );
}

/// صفّ كما يُراجعه المستخدم.
class ImportRow {
  const ImportRow({
    required this.id,
    required this.rowNumber,
    required this.name,
    required this.matchStatus,
    required this.selected,
    this.rawCells = '',
    this.strength,
    this.form,
    this.manufacturer,
    this.quantity,
    this.price,
    this.confidence = 1,
    this.note,
    this.matched,
    this.candidates = const [],
    this.previousPrice,
    this.outcome = ImportOutcome.pending,
    this.outcomeMessage,
  });

  final String id;
  final int rowNumber;

  /// الخلايا كما وردت في الملف — تُعرض حين تفشل المطابقة فيفهم المستخدم لماذا.
  final String rawCells;

  final String name;
  final double? strength;
  final String? form;
  final String? manufacturer;
  final int? quantity;
  final double? price;
  final double confidence;
  final String? note;

  final ImportMatch matchStatus;
  final bool selected;
  final ImportCandidate? matched;
  final List<ImportCandidate> candidates;

  /// السعر الحالي في «أدويتي» حين يكون الصنف مملوكاً.
  final double? previousPrice;

  final ImportOutcome outcome;
  final String? outcomeMessage;

  /// هل فيه قرارٌ يُتَّخذ؟ غير الموجود لا يمكن استيراده أصلاً.
  bool get isActionable =>
      matchStatus != ImportMatch.notFound && matched != null;

  factory ImportRow.fromJson(Map<String, dynamic> j) => ImportRow(
        id: j['id'] as String,
        rowNumber: (j['rowNumber'] as num?)?.toInt() ?? 0,
        rawCells: j['rawCells'] as String? ?? '',
        name: j['name'] as String? ?? '',
        strength: (j['strength'] as num?)?.toDouble(),
        form: _str(j['form']),
        manufacturer: _str(j['manufacturer']),
        quantity: (j['quantity'] as num?)?.toInt(),
        price: (j['price'] as num?)?.toDouble(),
        confidence: (j['confidence'] as num?)?.toDouble() ?? 1,
        note: _str(j['note']),
        matchStatus: ImportMatch.fromCode((j['matchStatus'] as num?)?.toInt()),
        selected: j['selected'] as bool? ?? false,
        matched: j['matched'] is Map<String, dynamic>
            ? ImportCandidate.fromJson(j['matched'] as Map<String, dynamic>)
            : null,
        candidates: ((j['candidates'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ImportCandidate.fromJson)
            .toList(),
        previousPrice: (j['previousPrice'] as num?)?.toDouble(),
        outcome: ImportOutcome.fromCode((j['outcome'] as num?)?.toInt()),
        outcomeMessage: _str(j['outcomeMessage']),
      );

  ImportRow copyWith({
    bool? selected,
    double? price,
    ImportCandidate? matched,
    ImportMatch? matchStatus,
  }) =>
      ImportRow(
        id: id,
        rowNumber: rowNumber,
        rawCells: rawCells,
        name: name,
        strength: strength,
        form: form,
        manufacturer: manufacturer,
        quantity: quantity,
        price: price ?? this.price,
        confidence: confidence,
        note: note,
        matchStatus: matchStatus ?? this.matchStatus,
        selected: selected ?? this.selected,
        matched: matched ?? this.matched,
        candidates: candidates,
        previousPrice: previousPrice,
        outcome: outcome,
        outcomeMessage: outcomeMessage,
      );
}

/// ملخّص الوكيل للملف.
class ImportSummary {
  const ImportSummary({
    this.text = '',
    this.columns = const [],
    this.warnings = const [],
  });

  final String text;

  /// الأعمدة كما فسّرها الوكيل — خطؤها يفسد كل الصفوف، فتُعرض أولاً.
  final List<String> columns;

  final List<String> warnings;

  factory ImportSummary.fromJson(Map<String, dynamic>? j) => ImportSummary(
        text: j?['text'] as String? ?? '',
        columns: _strList(j?['columns']),
        warnings: _strList(j?['warnings']),
      );
}

/// عدّادات المراجعة — يحسبها الخادم فلا يُعيد كل عميل حسابها.
class ImportCounts {
  const ImportCounts({
    this.total = 0,
    this.newItems = 0,
    this.priceUpdate = 0,
    this.needsConfirm = 0,
    this.notFound = 0,
  });

  final int total;
  final int newItems;
  final int priceUpdate;
  final int needsConfirm;
  final int notFound;

  factory ImportCounts.fromJson(Map<String, dynamic>? j) => ImportCounts(
        total: (j?['total'] as num?)?.toInt() ?? 0,
        newItems: (j?['new'] as num?)?.toInt() ?? 0,
        priceUpdate: (j?['priceUpdate'] as num?)?.toInt() ?? 0,
        needsConfirm: (j?['needsConfirm'] as num?)?.toInt() ?? 0,
        notFound: (j?['notFound'] as num?)?.toInt() ?? 0,
      );
}

/// حالة المهمة الكاملة: التقدّم أثناء التنفيذ، وصفوف المراجعة عند الجهوزية.
class ImportJob {
  const ImportJob({
    required this.jobId,
    required this.fileName,
    required this.status,
    required this.totalRows,
    this.analyzedRows = 0,
    this.matchedRows = 0,
    this.progress = 0,
    this.activity,
    this.failureMessage,
    this.summary = const ImportSummary(),
    this.counts = const ImportCounts(),
    this.rows = const [],
    this.createdOn,
  });

  final String jobId;
  final String fileName;
  final ImportStatus status;
  final int totalRows;
  final int analyzedRows;
  final int matchedRows;

  /// نسبة الإنجاز (٠..١) — يحسبها الخادم لأنه يعرف أوزان المراحل.
  final double progress;

  final String? activity;
  final String? failureMessage;

  final ImportSummary summary;
  final ImportCounts counts;
  final List<ImportRow> rows;

  /// وقت إنشاء المهمة في الخادم — أساس عدّاد «كم مضى».
  ///
  /// لازمٌ لا زينة: ملفٌ بسبعمئة صف يُقسَّم دفعاتٍ كثيرة لكل منها نداء
  /// وكيل، فيبقى التقدّم ثابتاً دقائق. وبلا عدّادٍ يرى المستخدم شاشةً
  /// ساكنة فيظنّها معلّقة ويعيد الرفع — فتتراكم مهامٌ متوازية بلا داعٍ.
  final DateTime? createdOn;

  factory ImportJob.fromJson(Map<String, dynamic> j) => ImportJob(
        jobId: j['jobId'] as String,
        fileName: j['fileName'] as String? ?? '',
        status: ImportStatus.fromCode((j['status'] as num?)?.toInt()),
        totalRows: (j['totalRows'] as num?)?.toInt() ?? 0,
        analyzedRows: (j['analyzedRows'] as num?)?.toInt() ?? 0,
        matchedRows: (j['matchedRows'] as num?)?.toInt() ?? 0,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        activity: _str(j['activity']),
        failureMessage: _str(j['failureMessage']),
        summary: ImportSummary.fromJson(j['summary'] as Map<String, dynamic>?),
        counts: ImportCounts.fromJson(j['counts'] as Map<String, dynamic>?),
        rows: ((j['rows'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ImportRow.fromJson)
            .toList(),
        createdOn: DateTime.tryParse(j['createdOn'] as String? ?? '')?.toLocal(),
      );

  /// كم مضى على المهمة — يُحسب من وقت الخادم لا من فتح الشاشة، فيبقى
  /// صحيحاً عند استئناف مهمةٍ بدأت قبل إغلاق التطبيق.
  Duration? get elapsed {
    final start = createdOn;
    return start == null ? null : DateTime.now().difference(start);
  }

  ImportJob copyWith({List<ImportRow>? rows}) => ImportJob(
        jobId: jobId,
        fileName: fileName,
        status: status,
        totalRows: totalRows,
        analyzedRows: analyzedRows,
        matchedRows: matchedRows,
        progress: progress,
        activity: activity,
        failureMessage: failureMessage,
        summary: summary,
        counts: counts,
        rows: rows ?? this.rows,
        createdOn: createdOn,
      );
}

/// سطر في التقرير النهائي — ما أُضيف أو ما تغيّر سعره.
class ImportAppliedItem {
  const ImportAppliedItem({
    required this.rowNumber,
    required this.displayName,
    this.strength = 0,
    this.manufacturerName = '',
    this.price,
    this.previousPrice,
  });

  final int rowNumber;
  final String displayName;
  final double strength;
  final String manufacturerName;
  final double? price;

  /// السعر قبل التعديل — للمُعدَّل وحده، فيكون التغيير مفهوماً.
  final double? previousPrice;

  factory ImportAppliedItem.fromJson(Map<String, dynamic> j) =>
      ImportAppliedItem(
        rowNumber: (j['rowNumber'] as num?)?.toInt() ?? 0,
        displayName: j['displayName'] as String? ?? '',
        strength: (j['strength'] as num?)?.toDouble() ?? 0,
        manufacturerName: j['manufacturerName'] as String? ?? '',
        price: (j['price'] as num?)?.toDouble(),
        previousPrice: (j['previousPrice'] as num?)?.toDouble(),
      );
}

/// سطر تعذّر.
class ImportFailure {
  const ImportFailure({
    required this.rowNumber,
    required this.name,
    required this.message,
  });

  final int rowNumber;
  final String name;
  final String message;

  factory ImportFailure.fromJson(Map<String, dynamic> j) => ImportFailure(
        rowNumber: (j['rowNumber'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        message: j['message'] as String? ?? '',
      );
}

/// تقرير التطبيق: ماذا أُضيف وماذا عُدِّل وماذا تعذّر.
class ImportReport {
  const ImportReport({
    required this.jobId,
    this.added = const [],
    this.modified = const [],
    this.failed = const [],
    this.skippedCount = 0,
  });

  final String jobId;
  final List<ImportAppliedItem> added;
  final List<ImportAppliedItem> modified;
  final List<ImportFailure> failed;
  final int skippedCount;

  int get total => added.length + modified.length;
  bool get hasFailures => failed.isNotEmpty;

  factory ImportReport.fromJson(Map<String, dynamic> j) => ImportReport(
        jobId: j['jobId'] as String,
        added: _items(j['added']),
        modified: _items(j['modified']),
        failed: ((j['failed'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ImportFailure.fromJson)
            .toList(),
        skippedCount: (j['skippedCount'] as num?)?.toInt() ?? 0,
      );

  static List<ImportAppliedItem> _items(dynamic value) =>
      ((value as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ImportAppliedItem.fromJson)
          .toList();
}

/// تقدّم وصل عبر القناة الفورية.
class ImportProgressEvent {
  const ImportProgressEvent({
    required this.jobId,
    required this.phase,
    required this.done,
    required this.total,
    required this.activity,
  });

  final String jobId;
  final ImportStatus phase;
  final int done;
  final int total;
  final String activity;

  factory ImportProgressEvent.fromJson(Map<String, dynamic> j) =>
      ImportProgressEvent(
        jobId: j['jobId'] as String? ?? '',
        phase: ImportStatus.fromCode((j['phase'] as num?)?.toInt()),
        done: (j['done'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        activity: j['activity'] as String? ?? '',
      );
}

String? _str(dynamic v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

List<String> _strList(dynamic v) {
  if (v is! List) return const [];
  return v
      .whereType<String>()
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}
