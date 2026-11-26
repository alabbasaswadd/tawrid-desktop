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
    this.sourceLabel,
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

  /// تسمية الصنف كما وردت في الملف — «كورناسيل بلس (6.25/ 2.5) ملغ».
  ///
  /// تُعرَض بدل [name] وحده: الاسم منظَّفٌ من العيار، فثلاثة أصنافٍ
  /// بعياراتٍ مركّبة تظهر ثلاثة أسطرٍ متطابقة لا يُفرَّق بينها — ويُطلَب
  /// من صاحبها أن يُقرّ ما لا يُميّزه.
  final String? sourceLabel;

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

  /// هل يمكن استيراده؟
  ///
  /// نعم ولو لم يُطابِق الكتالوج: المستودع يحمل مكمّلاتٍ ومستحضرات
  /// ومستوردات لا وجود لها في النشرة الوطنية، ومنعُها كان يُخرج ثلث
  /// الملف من مخزون صاحبه. فتُضاف باسمها وعيارها كما قرأهما الوكيل.
  ///
  /// والشرط الباقي أن يكون له اسم: صفٌّ بلا اسمٍ لا شيء فيه يُضاف.
  bool get isActionable => name.isNotEmpty;

  /// صنفٌ حرّ — يُضاف بهويّته لا بمرجعٍ في الكتالوج.
  bool get isCatalogFree => matched == null;

  /// ما يُعرَض للمستخدم — التسمية الأصلية وإلا الاسم المنظَّف.
  String get displayLabel =>
      (sourceLabel != null && sourceLabel!.trim().isNotEmpty)
          ? sourceLabel!.trim()
          : name;

  /// ينقص الصفَّ سعرُه.
  ///
  /// السعر وحده هو الحقل الذي لا افتراض له. الكمية تُقرأ واحداً حين
  /// تغيب، والوحدة «علبة»، والاسم شرطُ الصفّ أصلاً ([isActionable]) —
  /// أمّا السعر فرقمٌ مخترَع فيه يُلزم صاحب المستودع ببيعٍ لم يقصده.
  ///
  /// وهو في المخزون اختياري: صنفٌ بلا سعرٍ يبقى في «أدويتي» بياناً
  /// تعريفياً. لكنّه في بند العرض شرطٌ لا يُتجاوَز.
  bool get needsPrice => (price ?? 0) <= 0;

  /// صالحٌ ليصير بند عرض.
  ///
  /// ما لا يجتازه يبقى في المخزون ولا يدخل العرض. وكان يدخله بسعر صفر
  /// فيُسقط عرض شركته كلّها عند التحقّق — فصار يُطرَح، ويُقال لصاحبه
  /// أنه طُرح ولماذا، بدل أن يختفي صامتاً.
  bool get canBeOfferItem => isOfferItem && isActionable && !needsPrice;

  /// بندُ عرضٍ محدَّدٌ ينقصه سعرُه — ثغرةٌ تُعرَض للمستخدم ليملأها أو
  /// يتجاهلها، لا لتُطوى عنه.
  bool get isOfferGap => isOfferItem && isActionable && selected && needsPrice;

  /// هل في هذا الصفّ ما سيتغيّر فعلاً في «أدويتي»؟
  ///
  /// سؤالُ المزامنة الثانية. استيراد نفس النشرة شهرياً أمرٌ عادي،
  /// وأكثرُ أسعارها لا يتبدّل — فملفٌ بسبعمئة صنفٍ قد لا يحمل جديداً
  /// إلا في عشرين. وبلا تمييزٍ بينهما تُعرَض السبعمئة كلّها على صاحبها
  /// ليبحث بعينه عن العشرين.
  ///
  /// والمملوك بسعرٍ مطابق ليس تغييراً: الخادم يسمه «تُخطّي» ولا يكتب
  /// فيه شيئاً. وغيرُ المطابَق تغييرٌ لأنه سيُضاف صنفاً جديداً.
  bool get willChange {
    if (!isActionable) return false;
    if (matchStatus != ImportMatch.owned) return true;

    // مملوك: التغيير سعرٌ مختلف — ولا سعر في الملف يعني لا تغيير.
    if (price == null) return false;
    return previousPrice == null || (price! - previousPrice!).abs() > 0.0001;
  }

  factory ImportRow.fromJson(Map<String, dynamic> j) => ImportRow(
        id: j['id'] as String,
        rowNumber: (j['rowNumber'] as num?)?.toInt() ?? 0,
        rawCells: j['rawCells'] as String? ?? '',
        sourceLabel: _str(j['sourceLabel']),
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
        sourceLabel: sourceLabel,
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
    this.skipCatalogMatching = false,
  });

  final String jobId;
  final String fileName;
  final ImportStatus status;
  final int totalRows;

  /// رُفع الملف بطلب تخطّي الكتالوج — فكل صفوفه أصنافٌ حرّة.
  ///
  /// تُقرأ في المراجعة لتُقال الحقيقة: «خارج الكتالوج: ٧٦٠» في المسار
  /// العادي خبرُ عطبٍ يستدعي التدقيق، وهنا هو المطلوب نفسه — والعدّاد
  /// وحده لا يفرّق بينهما.
  final bool skipCatalogMatching;
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
        skipCatalogMatching: j['skipCatalogMatching'] as bool? ?? false,
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

  /// من صفٍّ انتهت مزامنته — طريق التقرير حين يُبنى محلياً.
  factory ImportAppliedItem.fromRow(ImportRow row) => ImportAppliedItem(
        rowNumber: row.rowNumber,
        displayName: row.matched?.displayName ?? row.name,
        strength: row.matched?.strength ?? row.strength ?? 0,
        manufacturerName:
            row.matched?.manufacturerName ?? row.manufacturer ?? '',
        price: row.price,
        previousPrice: row.previousPrice,
      );

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

