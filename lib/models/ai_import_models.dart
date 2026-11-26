import 'package:tawrid_app/models/sales_offer_models.dart';

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
    this.company,
    this.unit,
    this.discountPercentage,
    this.bonusBuyQuantity,
    this.bonusFreeQuantity,
    this.expiryDate,
    this.isOfferItem = false,
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

  // ── الشقّ التجاري — ما يجعل الصفّ بند عرضٍ لا مجرّد سطر مخزون ────────
  /// الشركة المصنّعة أو المورّدة — أساس تجميع بنود العرض الواحد.
  final String? company;

  final String? unit;
  final double? discountPercentage;

  /// «اشترِ [bonusBuyQuantity] فتأخذ [bonusFreeQuantity] مجاناً».
  final double? bonusBuyQuantity;
  final double? bonusFreeQuantity;

  final DateTime? expiryDate;

  /// هل يحمل الصفّ شرطاً تجارياً؟ يقرّره الخادم من الخصم والبونص.
  final bool isOfferItem;

  /// نصّ البونص للعرض: «١٠+١».
  String? get bonusLabel =>
      bonusBuyQuantity != null && bonusFreeQuantity != null
          ? '${_num(bonusBuyQuantity!)}+${_num(bonusFreeQuantity!)}'
          : null;

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

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
        company: _str(j['company']),
        unit: _str(j['unit']),
        discountPercentage: (j['discountPercentage'] as num?)?.toDouble(),
        bonusBuyQuantity: (j['bonusBuyQuantity'] as num?)?.toDouble(),
        bonusFreeQuantity: (j['bonusFreeQuantity'] as num?)?.toDouble(),
        expiryDate: DateTime.tryParse(j['expiryDate'] as String? ?? '')?.toLocal(),
        isOfferItem: j['isOfferItem'] as bool? ?? false,
      );

  /// [clearPrice] يُفرِّغ السعر صراحةً.
  ///
  /// لازمٌ لأن `price ?? this.price` لا يُفرِّق بين «لا تُغيّره» و«اجعله
  /// فارغاً»، والفارغ معنىً مقصود هنا: سعرٌ يُشتقّ تلقائياً من الكتالوج.
  ImportRow copyWith({
    bool? selected,
    double? price,
    bool clearPrice = false,
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
        price: clearPrice ? null : (price ?? this.price),
        confidence: confidence,
        note: note,
        matchStatus: matchStatus ?? this.matchStatus,
        selected: selected ?? this.selected,
        matched: matched ?? this.matched,
        candidates: candidates,
        previousPrice: previousPrice,
        outcome: outcome,
        outcomeMessage: outcomeMessage,
        company: company,
        unit: unit,
        discountPercentage: discountPercentage,
        bonusBuyQuantity: bonusBuyQuantity,
        bonusFreeQuantity: bonusFreeQuantity,
        expiryDate: expiryDate,
        isOfferItem: isOfferItem,
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

/// ما استهلكه تحليل الملف من وحدات النموذج — إدخالاً وإخراجاً.
///
/// يُعرَض لأن الحصّة المجانية محدودة وصاحب المستودع هو من يدفع ثمن
/// تجاوزها: رقمٌ أمام عينه عند كل ملف يُعلّمه أن ملفاً بألف صف ليس كملفٍ
/// بخمسين. وصفرٌ في الحقلين يعني أن الملف قُرئ من ترويسته مباشرةً بلا
/// نموذج — وهو خبرٌ طيّب لا نقص بيانات.
class ImportUsage {
  const ImportUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.reported = false,
  });

  final int inputTokens;
  final int outputTokens;

  /// هل أرسل الخادم هذا الحقل أصلاً؟
  ///
  /// التمييز لازم ولا يُستغنى عنه بالصفر: خادمٌ قديم لا يعرف الحقل
  /// وخادمٌ حديثٌ قرأ الملف بلا نموذج كلاهما يصل بصفر، والخبر عنهما
  /// مختلف تماماً — «بلا مصروف» عن الأول كذب. فالغياب يُخفي السطر،
  /// والصفر الصريح يُقال.
  final bool reported;

  int get total => inputTokens + outputTokens;

  /// النموذج لم يُستدعَ — والخادم قال ذلك صراحةً.
  bool get isFree => reported && total == 0;

  factory ImportUsage.fromJson(Map<String, dynamic>? j) => ImportUsage(
        inputTokens: (j?['inputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (j?['outputTokens'] as num?)?.toInt() ?? 0,
        reported: j != null,
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
    this.usage = const ImportUsage(),
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
  final ImportUsage usage;
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
        usage: ImportUsage.fromJson(j['usage'] as Map<String, dynamic>?),
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
        usage: usage,
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

/// عرضٌ أُنشئ من بنود شركةٍ في الملف.
class ImportCreatedOffer {
  const ImportCreatedOffer({
    required this.offerId,
    required this.company,
    required this.title,
    required this.itemCount,
  });

  final String offerId;
  final String company;
  final String title;
  final int itemCount;

  factory ImportCreatedOffer.fromJson(Map<String, dynamic> j) =>
      ImportCreatedOffer(
        offerId: j['offerId'] as String? ?? '',
        company: j['company'] as String? ?? '',
        title: j['title'] as String? ?? '',
        itemCount: (j['itemCount'] as num?)?.toInt() ?? 0,
      );
}

/// عرضٌ تعذّر إنشاؤه — باسم شركته وسببه.
class ImportOfferFailure {
  const ImportOfferFailure({required this.company, required this.message});

  final String company;
  final String message;

  factory ImportOfferFailure.fromJson(Map<String, dynamic> j) =>
      ImportOfferFailure(
        company: j['company'] as String? ?? '',
        message: j['message'] as String? ?? '',
      );
}

/// ما يُرسَل لإنشاء عرضٍ من بنود شركة.
///
/// الاستهداف والتواريخ تأتي من المستخدم لا من الملف: ملفُّ أسعارٍ لا
/// يحمل مناطقَ ولا مدداً، وهي شرطُ إنشاء العرض في الخادم.
class ImportOfferPlan {
  const ImportOfferPlan({
    required this.company,
    required this.title,
    required this.startsAt,
    required this.targetRegions,
    this.expiresAt,
    this.isPublicInRegion = true,
    this.description,
  });

  final String company;
  final String title;
  final DateTime startsAt;
  final DateTime? expiresAt;
  final bool isPublicInRegion;
  final List<TargetRegion> targetRegions;
  final String? description;

  Map<String, dynamic> toJson() => {
        'company': company,
        'title': title,
        'startsAt': startsAt.toUtc().toIso8601String(),
        if (expiresAt != null)
          'expiresAt': expiresAt!.toUtc().toIso8601String(),
        'isPublicInRegion': isPublicInRegion,
        'targetRegions': targetRegions
            .map((r) => {
                  'governorate': r.governorate,
                  if (r.city != null) 'city': r.city,
                })
            .toList(),
        if (description != null) 'description': description,
      };
}

/// تقرير التطبيق: ماذا أُضيف وماذا عُدِّل وماذا تعذّر.
class ImportReport {
  const ImportReport({
    required this.jobId,
    this.added = const [],
    this.modified = const [],
    this.failed = const [],
    this.skippedCount = 0,
    this.offers = const [],
    this.offerFailures = const [],
  });

  final String jobId;
  final List<ImportAppliedItem> added;
  final List<ImportAppliedItem> modified;
  final List<ImportFailure> failed;
  final int skippedCount;

  /// العروض التي أُنشئت مسوّدةً — واحدٌ لكل شركة أقرّها المستخدم.
  final List<ImportCreatedOffer> offers;

  /// عروضٌ تعذّرت — تُفصَل عن [failed] لأن إجراءها مختلف: تلك أصنافٌ
  /// يُعاد استيرادها، وهذه عروضٌ تُنشأ من شاشة العروض.
  final List<ImportOfferFailure> offerFailures;

  int get total => added.length + modified.length;
  bool get hasFailures => failed.isNotEmpty || offerFailures.isNotEmpty;

  factory ImportReport.fromJson(Map<String, dynamic> j) => ImportReport(
        jobId: j['jobId'] as String,
        added: _items(j['added']),
        modified: _items(j['modified']),
        failed: ((j['failed'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ImportFailure.fromJson)
            .toList(),
        skippedCount: (j['skippedCount'] as num?)?.toInt() ?? 0,
        offers: ((j['offers'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ImportCreatedOffer.fromJson)
            .toList(),
        offerFailures: ((j['offerFailures'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ImportOfferFailure.fromJson)
            .toList(),
      );

  static List<ImportAppliedItem> _items(dynamic value) =>
      ((value as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ImportAppliedItem.fromJson)
          .toList();
}

/// صنفٌ فرغت المزامنة منه — يصل واحداً واحداً أثناء التطبيق.
///
/// بلا هذا كانت المزامنة صندوقاً مغلقاً: المستخدم يضغط «مزامنة» ثم يبقى
/// أمام شاشة المراجعة بلا حراك حتى يظهر التقرير دفعةً واحدة — فلا يعرف
/// أهي تعمل أم تعلّقت، ولا عند أي صنفٍ تعثّرت إن تعثّرت.
class ImportItemEvent {
  const ImportItemEvent({
    required this.jobId,
    required this.rowNumber,
    required this.name,
    required this.outcome,
    required this.done,
    required this.total,
    this.price,
    this.previousPrice,
    this.message,
  });

  final String jobId;
  final int rowNumber;
  final String name;
  final ImportOutcome outcome;

  final double? price;

  /// السعر قبل التعديل — للمُعدَّل وحده.
  final double? previousPrice;

  /// سبب التعذّر إن تعذّر.
  final String? message;

  final int done;
  final int total;

  factory ImportItemEvent.fromJson(Map<String, dynamic> j) => ImportItemEvent(
        jobId: j['jobId'] as String? ?? '',
        rowNumber: (j['rowNumber'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        outcome: ImportOutcome.fromCode((j['outcome'] as num?)?.toInt()),
        price: (j['price'] as num?)?.toDouble(),
        previousPrice: (j['previousPrice'] as num?)?.toDouble(),
        message: _str(j['message']),
        done: (j['done'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
      );
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