/// حصيلة خطوة إنشاء العروض — ردّ النداء التالي للتطبيق.
///
/// منفصلٌ عن [ImportReport] لأن الخطوتين منفصلتان في الخادم: التطبيق
/// يكتب المخزون ويعود، وهذا يُنادى بعده. وتُدمَج حصيلتُه في التقرير
/// بـ [ImportReport.withOffers] فيُعرَض الاثنان معاً.
class ImportOffersResult {
  const ImportOffersResult({
    this.offers = const [],
    this.failures = const [],
  });

  final List<ImportCreatedOffer> offers;
  final List<ImportOfferFailure> failures;

  factory ImportOffersResult.fromJson(Map<String, dynamic> j) =>
      ImportOffersResult(
        offers: ((j['offers'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ImportCreatedOffer.fromJson)
            .toList(),
        failures: ((j['offerFailures'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ImportOfferFailure.fromJson)
            .toList(),
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
    this.includeAllItems = false,
  });

  final String company;
  final String title;
  final DateTime startsAt;
  final DateTime? expiresAt;
  final bool isPublicInRegion;
  final List<TargetRegion> targetRegions;
  final String? description;

  /// يضمّ كل أصناف الشركة لا حَمَلةَ الخصم والبونص وحدهم.
  ///
  /// «ما هو بند عرض؟» سؤالٌ لا يملك الوكيل جوابه: هو يرى خصماً أو
  /// بونصاً فيعرفه عرضاً — وأكثر ما يصل المستودعات نشرةُ أسعارٍ صرف
  /// بلا علامةٍ يلتقطها. فالقرار لصاحب المستودع: هو وحده يعرف أرفع
  /// نشرةَ أسعارٍ أم جرداً.
  final bool includeAllItems;

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
        if (includeAllItems) 'includeAllItems': true,
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

  /// يدمج حصيلة خطوة العروض في تقرير المخزون.
  ///
  /// الخطوتان منفصلتان في الخادم ويُعرضان معاً: المستخدم زامن ملفاً
  /// واحداً، وتقريران عنه تجزئةٌ لا تعنيه.
  ImportReport withOffers(ImportOffersResult result) => ImportReport(
        jobId: jobId,
        added: added,
        modified: modified,
        failed: failed,
        skippedCount: skippedCount,
        offers: result.offers,
        offerFailures: result.failures,
      );

  /// يُسجّل تعذّر خطوة العروض كلّها — عطلُ طريقٍ لا رفضُ عرضٍ بعينه.
  ///
  /// يُقال ولا يُكتَم: المخزون كُتب والعروض لم تُنشأ، وهي حالةٌ وسطى
  /// يحتاج صاحبها أن يعرفها ليُنشئها من شاشة العروض.
  ImportReport withOfferError(String message) => ImportReport(
        jobId: jobId,
        added: added,
        modified: modified,
        failed: failed,
        skippedCount: skippedCount,
        offerFailures: [
          ImportOfferFailure(company: '', message: message),
        ],
      );

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

  /// تقرير يُبنى من حصيلة الصفوف حين يضيع ردّ التطبيق في الطريق.
  ///
  /// الكتابة تجري في الخادم لا في الطريق إليه: فإن سقط الاتصال بعد أن
  /// تمّت، فالحقيقة كاملةٌ في الصفوف — لكل صفٍّ حصيلتُه وسببُها. وقراءتها
  /// منها أصدق من ترك المستخدم أمام شاشةٍ لا تنتهي عن عملٍ قد نجح، أو
  /// إخباره بعطلٍ لم يقع.
  ///
  /// تقرير من أخبار القناة نفسها — آخر ما يُلجأ إليه.
  ///
  /// حين يضيع الردّ ولا تعود الصفوف بحصيلتها، يبقى ما رآه المستخدم يمرّ
  /// أمامه صنفاً صنفاً. وهو ناقصٌ بطبعه — لا يعرف إلا ما وصل — لكنّ
  /// «أُضيف مئتان وستون» أصدق من «لم يُزامَن شيء» عن مزامنةٍ تمّت.
  factory ImportReport.fromItemEvents({
    required String jobId,
    required List<ImportItemEvent> events,
    List<ImportOfferEvent> offerEvents = const [],
  }) {
    final added = <ImportAppliedItem>[];
    final modified = <ImportAppliedItem>[];
    final failed = <ImportFailure>[];
    var skipped = 0;

    // صفٌّ واحد لكل رقم: القناة قد تُعيد إرسال ما أرسلت بعد عودة اتصال.
    final seen = <int>{};
    for (final e in events) {
      if (!seen.add(e.rowNumber)) continue;
      final item = ImportAppliedItem(
        rowNumber: e.rowNumber,
        displayName: e.name,
        price: e.price,
        previousPrice: e.previousPrice,
      );
      switch (e.outcome) {
        case ImportOutcome.added:
          added.add(item);
        case ImportOutcome.repriced:
          modified.add(item);
        case ImportOutcome.failed:
          failed.add(ImportFailure(
            rowNumber: e.rowNumber,
            name: e.name,
            message: e.message ?? 'تعذّرت الإضافة',
          ));
        case ImportOutcome.skipped:
          skipped++;
        case ImportOutcome.pending:
          break;
      }
    }

    return ImportReport(
      jobId: jobId,
      added: added,
      modified: modified,
      failed: failed,
      skippedCount: skipped,
      offers: _createdOffers(offerEvents),
      offerFailures: _failedOffers(offerEvents),
    );
  }

  /// [offerEvents] ما وصل عن العروض على القناة الفورية: حالة المهمة لا
  /// تحمل العروض، وهذه وحدها تعرف أيّها أُنشئ وأيّها تعذّر.
  factory ImportReport.fromRows({
    required String jobId,
    required List<ImportRow> rows,
    List<ImportOfferEvent> offerEvents = const [],
  }) {
    final added = <ImportAppliedItem>[];
    final modified = <ImportAppliedItem>[];
    final failed = <ImportFailure>[];
    var skipped = 0;

    for (final row in rows) {
      switch (row.outcome) {
        case ImportOutcome.added:
          added.add(ImportAppliedItem.fromRow(row));
        case ImportOutcome.repriced:
          modified.add(ImportAppliedItem.fromRow(row));
        case ImportOutcome.failed:
          failed.add(ImportFailure(
            rowNumber: row.rowNumber,
            name: row.matched?.displayName ?? row.name,
            message: row.outcomeMessage ?? 'تعذّرت الإضافة',
          ));
        case ImportOutcome.skipped:
          skipped++;
        case ImportOutcome.pending:
          break;
      }
    }

    return ImportReport(
      jobId: jobId,
      added: added,
      modified: modified,
      failed: failed,
      skippedCount: skipped,
      offers: _createdOffers(offerEvents),
      offerFailures: _failedOffers(offerEvents),
    );
  }

  /// خبرٌ واحد لكل شركة: القناة قد تُعيد الإرسال بعد انقطاعٍ وعودة،
  /// فيظهر العرض الواحد مرّتين في التقرير بلا هذا.
  static List<ImportOfferEvent> _byCompany(List<ImportOfferEvent> events) {
    final seen = <String>{};
    return [
      for (final e in events)
        if (seen.add(e.company.trim().toLowerCase())) e,
    ];
  }

  static List<ImportCreatedOffer> _createdOffers(
    List<ImportOfferEvent> events,
  ) =>
      [
        for (final e in _byCompany(events))
          if (e.created)
            ImportCreatedOffer(
              offerId: e.offerId!,
              company: e.company,
              title: e.title,
              itemCount: e.itemCount,
            ),
      ];

  static List<ImportOfferFailure> _failedOffers(
    List<ImportOfferEvent> events,
  ) =>
      [
        for (final e in _byCompany(events))
          if (!e.created)
            ImportOfferFailure(
              company: e.company,
              message: e.message ?? 'تعذّر إنشاء العرض',
            ),
      ];
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

/// عرضٌ فرغت المزامنة منه — يصل لحظة إنشائه.
///
/// منفصلٌ عن [ImportItemEvent] لأنه ليس صنفاً: له عنوانٌ وشركةٌ وعددُ
/// بنود، ويُعرَض بطاقةً بشكله لا سطراً في قائمة الأصناف.
class ImportOfferEvent {
  const ImportOfferEvent({
    required this.jobId,
    required this.company,
    required this.title,
    required this.itemCount,
    required this.done,
    required this.total,
    this.offerId,
    this.message,
  });

  final String jobId;

  /// معرّف العرض المُنشأ — فارغٌ إن تعذّر.
  final String? offerId;

  final String company;
  final String title;
  final int itemCount;

  /// سبب التعذّر إن تعذّر.
  final String? message;

  final int done;
  final int total;

  bool get created => offerId != null && message == null;

  factory ImportOfferEvent.fromJson(Map<String, dynamic> j) => ImportOfferEvent(
        jobId: j['jobId'] as String? ?? '',
        offerId: _str(j['offerId']),
        company: j['company'] as String? ?? '',
        title: j['title'] as String? ?? '',
        itemCount: (j['itemCount'] as num?)?.toInt() ?? 0,
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
