import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tawrid_app/app/theme/app_spacing.dart';
import 'package:tawrid_app/app/theme/app_tokens_ext.dart';
import 'package:tawrid_app/core/network/api_exception.dart';
import 'package:tawrid_app/core/realtime/inventory_import_hub.dart';
import 'package:tawrid_app/core/state/inventory_revision.dart';
import 'package:tawrid_app/features/wh_medicines/import_offer_setup_page.dart';
import 'package:tawrid_app/models/ai_import_models.dart';
import 'package:tawrid_app/repositories/inventory_import_repository.dart';
import 'package:tawrid_app/repositories/sales_offer_repository.dart';
import 'package:tawrid_app/repositories/warehouse_service_area_repository.dart';
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
  bool _cancelling = false;

  /// خبرٌ لا عطل — يُعرض على شاشة البداية بعد إلغاءٍ ناجح.
  String? _notice;

  int _uploadPercent = 0;
  bool _uploading = false;

  /// المزامنة جارية — مرحلةٌ قائمة بذاتها في الواجهة.
  ///
  /// كانت ناقصة، وهذا أصل عطب «المزامنة»: الضغط على الزرّ كان ينادي
  /// الخادم ويبقى `status` على «جاهزة للمراجعة»، فتظلّ الشاشة على
  /// المراجعة بلا حراك حتى يصل التقرير — فيبدو الزرّ كأنه لم يعمل،
  /// ويُضغط ثانيةً.
  bool _applying = false;

  /// ما تمّت مزامنته حتى الآن — الأحدث أولاً، يصل صنفاً صنفاً.
  final List<ImportItemEvent> _syncItems = [];
  int _syncDone = 0;
  int _syncTotal = 0;

  /// أخبار العروض كما وصلت من الخادم — الأحدث أولاً.
  final List<ImportOfferEvent> _syncOffers = [];

  /// العروض التي أقرّها المستخدم، بترتيب إقرارها.
  ///
  /// تُحفَظ عند الضغط على «مزامنة» لا عند وصول خبرها: بطاقةُ العرض يجب
  /// أن تكون أمام العين قبل إنشائه لا بعده — فيرى المستخدم ما يُنتظر
  /// إنشاؤه وما أُنشئ، بدل قائمةٍ تنبت من العدم ولا يعرف متى تكتمل.
  List<_PlannedOffer> _offerPlans = const [];

  /// العروض كما حرّرها المستخدم في شاشة الإعداد.
  ///
  /// `null` تعني «لم يفتحها» لا «لا عروض»: القائمة الفارغة قرارٌ صريح
  /// («بلا عروض») يجب أن يُحترم، والفرق بينهما لا يحمله طولُ القائمة.
  List<ImportOfferPlan>? _offerDraft;

  /// الخطّة المُقرّة، محفوظةً حتى تُنادى خطوة العروض.
  ///
  /// العروض لم تعد حقلاً في طلب التطبيق بل نداءً بعده، فيجب أن تبقى
  /// الخطّة في متناول اليد حين يعود ردُّ التطبيق — ومن أيّ طريقٍ عاد:
  /// من الردّ نفسه، أو من المراقبة الدورية حين يضيع الردّ.
  List<ImportOfferPlan> _pendingOffers = const [];

  /// يُرفَع الملف بلا مطابقة كتالوج — مزامنةٌ مع المخزون والعروض وحدهما.
  ///
  /// قرارٌ يُتَّخذ قبل الرفع لا بعده: المطابقة مرحلةٌ في الخادم تجري
  /// أثناء التحليل، فلا تُلغى بأثرٍ رجعي.
  bool _skipCatalog = false;

  /// الملف نشرة أسعار — فكل أصنافه بنود عرضٍ لا حَمَلةُ الخصم وحدهم.
  ///
  /// «ما هو بند عرض؟» سؤالٌ لا يملك الوكيل جوابه: هو يرى خصماً أو
  /// بونصاً فيعرفه عرضاً، وأكثر ما يصل المستودعات نشرةُ أسعارٍ صرف بلا
  /// علامةٍ يلتقطها. فصاحب المستودع وحده يعرف أيّهما رفع.
  bool _priceListMode = false;

  /// أقرّ المستخدم أن يمضي رغم بنودٍ ينقصها سعرُها.
  ///
  /// قرارٌ صريح لا صمت: اللافتة تقول كم بنداً سيُطرَح، وتعرض ملأه أو
  /// تركه. والتارك يمضي بلا أن تُعاد عليه في كل إعادة بناء.
  bool _gapsIgnored = false;

  /// هل نُوديت خطوة العروض لهذا التطبيق؟
  ///
  /// النداء ليس آمناً للتكرار — مرّتان يُنشئان عرضين. وللردّ طريقان
  /// يصل منهما، فبلا هذا العلم قد يسلكهما معاً.
  bool _offersSent = false;

  /// نشر العروض المُنشأة جارٍ — بعد وصول التقرير مباشرةً.
  bool _publishing = false;

  /// عروضٌ تعذّر نشرها، بأسمائها. أُنشئت ولم تُعلَن.
  List<String> _publishFailed = const [];

  /// سقط ردّ التطبيق والكتابة ماضيةٌ في الخادم.
  ///
  /// ليس عطلاً يُعرَض: الطلب طريقٌ لا عمل، وانقطاعه لا يوقف ما بدأ هناك.
  /// فتُكمل الشاشة بالاستعلام الدوري وتقول للمستخدم من أين تتابع.
  bool _detached = false;

  /// تعديلات المستخدم في المراجعة — تُرسل عند التطبيق.
  final Map<String, double?> _priceOverrides = {};
  final Map<String, String> _catalogOverrides = {};
  List<ImportRow> _rows = const [];

  final List<StreamSubscription<void>> _subs = [];

  // استطلاعٌ احتياطي: القناة الفورية تسريعٌ لا ضمان، وإن سقطت يجب أن
  // تُكمل الشاشة بدل أن تتجمّد على آخر إطار وصلها.
  Timer? _poll;

  /// مراقبة التطبيق — مستقلّة عن [_poll] لأن عملها مختلف.
  ///
  /// ذاك يتابع التحليل ويتوقّف متى خرجت المهمة من مراحله، وهذه تبدأ حيث
  /// يقف ولا تنتهي إلا بانتهاء الكتابة.
  Timer? _applyWatch;

  /// استعلاماتٌ متتالية لم تصل — عدّادُ صبرٍ على طريقٍ ساقط.
  int _watchMisses = 0;

  /// آخر لحظةٍ تُنتظر فيها نهاية المزامنة.
  ///
  /// مهمةٌ عالقة في الخادم لا تُصلحها شاشةٌ تنتظر إلى الأبد: بعد المهلة
  /// تُعاد المراجعة برسالةٍ تقول أين يُراجع ما كُتب.
  DateTime? _applyDeadline;

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
    _applyWatch?.cancel();
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

    // صنفٌ انتهت مزامنته — يُضاف إلى القائمة فور وصوله.
    _subs.add(hub.item.listen((event) {
      if (!mounted || event.jobId != _job?.jobId) return;
      setState(() {
        // الأحدث أولاً: الجديد يظهر في أعلى القائمة حيث تنظر العين،
        // بدل أن يُدفن تحت عشرات الأسطر السابقة.
        _syncItems.insert(0, event);
        _syncDone = event.done;
        if (event.total > 0) _syncTotal = event.total;
      });
    }));

    // عرضٌ فرغ إنشاؤه — يُعرَض بطاقةً فوق قائمة الأصناف.
    _subs.add(hub.offer.listen((event) {
      if (!mounted || event.jobId != _job?.jobId) return;
      setState(() => _syncOffers.insert(0, event));
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
  ///
  /// الالتقاط هنا وفي أخواته `on Object` لا `on ApiException`: طبقة
  /// الشبكة ترمي `DioException`، و`ApiException` تُشتقّ منها عند العرض
  /// لا قبله. والتقاطُ النوع الخطأ لا يُسقط رسالةً فحسب — بل يترك
  /// الشاشة على حالها الأخير بلا نهاية.
  Future<void> _resumeActive() async {
    try {
      final job = await ref.read(inventoryImportRepositoryProvider).active();
      if (!mounted || job == null) return;
      _adopt(job);
      if (job.status == ImportStatus.ready) {
        await _loadJob(job.jobId);
      } else if (job.status == ImportStatus.applying) {
        // مزامنةٌ تركها وعاد: تُستأنف شاشتها بدل أن تُستقبل الشاشة
        // الأولى — فلا يرفع الملف ثانيةً على مخزونٍ يُكتب الآن.
        setState(() {
          _applying = true;
          _syncTotal = 0;
          _watchMisses = 0;
          _applyDeadline = DateTime.now().add(const Duration(minutes: 30));
          _activity = 'يزامن مع مخزونك…';
        });
        _watchApply(job.jobId);
      } else {
        _startPolling();
      }
    } on Object {
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
      _notice = null;
      _report = null;
      _rows = const [];
      _syncItems.clear();
      _syncOffers.clear();
      _offerPlans = const [];
      _offerDraft = null;
      _syncDone = 0;
      _syncTotal = 0;
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
            skipCatalogMatching: _skipCatalog,
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
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = ApiException.from(e).message;
      });
    }
  }

  /// عدد الصفوف المحلَّلة حين جُلبت قائمة الأصناف آخر مرّة.
  ///
  /// الصفوف لا تتغيّر إلا عند اكتمال دفعة وكيل (كل دقيقة أو أكثر)، بينما
  /// العدّادات تتغيّر مع كل استطلاع. فجلبها مع كل نبضة يعني نقل مئات
  /// الصفوف كل ثلاث ثوانٍ بلا جديد — وجلبها عند تغيّر العدد وحده يُعطي
  /// نفس النتيجة بجزءٍ من الحِمل.
  int _rowsFetchedAt = -1;

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      final job = _job;
      if (!mounted || job == null || !job.status.isRunning) return;

      final progressed = job.analyzedRows != _rowsFetchedAt;
      if (progressed) _rowsFetchedAt = job.analyzedRows;

      _loadJob(job.jobId, silent: true, includeRows: progressed);
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
    } on Object catch (e) {
      if (!mounted || silent) return;
      setState(() => _error = ApiException.from(e).message);
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

    // copyWith لا بناءٌ يدوي: الصفّ صار يحمل شركةً وخصماً وبونصاً
    // وصلاحية، وكلّها كانت تسقط صامتةً عند كل تعديل سعر.
    final next = [..._rows];
    next[index] = row.copyWith(price: price, selected: true, clearPrice: price == null);

    setState(() {
      _rows = next;
      _priceOverrides[row.id] = price;
    });
  }

  /// بنود العرض المحدَّدة، مجموعةً بالشركة.
  ///
  /// الشركة مفتاح التجميع لأنها وحدة التفاوض في السوق: المستودع يتّفق
  /// مع شركةٍ على شروطٍ فتسري على أصنافها، لا على صنفٍ صنف.
  List<ImportOfferGroup> get _offerGroups {
    final byCompany = <String, List<ImportRow>>{};

    for (final row in _rows) {
      // `canBeOfferItem` لا `isOfferItem`: الصفّ بلا سعرٍ يُطرَح في
      // الخادم، وعدّه هنا يجعل الشريط يَعِد بعشرين بنداً ويصل منها
      // سبعة عشر — ورقمٌ يكذب أسوأ من رقمٍ ناقص. ومن طُرح يُقال له
      // أنه طُرح في لافتة «الحقول الناقصة» لا يُطوى عنه.
      //
      // وفي وضع نشرة الأسعار يسقط شرط «حَمَل خصماً أو بونصاً» وحده:
      // الاسم والسعر يبقيان شرطين، فنشرةٌ بلا أسعار ليست نشرة.
      final eligible = _priceListMode
          ? row.isActionable && !row.needsPrice
          : row.canBeOfferItem;

      if (!eligible || !row.selected) continue;
      byCompany.putIfAbsent(row.company?.trim() ?? '', () => []).add(row);
    }

    final groups = byCompany.entries
        .map((e) => ImportOfferGroup(
              company: e.key,
              rows: e.value,
              includeAllItems: _priceListMode,
            ))
        .toList();

    // الأكثر بنوداً أولاً، والمجهولة آخراً: هي الأقلّ إفادةً وأقربها
    // إلى أن تُترك بلا عرض.
    groups.sort((a, b) {
      if (a.isUnnamed != b.isUnnamed) return a.isUnnamed ? 1 : -1;
      return b.rows.length.compareTo(a.rows.length);
    });

    return groups;
  }

  Future<void> _apply() async {
    final job = _job;
    if (job == null) return;

    final selected = _rows
        .where((r) => r.selected && r.isActionable)
        .map((r) => r.id)
        .toList();
    if (selected.isEmpty) return;

    // ── خطوة العروض ───────────────────────────────────────────────────
    // لم تعد شاشةً تُفرَض بين المراجعة والمزامنة: كل حقلٍ فيها له افتراضٌ
    // صحيح (العنوان من الشركة وتاريخه، والمدّة شهر، والاستهداف كامل
    // التغطية)، وسؤالُ المستخدم عنها في كل ملفٍ تأكيدٌ على ما لن يُغيّره.
    // فتُبنى الخطة هنا، ويفتح الشاشة من أرادها من شريط المراجعة.
    var offers = const <ImportOfferPlan>[];
    final groups = _offerGroups;

    if (groups.isNotEmpty) {
      offers = _offerDraft ?? _autoOffers(groups);

      // تعذّر الافتراض — لا مناطق تغطيةٍ معروفة، والخادم يرفض عرضاً بلا
      // استهداف. فلا مفرّ من سؤالٍ هنا، وهو السؤال الوحيد الباقي.
      if (offers.isEmpty && _offerDraft == null) {
        final chosen = await _editOffers(groups);
        if (chosen == null || !mounted) return;
        offers = chosen;
      }
    }

    // الاستطلاع الأول يتوقّف هنا: المهمة غادرت مراحل التحليل، ومراقبة
    // التطبيق تأخذ مكانه.
    _poll?.cancel();

    setState(() {
      _applying = true;
      _detached = false;
      _syncItems.clear();
      _syncOffers.clear();
      _syncDone = 0;
      _syncTotal = selected.length;
      _offerPlans = _plannedOffers(groups, offers);
      _pendingOffers = offers;
      _offersSent = false;
      _watchMisses = 0;
      _applyDeadline = DateTime.now().add(const Duration(minutes: 30));
      _activity = 'يزامن مع مخزونك…';
      _error = null;
    });

    // المراقبة تبدأ مع الطلب لا بعد سقوطه: الكتابة تجري في الخادم سواءٌ
    // وصل الردّ أم لا، وسؤالٌ دوريٌّ عنها يُنهي الشاشة بالحقيقة مهما جرى
    // للطلب نفسه. وهذا أصل العطب الذي كان: ردٌّ انقضت مهلته لا يصل أبداً،
    // ولا شيء خلفه يسأل — فتبقى الشاشة على «يزامن…» إلى ما لا نهاية.
    _watchApply(job.jobId);

    try {
      final report =
          await ref.read(inventoryImportRepositoryProvider).apply(
                job.jobId,
                selectedRowIds: selected,
                priceOverrides: _priceOverrides,
                catalogOverrides: _catalogOverrides,
              );
      if (!mounted) return;
      await _finishApply(report);
    } on Object catch (e) {
      if (!mounted || !_applying) return;
      // `on ApiException` كانت تُخطئ الهدف: ما يرميه Dio عند انقضاء
      // المهلة `DioException` لا `ApiException`، فكان العطل يُفلت من
      // الالتقاط ويبقى `_applying` صحيحاً إلى الأبد.
      final err = ApiException.from(e);

      // عطل الطريق لا يُبطل ما يكتبه الخادم — تُكمل المراقبة وتُخبر
      // الشاشةُ المستخدمَ من أين تتابع. وما عداه ردٌّ صريح بالرفض:
      // يعود إلى المراجعة بتحديداته كما هي فيُصلح ويُعيد، بلا رفع الملف.
      if (err.isNetwork) {
        setState(() => _detached = true);
        return;
      }
      _stopApply(err.message);
    }
  }

  /// خطّة العروض بالقيم الافتراضية — فارغةٌ إن لم تُعرَف مناطق التغطية.
  List<ImportOfferPlan> _autoOffers(List<ImportOfferGroup> groups) {
    final served = ref.read(myServiceGovernoratesProvider).value;
    if (served == null || served.isEmpty) return const [];

    final regions = regionsOfCoverage(served);
    if (regions.isEmpty) return const [];

    final now = DateTime.now();
    return [
      for (final g in groups) g.defaultPlan(now: now, regions: regions),
    ];
  }

  /// يفتح شاشة إعداد العروض ويحفظ ما خرج منها.
  Future<List<ImportOfferPlan>?> _editOffers(
    List<ImportOfferGroup> groups,
  ) async {
    final chosen = await Navigator.of(context).push<List<ImportOfferPlan>>(
      MaterialPageRoute(
        builder: (_) => ImportOfferSetupPage(groups: groups),
      ),
    );
    if (chosen == null || !mounted) return null;
    setState(() => _offerDraft = chosen);
    return chosen;
  }

  /// بطاقات العروض كما ستُعرَض — من الخطة لا من الأخبار.
  static List<_PlannedOffer> _plannedOffers(
    List<ImportOfferGroup> groups,
    List<ImportOfferPlan> plans,
  ) {
    final counts = {
      for (final g in groups) _companyKey(g.company): g.rows.length,
    };
    return [
      for (final plan in plans)
        _PlannedOffer(
          company: plan.company,
          title: plan.title,
          itemCount: counts[_companyKey(plan.company)] ?? 0,
        ),
    ];
  }

  static String _companyKey(String company) => company.trim().toLowerCase();

  /// يراقب الكتابة في الخادم حتى تنتهي.
  ///
  /// حالة المهمة في قاعدة بيانات الخادم هي المرجع، لا ردُّ الطلب: الردّ
  /// قد يضيع وقد يتأخّر، والحالة لا تكذب. وحين تصير «طُبِّقت» يُبنى
  /// التقرير من حصيلة الصفوف نفسها.
  void _watchApply(String jobId) {
    _applyWatch?.cancel();
    var busy = false;

    _applyWatch = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted || !_applying || busy) return;

      final deadline = _applyDeadline;
      if (deadline != null && DateTime.now().isAfter(deadline)) {
        _stopApply(
          'طالت المزامنة أكثر من المعتاد — راجع «أدويتي» قبل إعادة المحاولة',
        );
        return;
      }

      busy = true;
      try {
        final job = await ref
            .read(inventoryImportRepositoryProvider)
            .get(jobId, includeRows: false);
        if (!mounted || !_applying) return;
        _watchMisses = 0;

        switch (job.status) {
          case ImportStatus.applied:
            await _reportFromServer(jobId);
          case ImportStatus.failed:
            _stopApply(job.failureMessage ?? 'تعذّرت المزامنة');
          case ImportStatus.cancelled:
            _stopApply('أُوقفت المزامنة');
          default:
            // ما زالت تكتب — الأخبار تصل على القناة، ولا شيء يُقال هنا.
            break;
        }
      } on Object {
        if (!mounted || !_applying) return;
        _watchMisses++;
        // ما دام الطلب قائماً فسقوط استعلامٍ لا يعني شيئاً. أمّا وقد سقط
        // الطلب أيضاً فلم يبقَ ما يُنتظر منه خبر: صمتٌ متّصلٌ على
        // الطريقين انقطاعٌ يُقال، لا انتظارٌ بلا نهاية.
        if (_detached && _watchMisses >= 8) {
          _stopApply(
            'انقطع الاتصال أثناء المزامنة — راجع «أدويتي» لتعرف ما أُضيف '
            'قبل إعادة المحاولة',
          );
        }
      } finally {
        busy = false;
      }
    });
  }

  /// يبني التقرير بعد أن أعلن الخادم انتهاء الكتابة.
  Future<void> _reportFromServer(String jobId) async {
    try {
      final job = await ref.read(inventoryImportRepositoryProvider).get(jobId);
      if (!mounted || !_applying) return;

      // القائمتان مقلوبتان للعرض (الأحدث أولاً)، والتقرير يُقرأ بترتيب
      // الحدوث.
      final offerEvents = _syncOffers.reversed.toList();

      // الصفوف أولاً فهي كاملة، وأخبار القناة عند خلوّها من الحصيلة:
      // تقريرٌ فارغ عن مزامنةٍ تمّت أسوأ من تقريرٍ ناقص عنها.
      final settled =
          job.rows.any((r) => r.outcome != ImportOutcome.pending);

      await _finishApply(settled
          ? ImportReport.fromRows(
              jobId: jobId,
              rows: job.rows,
              offerEvents: offerEvents,
            )
          : ImportReport.fromItemEvents(
              jobId: jobId,
              events: _syncItems.reversed.toList(),
              offerEvents: offerEvents,
            ));
    } on Object {
      // الصفوف لم تصل — النبضة التالية تسأل ثانيةً.
    }
  }

  Future<void> _finishApply(ImportReport report) async {
    // إنهاءٌ واحد لكل مزامنة. للردّ طريقان — الطلب والمراقبة — وقد يصل
    // الأبطأ بعد أن أنهى الأسرع: فلولا هذا الحارس لاستُبدل تقريرٌ كاملٌ
    // بعروضه بتقريرٍ بُني قبلها.
    if (!_applying) return;

    _applyWatch?.cancel();

    // العروض بعد المخزون لا معه: الخادم فصل الخطوتين، فتُنادى الثانية
    // هنا — حيث يلتقي طريقا الردّ، من الطلب أو من المراقبة.
    final full = await _createOffers(report);
    if (!mounted) return;

    setState(() {
      _applying = false;
      _detached = false;
      _applyDeadline = null;
      _report = full;
    });

    // «أدويتي» و«العروض» فرعان حيّان في IndexedStack لا يُعاد بناؤهما،
    // فما كُتب الآن لا يظهر فيهما ما لم يُطلَب منهما إعادة الجلب — ويبدو
    // الاستيراد كأنه لم يحدث وقد حدث.
    if (full.total > 0 || full.offers.isNotEmpty) {
      ref.read(inventoryRevisionProvider.notifier).bump();
    }

    if (full.offers.isNotEmpty) _publishCreated(full.offers);
  }

  /// يُنشئ العروض المُقرّة ويدمج حصيلتها في التقرير.
  ///
  /// الشاشة تبقى على «يزامن» أثناءه: المستخدم ضغط زرّاً واحداً، وتقسيمُ
  /// انتظاره إلى انتظارين لا يعنيه. وبطاقات العروض تتبدّل أمامه بأخبار
  /// القناة كما كانت.
  Future<ImportReport> _createOffers(ImportReport report) async {
    final plans = _pendingOffers;
    if (plans.isEmpty || _offersSent) return report;

    // يُرفع قبل أول await لا بعده: للردّ طريقان يصل منهما، وتبديلٌ
    // بينهما في أثناء الانتظار يُنشئ كل عرضٍ مرّتين.
    _offersSent = true;

    if (!mounted) return report;
    setState(() => _activity = 'يُنشئ العروض…');

    try {
      final result = await ref
          .read(inventoryImportRepositoryProvider)
          .createOffers(report.jobId, plans);
      return report.withOffers(result);
    } on Object catch (e) {
      // عطلُ هذه الخطوة لا يمسّ المخزون — وقد كُتب وحُفظ. فيُقال ولا
      // يُكتَم: صاحبه يحتاج أن يعرف ليُنشئ عروضه من شاشة العروض.
      return report.withOfferError(ApiException.from(e).message);
    }
  }

  /// ينشر العروض التي أنشأها الاستيراد.
  ///
  /// الخادم يُنشئها مسوّدةً، والمسوّدة لا يراها صيدلي. وقد اختار صاحب
  /// المستودع أن يُنشَر ما يستورده فوراً — فيُنشَر هنا بدل أن يُطالَب
  /// بفتح كل عرضٍ ونشره بيده.
  ///
  /// واحداً واحداً لا دفعةً: لا مسار يقبل جمعها، وفشلُ واحدٍ لا يجوز أن
  /// يمنع نشر البقية. وما تعذّر يُقال باسمه — عرضٌ أُنشئ ولم يُعلَن
  /// حالةٌ وسطى، وكتمانُها يُري المستودع عرضاً يظنّه حيّاً وهو ساكن.
  Future<void> _publishCreated(List<ImportCreatedOffer> offers) async {
    setState(() {
      _publishing = true;
      _publishFailed = const [];
    });

    final repo = ref.read(salesOfferRepositoryProvider);
    final failed = <String>[];

    for (final offer in offers) {
      if (offer.offerId.isEmpty) continue;
      try {
        await repo.publishOffer(offer.offerId);
      } on Object {
        failed.add(offer.title.isNotEmpty ? offer.title : offer.company);
      }
    }

    if (!mounted) return;
    setState(() {
      _publishing = false;
      _publishFailed = failed;
    });

    // شاشة العروض تُعيد الجلب فتظهر سارية لا مسوّدة.
    ref.read(inventoryRevisionProvider.notifier).bump();
  }

  /// ينهي المزامنة بعطل — ويعود إلى المراجعة بتحديدات المستخدم كما هي.
  void _stopApply(String error) {
    _applyWatch?.cancel();
    setState(() {
      _applying = false;
      _detached = false;
      _applyDeadline = null;
      _error = error;
    });
  }

  /// حال كل عرضٍ الآن — خطةُ المستخدم مدموجةً بأخبار الخادم.
  ///
  /// البطاقات تُرسَم من الخطة بترتيبها الثابت، فيتبدّل حال الواحدة في
  /// مكانها بدل أن تقفز القائمة مع كل خبر: قائمةٌ تُقرأ كقائمة مهامٍ
  /// تُشطَب واحدةً بعد واحدة.
  List<_OfferProgress> get _offerProgress {
    // خبرٌ واحد لكل شركة — وأوّل ما في القائمة أحدثُها.
    final events = <String, ImportOfferEvent>{};
    for (final e in _syncOffers) {
      events.putIfAbsent(_companyKey(e.company), () => e);
    }

    if (_offerPlans.isEmpty) {
      return [
        for (final e in _syncOffers.reversed) _OfferProgress.fromEvent(e),
      ];
    }

    // أوّل عرضٍ بلا خبرٍ هو ما يُنشأ الآن — ولا يُقال ذلك قبل أوانه:
    // الخادم يكتب الأصناف أولاً، فما قبل فراغها انتظارٌ لا إنشاء.
    final itemsSettled = _syncTotal > 0 && _syncDone >= _syncTotal;
    var creatingTaken = false;
    final out = <_OfferProgress>[];

    for (final plan in _offerPlans) {
      final event = events.remove(_companyKey(plan.company));
      if (event != null) {
        out.add(_OfferProgress(
          company: plan.company.isEmpty ? event.company : plan.company,
          title: event.title.isEmpty ? plan.title : event.title,
          itemCount: event.itemCount > 0 ? event.itemCount : plan.itemCount,
          state: event.created ? _OfferSync.created : _OfferSync.failed,
          message: event.message,
        ));
        continue;
      }

      final creating =
          !creatingTaken && (itemsSettled || _syncOffers.isNotEmpty);
      if (creating) creatingTaken = true;

      out.add(_OfferProgress(
        company: plan.company,
        title: plan.title,
        itemCount: plan.itemCount,
        state: creating ? _OfferSync.creating : _OfferSync.queued,
      ));
    }

    // خبرٌ عن شركةٍ ليست في الخطة — يُلحَق كما جاء بدل أن يُكتم.
    for (final event in events.values) {
      out.add(_OfferProgress.fromEvent(event));
    }

    return out;
  }

  /// يوقف المهمة الجارية بعد تأكيد.
  ///
  /// التأكيد ليس تزيّناً: الملف رُفع والتحليل قطع شوطاً، وإلغاؤه بنقرةٍ
  /// واحدة يُضيّع عملاً استغرق دقائق — لكنّ الإلغاء نفسه آمن، فلا شيء
  /// كُتب في «أدويتي» بعد.
  Future<void> _cancel() async {
    final job = _job;
    if (job == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.surface,
        title: Text('إلغاء الاستيراد؟', style: ctx.text.titleMedium),
        content: Text(
          'سيتوقّف التحليل ولن يُضاف شيء إلى مخزونك. يمكنك رفع الملف '
          'من جديد في أي وقت.',
          style: ctx.text.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('متابعة التحليل'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'إلغاء الاستيراد',
              style: TextStyle(color: ctx.tokens.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // الاستطلاع يتوقّف قبل النداء: استجابةٌ متأخّرة قد تُعيد الحالة
    // «جارية» بعد الإلغاء فتعود الشاشة إلى التحليل أمام المستخدم.
    _poll?.cancel();
    setState(() {
      _cancelling = true;
      _activity = 'يوقف الاستيراد…';
    });

    try {
      await ref.read(inventoryImportRepositoryProvider).cancel(job.jobId);
      if (!mounted) return;
      setState(() {
        _cancelling = false;
        _job = null;
        _rows = const [];
        _progress = 0;
        _activity = '';
        _notice = 'أُلغي الاستيراد — لم يُضَف شيء إلى مخزونك';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _cancelling = false;
        _error = ApiException.from(e).message;
      });
      // فشل الإلغاء يعني أنها ما زالت تعمل — فيعود الاستطلاع.
      _startPolling();
    }
  }

  void _reset() {
    _poll?.cancel();
    _applyWatch?.cancel();
    setState(() {
      _job = null;
      _report = null;
      _error = null;
      _notice = null;
      _rows = const [];
      _applying = false;
      _detached = false;
      _applyDeadline = null;
      _syncItems.clear();
      _syncOffers.clear();
      _offerPlans = const [];
      _offerDraft = null;
      _pendingOffers = const [];
      _offersSent = false;
      // قرارُ تجاهل النقص يخصّ ملفاً بعينه — والملف التالي يُسأل عنه.
      _gapsIgnored = false;
      _priceListMode = false;
      _syncDone = 0;
      _syncTotal = 0;
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

    // مناطق التغطية تُطلَب من أول إطار لا عند الحاجة إليها: هي افتراض
    // استهداف العروض، ولو انتُظر طلبُها إلى لحظة الضغط على «مزامنة»
    // لوجدها الافتراض فارغةً فسأل المستخدم سؤالاً كان يملك جوابه.
    ref.watch(myServiceGovernoratesProvider);

    final Widget body;
    if (_report != null) {
      body = _ReportView(
        report: _report!,
        publishing: _publishing,
        publishFailed: _publishFailed,
        onDone: () => Navigator.of(context).maybePop(),
        onAgain: _reset,
      );
    } else if (_applying) {
      body = _SyncingView(
        items: _syncItems,
        offers: _offerProgress,
        done: _syncDone,
        total: _syncTotal,
        detached: _detached,
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
        totalRows: job.totalRows,
        // المرحلة التي لم يُنجَز فيها صفٌّ بعد لا قياس لتقدّمها.
        measured: switch (job.status) {
          ImportStatus.analyzing => job.analyzedRows > 0,
          ImportStatus.matching => job.matchedRows > 0,
          _ => false,
        },
        startedAt: job.createdOn,
        onLeave: () => Navigator.of(context).maybePop(),
        // لا إلغاء أثناء المزامنة: الكتابة في «أدويتي» جارية، وقطعُها
        // يترك نصف الأصناف مُضافاً ونصفها لا.
        onCancel: job.status == ImportStatus.applying ? null : _cancel,
        cancelling: _cancelling,
        // ما تعرّف عليه الوكيل حتى الآن. الصفوف غير المحلَّلة تصل باسمٍ
        // فارغ (يُملأ عند تطبيعها)، فتُطرح حتى لا تظهر أسطرٌ خاوية.
        discovered: _rows.where((r) => r.name.isNotEmpty).toList(),
        analyzedRows: job.analyzedRows,
      );
    } else if (job != null && job.status == ImportStatus.ready) {
      final groups = _offerGroups;
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
        offerCount: (_offerDraft ?? _autoOffers(groups)).length,
        offerCompanies: groups.length,
        noCoverage: (ref.watch(myServiceGovernoratesProvider).value ??
                const [])
            .isEmpty,
        gapsIgnored: _gapsIgnored,
        onIgnoreGaps: () => setState(() => _gapsIgnored = true),
        priceListMode: _priceListMode,
        onPriceListChanged: (v) => setState(() {
          _priceListMode = v;
          // الخطّة المحرَّرة بُنيت على مجموعاتٍ أخرى — تُطرح لتُبنى
          // من جديد، وإلا بقيت تُشير إلى شركاتٍ لم تعد كما كانت.
          _offerDraft = null;
        }),
        onEditOffers: groups.isEmpty ? null : () => _editOffers(groups),
      );
    } else {
      body = _IdleView(
        onPick: _pick,
        error: _error,
        notice: _notice,
        skipCatalog: _skipCatalog,
        onModeChanged: (v) => setState(() => _skipCatalog = v),
      );
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
    if (_applying) return 'syncing';
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
  const _IdleView({
    required this.onPick,
    required this.skipCatalog,
    required this.onModeChanged,
    this.error,
    this.notice,
  });

  final VoidCallback onPick;

  /// الوضع المختار: تخطّي مطابقة الكتالوج الوطني.
  final bool skipCatalog;
  final ValueChanged<bool> onModeChanged;

  final String? error;

  /// خبرٌ لا عطل (إلغاءٌ تمّ مثلاً) — بنبرةٍ محايدة لا حمراء: ما فعله
  /// المستخدم بنفسه لا يُعرض عليه كخطأ.
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.x2l, AppSpacing.page, AppSpacing.x3l),
      child: Center(
        child: ConstrainedBox(
          // عريضةٌ تسع بطاقتَي الوضع جنباً إلى جنب: كانت ٤٨٠ فتنزل
          // الواحدة تحت الأخرى، فتُقرآن تِباعاً لا مقارنةً — وهما خياران
          // يُقارَنان.
          constraints: const BoxConstraints(maxWidth: 920),
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
                'ارفع ملف Excel، ويقرأ وكيل الـ AI أعمدته ويفصل العيار عن '
                'الاسم — ولا يُضاف شيء لمخزونك قبل مراجعتك',
                style: context.text.bodyMedium?.copyWith(color: tk.hint),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── الوضع يُختار قبل الرفع ───────────────────────────────
              // لا بعده: المطابقة مرحلةٌ تجري في الخادم أثناء التحليل،
              // فلا تُلغى بأثرٍ رجعي. وعرضُها خيارين صريحين خيرٌ من
              // إعدادٍ مخبوء — الفرق بينهما في الزمن والنتيجة كبير.
              _ModeChooser(skipCatalog: skipCatalog, onChanged: onModeChanged),
              const SizedBox(height: AppSpacing.xl),

              if (error != null) ...[
                _NoticeCard(
                  appIcon: AppIcons.alertTriangle,
                  tone: StatusTone.danger,
                  title: 'تعذّر الاستيراد',
                  body: error!,
                ),
                const SizedBox(height: AppSpacing.lg),
              ] else if (notice != null) ...[
                _NoticeCard(
                  appIcon: AppIcons.info,
                  tone: StatusTone.info,
                  title: 'أُلغي الاستيراد',
                  body: notice!,
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
                    const _Hint('يقرأ الخصم والبونص والشركة فيُنشئ العروض'),
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

/// اختيار وضع الاستيراد: مع مطابقة الكتالوج الوطني أم بدونها.
///
/// بطاقتان متجاورتان لا مفتاحُ تبديل: الفرق بينهما ليس «ميزةً تُطفأ» بل
/// مساران مختلفان في النتيجة والزمن — والمقارنة تحتاج أن يُقرأ الوصفان
/// معاً، وهو ما لا يُتيحه مفتاح.
class _ModeChooser extends StatelessWidget {
  const _ModeChooser({required this.skipCatalog, required this.onChanged});

  final bool skipCatalog;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // تحت ٧٠٠ بكسل تنزل الواحدة تحت الأخرى: بطاقتان بعرض ٣٥٠ أضيق
        // من ذلك تقطعان كل سطرٍ في وصفهما.
        final side = constraints.maxWidth >= 700;

        final cards = [
          _ModeCard(
            title: 'مع الكتالوج الوطني',
            body: 'يطابق كل صنفٍ مع النشرة الوطنية فيُربَط بها — '
                'فيظهر في بحث الأسعار المقارن لدى الصيدليات. '
                'وما لا يجده يبقى صنفاً حرّاً تراجعه بنفسك.',
            footnote: 'أدقّ · أبطأ · مطابقةٌ بالنموذج لغير المحسوم',
            icon: AppIcons.pill,
            selected: !skipCatalog,
            onTap: () => onChanged(false),
          ),
          _ModeCard(
            title: 'مخزوني وعروضي فقط',
            body: 'بلا مطابقة: كل ما في الملف يدخل «أدويتي» باسمه وعياره '
                'كما وردا، وتُنشأ منه العروض. ويجده استيرادُ الشهر القادم '
                'فيُحدّث سعره بدل أن يُكرّره.',
            footnote: 'أسرع · أرخص · بلا ربطٍ بالنشرة الوطنية',
            icon: AppIcons.clipboardList,
            selected: skipCatalog,
            onTap: () => onChanged(true),
          ),
        ];

        if (!side) {
          return Column(
            children: [
              cards[0],
              const SizedBox(height: AppSpacing.md),
              cards[1],
            ],
          );
        }

        // IntrinsicHeight شرطٌ لا تحسين: البطاقتان تتساويان بأطولهما
        // بـ stretch، وهي تطلب ارتفاعاً محدوداً — والشاشة داخل
        // SingleChildScrollView فارتفاعها غير محدود. فبلا هذا يُطلب من
        // البطاقة ارتفاعٌ لا نهائي وتبقى الشاشة بيضاء.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: cards[1]),
            ],
          ),
        );
      },
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.body,
    required this.footnote,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String body;
  final String footnote;
  final AppIcons icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    // غير المختار يبقى مقروءاً تماماً: هو خيارٌ متاح لا شيء مُستبعَد،
    // وإخفاتُه يجعل المقارنة بينهما غير عادلة.
    return Material(
      color: selected ? tk.brandSurface : cs.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected ? cs.primary.withValues(alpha: 0.6) : cs.outline,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AppCheckbox(
                    selection:
                        selected ? AppCheckState.all : AppCheckState.none,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppIcon(icon,
                      size: 16, color: selected ? cs.primary : tk.hint),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(title,
                        style: context.text.labelLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(body, style: context.text.bodySmall),
              const SizedBox(height: AppSpacing.sm),
              Text(footnote,
                  style: context.text.labelSmall?.copyWith(color: tk.hint)),
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
    this.totalRows = 0,
    this.measured = true,
    this.startedAt,
    this.onLeave,
    this.discovered = const [],
    this.analyzedRows = 0,
    this.onCancel,
    this.cancelling = false,
  });

  final ImportStatus phase;
  final String activity;
  final double progress;
  final String? fileName;

  /// عدد صفوف الملف — يُعرض ليعرف المستخدم أن الانتظار يناسب حجمه.
  final int totalRows;

  /// هل للتقدّم المعروض قياسٌ حقيقي؟ المرحلة التي لم يُنجَز فيها صفٌّ بعد
  /// لا قياس لها، وحلقةٌ واقفة على رقمٍ ثابت دقائق تبدو تجمّداً لا انتظاراً.
  final bool measured;

  final DateTime? startedAt;
  final VoidCallback? onLeave;

  /// الأصناف التي تعرّف عليها الوكيل حتى الآن — تُعرض أولاً بأول.
  final List<ImportRow> discovered;

  final int analyzedRows;

  /// يوقف المهمة في الخادم. فارغاً يعني أن هذه المرحلة لا تُلغى.
  final VoidCallback? onCancel;

  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;

    // الانتظار بلا قائمة ينتظر، ومع قائمةٍ تنمو يُراقَب: المستخدم يرى
    // أدويته تظهر واحداً واحداً فيطمئنّ أن الوكيل يقرأ ملفه هو.
    final preview = discovered.reversed.take(6).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.x2l, AppSpacing.page, AppSpacing.x3l),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProgressRing(progress: progress, measured: measured),
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

              // عدّاد الزمن والمتبقّي: انتظارٌ طويل مع رقمٍ يتحرّك انتظار،
              // وبلا رقمٍ يتحرّك يبدو عُطلاً — والمستخدم حينها يعيد الرفع
              // فتتراكم مهام متوازية على الخادم بلا داعٍ.
              if (startedAt != null)
                _ElapsedLine(
                  startedAt: startedAt!,
                  done: analyzedRows,
                  total: totalRows,
                ),

              if (totalRows > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$totalRows صفاً في الملف',
                  style: context.text.labelSmall?.copyWith(color: tk.hint),
                  textAlign: TextAlign.center,
                ),
              ],

              // ما تعرّف عليه الوكيل — يظهر أولاً بأول لا بعد الانتهاء.
              if (preview.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                _DiscoveredList(rows: preview, total: discovered.length),
              ],

              const SizedBox(height: AppSpacing.lg),
              Text(
                'يمكنك إغلاق الشاشة — العمل يتابع في الخادم وتجده عند عودتك',
                style: context.text.labelSmall?.copyWith(color: tk.hint),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  if (onLeave != null)
                    Expanded(
                      child: AppButton(
                        label: 'متابعة لاحقاً',
                        variant: AppButtonVariant.text,
                        onPressed: cancelling ? null : onLeave,
                      ),
                    ),
                  if (onCancel != null) ...[
                    if (onLeave != null) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppButton(
                        label: 'إلغاء الاستيراد',
                        variant: AppButtonVariant.danger,
                        appIcon: AppIcons.x,
                        loading: cancelling,
                        onPressed: onCancel,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «مضى ٥:٢٣ · يتبقّى ~١٢ دقيقة» — يتجدّد كل ثانية.
class _ElapsedLine extends StatefulWidget {
  const _ElapsedLine({
    required this.startedAt,
    this.done = 0,
    this.total = 0,
  });

  final DateTime startedAt;
  final int done;
  final int total;

  @override
  State<_ElapsedLine> createState() => _ElapsedLineState();
}

class _ElapsedLineState extends State<_ElapsedLine> {
  Timer? _tick;

  /// أول لحظة رُصد فيها تقدّمٌ فعلي، وعدد الصفوف عندها — نقطة الأساس التي
  /// يُقاس منها المعدّل بدل لحظة إنشاء المهمة.
  DateTime? _firstSeenAt;
  int _firstSeenDone = 0;

  @override
  void initState() {
    super.initState();
    _noteProgress();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _ElapsedLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    _noteProgress();
  }

  void _noteProgress() {
    if (_firstSeenAt == null && widget.done > 0) {
      _firstSeenAt = DateTime.now();
      _firstSeenDone = widget.done;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.startedAt);
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');

    final remaining = _remaining();

    return Column(
      children: [
        Text(
          'مضى $minutes:$seconds',
          style: context.text.labelMedium?.copyWith(color: context.tokens.hint),
          textAlign: TextAlign.center,
        ),
        if (remaining != null) ...[
          const SizedBox(height: 2),
          Text(
            'يتبقّى ${_humanize(remaining)} تقريباً',
            style: context.text.labelMedium
                ?.copyWith(color: context.colors.primary),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// تقدير المتبقّي من المعدّل المُقاس بين آخر تقدّمين.
  ///
  /// القياس من لحظة الإنشاء يكذب: يشمل انتظار المهمة في الطابور وإقلاع
  /// الوكيل البارد، فيُحمَّل المعدّلُ زمناً لا يتكرّر — ملفٌ أنجز دفعته
  /// الأولى في نصف ساعة أكثرها انتظار، فيُقدَّر الباقي بساعات وهو دقائق.
  ///
  /// فيُقاس المعدّل من الصفوف التي أُنجزت **منذ أول تقدّم رُصد** لا منذ
  /// الإنشاء، ولا يُعرَض قبل تقدّمين: تقديرٌ من نقطةٍ واحدة بلا معنى.
  Duration? _remaining() {
    final from = _firstSeenAt;
    final base = _firstSeenDone;
    if (from == null) return null;

    final advanced = widget.done - base;
    final left = widget.total - widget.done;
    if (advanced < 10 || left <= 0) return null;

    final seconds = DateTime.now().difference(from).inSeconds;
    if (seconds < 10) return null;

    final perRow = seconds / advanced;
    return Duration(seconds: (left * perRow).round());
  }

  static String _humanize(Duration d) {
    if (d.inMinutes < 1) return 'أقل من دقيقة';
    if (d.inMinutes < 60) return '${d.inMinutes} دقيقة';

    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    return minutes == 0 ? '$hours ساعة' : '$hours ساعة و$minutes دقيقة';
  }
}

/// قائمة الأصناف التي تعرّف عليها الوكيل — الأحدث أولاً.
class _DiscoveredList extends StatelessWidget {
  const _DiscoveredList({required this.rows, required this.total});

  final List<ImportRow> rows;

  /// العدد الكلي المكتشَف (القائمة تعرض آخر بضعة منه فقط).
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: tk.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(AppIcons.pill, size: 14, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'تعرّف على $total صنفاً',
                  style: context.text.labelMedium?.copyWith(color: cs.primary),
                ),
              ),
              DotsLoader(color: cs.primary, size: 4),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // AnimatedSwitcher على المفتاح لا على العناصر: القائمة تتبدّل
          // دفعةً عند اكتمال دفعة الوكيل، فيكفي تلاشٍ واحد لها كلها.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Column(
              key: ValueKey(rows.isEmpty ? '' : rows.first.id),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        AppIcon(AppIcons.check, size: 11, color: tk.success),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            row.name,
                            style: context.text.labelSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (row.strength != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            _num(row.strength!),
                            style: context.text.labelSmall
                                ?.copyWith(color: tk.hint),
                          ),
                        ],
                        if (row.price != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            _num(row.price!),
                            style: context.text.labelSmall
                                ?.copyWith(color: cs.primary),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// حلقة تقدّم تتحرّك بسلاسة بين القيم بدل أن تقفز عند كل إطار.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress, this.measured = true});

  final double progress;
  final bool measured;

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
                // تدور بلا قيمة ما لم يكن للتقدّم قياسٌ حقيقي: مرحلةٌ لم
                // يُنجَز فيها صفٌّ بعد تبقى على رقمها دقائق — وحلقةٌ واقفة
                // على ٥٪ تبدو تجمّداً، بينما الدوران يقول «يعمل ولا يُقاس».
                value: !measured || value <= 0.01 ? null : value,
                strokeWidth: 6,
                strokeCap: StrokeCap.round,
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                backgroundColor: tk.brandSurface,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // النسبة لا تُعرض بلا قياس: رقمٌ ثابت لا يتحرّك أسوأ من
                // لا رقم، لأنه يدّعي دقّةً ليست عنده.
                if (measured)
                  Text('${(value * 100).round()}٪',
                      style: context.text.titleLarge?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      )),
                if (measured) const SizedBox(height: 2),
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

// ── المزامنة الجارية ─────────────────────────────────────────────────────
/// ما يجري أثناء الكتابة في «أدويتي» — صنفاً صنفاً وقت حدوثه.
///
/// الفرق بين هذه الشاشة وغيابها هو الفرق بين «يعمل» و«تعلّق»: المزامنة
/// تمرّ على مئات الأصناف، وبلا عرضٍ لكل واحدٍ منها يبقى المستخدم أمام
/// شاشةٍ ساكنة ثم يُفاجأ بالتقرير — ولا يعرف أين تعثّرت إن تعثّرت.
class _SyncingView extends StatelessWidget {
  const _SyncingView({
    required this.items,
    required this.offers,
    required this.done,
    required this.total,
    this.detached = false,
  });

  final List<ImportItemEvent> items;
  final List<_OfferProgress> offers;
  final int done;
  final int total;

  /// سقط ردّ الطلب والخادم يُكمل — يُقال صراحةً لا يُكتَم.
  final bool detached;

  int get offersCreated =>
      offers.where((o) => o.state == _OfferSync.created).length;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final fraction = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;

    final added = items.where((i) => i.outcome == ImportOutcome.added).length;
    final repriced =
        items.where((i) => i.outcome == ImportOutcome.repriced).length;
    final failed = items.where((i) => i.outcome == ImportOutcome.failed).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.page, AppSpacing.xl, AppSpacing.page, AppSpacing.md),
          child: Column(
            children: [
              _ProgressRing(
                progress: fraction,
                // القياس يبدأ عند أول صنفٍ يصل: نسبةٌ صفرية مرسومة قبل
                // أي خبر توحي بتوقّفٍ لم يحدث.
                measured: done > 0,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('يزامن مع مخزونك…', style: context.text.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                total > 0
                    ? 'أنجز $done من $total صنفاً — لا تُغلق الشاشة'
                    : 'لا تُغلق الشاشة حتى تنتهي المزامنة',
                style: context.text.bodySmall?.copyWith(color: tk.hint),
                textAlign: TextAlign.center,
              ),
              // الصمت عن انقطاعٍ وقع يجعل الشاشة تبدو واقفة. وقولُه مع
              // «نتابع من الخادم» يُطمئن بما هو صحيح: الكتابة هناك ماضية.
              if (detached) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'انقطع ردّ الطلب — نتابع الحالة من الخادم',
                  style: context.text.labelSmall?.copyWith(color: tk.warning),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                alignment: WrapAlignment.center,
                children: [
                  if (added > 0)
                    StatusBadge(
                        label: 'أُضيف $added', tone: StatusTone.success),
                  if (repriced > 0)
                    StatusBadge(
                        label: 'حُدِّث سعر $repriced', tone: StatusTone.info),
                  if (failed > 0)
                    StatusBadge(
                        label: 'تعذّر $failed', tone: StatusTone.danger),
                  if (offers.isNotEmpty)
                    StatusBadge(
                      label: 'عروض $offersCreated من ${offers.length}',
                      tone: StatusTone.brand,
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty && offers.isEmpty
              ? Center(
                  child: Text(
                    'يبدأ بعد لحظة…',
                    style: context.text.bodySmall?.copyWith(color: tk.hint),
                  ),
                )
              // العروض فوق الأصناف لا مبثوثةً بينها: العرض حصيلةُ عشرات
              // البنود، وإخفاؤه وسط قائمةٍ تمرّ بسرعة يُضيّع أهمّ ما حدث.
              : ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                      AppSpacing.md, AppSpacing.page, AppSpacing.lg),
                  children: [
                    if (offers.isNotEmpty) ...[
                      AppSectionHeader(
                        title: 'العروض',
                        appIcon: AppIcons.gift,
                        trailing: Text(
                          '$offersCreated / ${offers.length}',
                          style: context.text.labelSmall
                              ?.copyWith(color: tk.hint),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    for (final offer in offers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _SyncOfferCard(offer: offer),
                      ),
                    if (offers.isNotEmpty && items.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      AppSectionHeader(
                        title: 'الأصناف',
                        appIcon: AppIcons.pill,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _SyncItemTile(item: item),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// عرضٌ أقرّه المستخدم وينتظر دوره في الخادم.
class _PlannedOffer {
  const _PlannedOffer({
    required this.company,
    required this.title,
    required this.itemCount,
  });

  final String company;
  final String title;

  /// بنوده كما عُدَّت من الملف — عددٌ صادق قبل أن يردّ الخادم بعدده.
  final int itemCount;
}

/// حال العرض الواحد في رحلته: ينتظر، يُنشأ، أُنشئ، أو تعذّر.
enum _OfferSync { queued, creating, created, failed }

/// ما تعرضه بطاقة العرض أثناء المزامنة.
class _OfferProgress {
  const _OfferProgress({
    required this.company,
    required this.title,
    required this.itemCount,
    required this.state,
    this.message,
  });

  /// من خبرٍ وصل عن عرضٍ لا خطّة له — حالةٌ نادرة لكنها لا تُكتَم.
  factory _OfferProgress.fromEvent(ImportOfferEvent e) => _OfferProgress(
        company: e.company,
        title: e.title,
        itemCount: e.itemCount,
        state: e.created ? _OfferSync.created : _OfferSync.failed,
        message: e.message,
      );

  final String company;
  final String title;
  final int itemCount;
  final _OfferSync state;
  final String? message;

  bool get settled =>
      state == _OfferSync.created || state == _OfferSync.failed;
}

/// بطاقة عرضٍ أثناء المزامنة — بحاله الآن لا بنتيجته وحدها.
///
/// بطاقةٌ لا سطر: العرض ليس صنفاً — هو حصيلة عشرات البنود، وله عنوانٌ
/// وشركةٌ وعدد. وعرضُه بحجم السطر يُساويه بصنفٍ واحد وليس سواءً.
///
/// وهي تُرسَم من لحظة الإقرار لا من لحظة الإنشاء: المستخدم يرى عروضه
/// الثلاثة أمامه، فيُشطَب الأول ثم الثاني، فيعرف كم بقي ومتى ينتهي —
/// بدل بطاقاتٍ تظهر من العدم ولا تقول عمّا لم يظهر بعد.
class _SyncOfferCard extends StatelessWidget {
  const _SyncOfferCard({required this.offer});
  final _OfferProgress offer;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    final (Color fg, Color bg, AppIcons icon, String label) =
        switch (offer.state) {
      _OfferSync.created => (
          tk.success,
          tk.successSurface,
          AppIcons.check,
          'أُضيف العرض',
        ),
      _OfferSync.failed => (
          tk.danger,
          tk.dangerSurface,
          AppIcons.alertTriangle,
          'تعذّر إنشاء العرض',
        ),
      _OfferSync.creating => (
          cs.primary,
          tk.brandSurface,
          AppIcons.gift,
          'يُنشئ العرض الآن…',
        ),
      _OfferSync.queued => (
          tk.hint,
          cs.surface,
          AppIcons.clock,
          'في الانتظار',
        ),
    };

    // ما استقرّ حالُه يدخل بحركةٍ واحدة، وما زال يُنشأ ينبض. والمنتظر
    // ساكنٌ بلا حركة: نبضُ كل البطاقات معاً ضجيجٌ لا خبر فيه.
    final Widget leading = offer.state == _OfferSync.creating
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          )
        : AppIcon(icon, size: 20, color: fg);

    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: fg.withValues(alpha: offer.settled ? 0.35 : 0.22),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              leading,
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: context.text.labelMedium?.copyWith(color: fg),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            offer.title,
            style: context.text.titleMedium?.copyWith(
              // المنتظر أبهتُ ممّا تمّ: الفرق يُقرأ قبل أن يُقرأ النص.
              color: offer.state == _OfferSync.queued ? tk.hint : null,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (offer.company.isNotEmpty)
                StatusBadge(label: offer.company, tone: StatusTone.neutral),
              if (offer.itemCount > 0)
                StatusBadge(
                  label: '${offer.itemCount} صنفاً',
                  tone: offer.state == _OfferSync.created
                      ? StatusTone.success
                      : StatusTone.neutral,
                ),
            ],
          ),
          if (offer.state == _OfferSync.failed && offer.message != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              offer.message!,
              style: context.text.bodySmall?.copyWith(color: tk.danger),
            ),
          ],
          if (offer.state == _OfferSync.created) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'يُنشَر تلقائياً عند انتهاء المزامنة',
              style: context.text.labelSmall?.copyWith(color: tk.hint),
            ),
          ],
        ],
      ),
    );

    if (offer.state == _OfferSync.creating) return _Pulse(child: card);

    return TweenAnimationBuilder<double>(
      // المفتاح بالحال لا بالشركة وحدها: تبدّلُ الحال يُعيد الحركة،
      // فيلفت العينَ أن شيئاً حدث هنا الآن.
      key: ValueKey('offer-${offer.company}-${offer.state.name}'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
      ),
      child: card,
    );
  }
}

/// سطرٌ واحد في قائمة المزامنة الحيّة.
class _SyncItemTile extends StatelessWidget {
  const _SyncItemTile({required this.item});
  final ImportItemEvent item;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;

    final (icon, fg, bg, label) = switch (item.outcome) {
      ImportOutcome.added => (
          AppIcons.plus,
          tk.success,
          tk.successSurface,
          'أُضيف'
        ),
      ImportOutcome.repriced => (
          AppIcons.tag,
          context.colors.primary,
          tk.brandSurface,
          'حُدِّث السعر'
        ),
      ImportOutcome.failed => (
          AppIcons.alertTriangle,
          tk.danger,
          tk.dangerSurface,
          'تعذّر'
        ),
      _ => (AppIcons.x, tk.hint, context.colors.surface, 'تُخطّي'),
    };

    // ظهورٌ من أسفل مع تلاشٍ — الوصول يُرى لا يُفاجئ.
    return TweenAnimationBuilder<double>(
      key: ValueKey(item.rowNumber),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: fg.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(icon, size: 18, color: fg),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: context.text.labelLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(label,
                          style: context.text.labelSmall?.copyWith(color: fg)),
                      if (item.price != null) ...[
                        Text(' · ',
                            style: context.text.labelSmall
                                ?.copyWith(color: tk.hint)),
                        // السعر القديم مشطوبٌ بجانب الجديد: التغيير
                        // يُفهَم من نظرة بلا أن يتذكّر المستخدم ما كان.
                        if (item.previousPrice != null)
                          Text(
                            '${_n(item.previousPrice!)} ← ',
                            style: context.text.labelSmall?.copyWith(
                              color: tk.hint,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        Text(_n(item.price!), style: context.priceStyle),
                      ],
                    ],
                  ),
                  if (item.message != null) ...[
                    const SizedBox(height: 2),
                    Text(item.message!,
                        style:
                            context.text.bodySmall?.copyWith(color: tk.danger)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

// ── المراجعة ─────────────────────────────────────────────────────────────
/// تصنيف صفوف المراجعة — قسمةٌ تامّة لا تتداخل.
///
/// كل صفٍّ يقع في خانةٍ واحدة لا غير، وإلا صار المجموع أكبر من العدد
/// وفقد المستخدم ثقته في الأرقام: «جديد» هو المطابَق الحاسم غير المملوك،
/// والمملوك «تحديث سعر»، والمشكوك فيه «يلزم تأكيد»، وما لا أصل له في
/// الكتالوج «غير موجود».
enum _RowFilter {
  all('الكل'),
  offers('بنود عرض'),
  missingPrice('ناقص سعر'),
  newItem('جديد'),
  priceUpdate('تحديث سعر'),
  needsConfirm('يلزم تأكيد'),
  notFound('خارج الكتالوج');

  const _RowFilter(this.label);
  final String label;

  bool matches(ImportRow row) => switch (this) {
        _RowFilter.all => true,

        // «بنود عرض» تقطع التصنيف الآخر لا تُجاوره: الصفّ بخصمٍ قد يكون
        // جديداً أو تحديثَ سعر في آن. ولذلك لا تُحسَب في قسمة الأربعة،
        // وتُعرَض وحدها مجموعةً بالشركة.
        _RowFilter.offers => row.isOfferItem,

        // و«ناقص سعر» كذلك تقطعها: ثغرةٌ لا تصنيفاً. وهي بنود العرض
        // التي لا تستطيع أن تصير بنوداً — يُجمَعن هنا ليُملأ نقصُهنّ
        // بنقرةٍ واحدة بدل البحث عنهنّ في مئة سطر.
        _RowFilter.missingPrice => row.isOfferGap,
        _RowFilter.newItem => row.matchStatus == ImportMatch.matched,
        _RowFilter.priceUpdate => row.matchStatus == ImportMatch.owned,
        _RowFilter.needsConfirm => row.matchStatus == ImportMatch.ambiguous,
        _RowFilter.notFound => row.matchStatus == ImportMatch.notFound,
      };

  StatusTone get tone => switch (this) {
        _RowFilter.all => StatusTone.neutral,
        _RowFilter.offers => StatusTone.brand,
        _RowFilter.missingPrice => StatusTone.danger,
        _RowFilter.newItem => StatusTone.success,
        _RowFilter.priceUpdate => StatusTone.info,
        _RowFilter.needsConfirm => StatusTone.warning,
        _RowFilter.notFound => StatusTone.warning,
      };
}

class _ReviewView extends StatefulWidget {
  const _ReviewView({
    required this.job,
    required this.rows,
    required this.onToggle,
    required this.onToggleAll,
    required this.onPickCandidate,
    required this.onEditPrice,
    required this.onApply,
    required this.onRestart,
    required this.onIgnoreGaps,
    required this.priceListMode,
    required this.onPriceListChanged,
    this.error,
    this.offerCount = 0,
    this.offerCompanies = 0,
    this.noCoverage = false,
    this.gapsIgnored = false,
    this.onEditOffers,
  });

  /// أقرّ المستخدم أن يمضي رغم الثغرات — فتُطوى اللافتة ولا تُعاد.
  ///
  /// الحالة في الصفحة لا هنا: هذا المكوّن يُعاد بناؤه مع كل تبديل
  /// تحديد، وقرارُ المستخدم يجب أن ينجو من ذلك.
  final bool gapsIgnored;

  final VoidCallback onIgnoreGaps;

  /// الملف نشرة أسعار — فكل صنفٍ مسعَّرٍ بند عرض.
  final bool priceListMode;
  final ValueChanged<bool> onPriceListChanged;

  final ImportJob job;
  final List<ImportRow> rows;
  final String? error;
  final void Function(int index) onToggle;
  final VoidCallback onToggleAll;
  final void Function(int index) onPickCandidate;
  final void Function(int index) onEditPrice;
  final VoidCallback onApply;
  final VoidCallback onRestart;

  /// كم عرضاً ستُنشئه المزامنة بالخطة الحالية.
  final int offerCount;

  /// كم شركةً في المحدَّد تحمل شرطاً تجارياً — قد تفوق [offerCount] حين
  /// يتعذّر الافتراض، وحينها يُقال إن العروض تحتاج ضبطاً.
  final int offerCompanies;

  /// يفتح شاشة إعداد العروض — `null` لملفٍ لا عرض فيه.
  final VoidCallback? onEditOffers;

  /// المستودع بلا مناطق تغطية — سببٌ يُقال باسمه لا يُلمَّح إليه.
  final bool noCoverage;

  @override
  State<_ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends State<_ReviewView> {
  _RowFilter _filter = _RowFilter.all;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final rows = widget.rows;

    final selected = rows.where((r) => r.selected && r.isActionable).toList();

    // بنود العرض المحدَّدة التي ينقصها سعرُها — ما لن يصل إلى أي عرض.
    final gaps = rows.where((r) => r.isOfferGap).length;

    // أصنافٌ مسعَّرة محدَّدة لا يراها الوكيل بنود عرض — مادّة نشرة
    // الأسعار. وبلا هذا العدد لا معنى للعرض عليه.
    final priceable =
        rows.where((r) => r.selected && r.isActionable && !r.needsPrice).length;

    // متى يُعرَض خيار نشرة الأسعار؟ حين لا يجد الوكيل بنداً تجارياً
    // واحداً وفي الملف أسعار — وهي حال أكثر ما يصل المستودعات. وحين
    // يكون الوضع مرفوعاً أصلاً، ليُطفأ.
    final offersFound = rows.where((r) => r.isOfferItem).length;
    final showPriceList =
        widget.priceListMode || (offersFound == 0 && priceable > 0);

    // عدّاد لكل خانة — من كل الصفوف لا من المحدَّد وحده: هذه إجابة
    // «ماذا في الملف»، وشريط الأسفل يُجيب «ماذا ستُزامن».
    final counts = {
      for (final f in _RowFilter.values)
        f: f == _RowFilter.all
            ? rows.length
            : rows.where(f.matches).length,
    };

    // ترتيب العرض حين تُفلتَر بنود العرض: مجموعةً بالشركة، والأكثر
    // بنوداً أولاً — فيرى المستخدم العرض الذي سيُنشأ كما سيُنشأ.
    final grouped = _filter == _RowFilter.offers;

    // الصفوف المعروضة مع فهارسها الأصلية: الفلترة تُغيّر ترتيب العرض،
    // والنداءات تُشير إلى مواضع في القائمة الكاملة — فلو مُرِّر فهرس
    // العرض لبدَّل المستخدمُ صفّاً غير الذي نقره.
    final visible = <int>[
      for (var i = 0; i < rows.length; i++)
        if (_filter.matches(rows[i])) i,
    ];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.lg),
            children: [
              _SummaryCard(summary: widget.job.summary, usage: widget.job.usage),

              if (widget.error != null) ...[
                const SizedBox(height: AppSpacing.md),
                _NoticeCard(
                  appIcon: AppIcons.alertTriangle,
                  tone: StatusTone.danger,
                  title: 'تعذّرت المزامنة',
                  body: widget.error!,
                ),
              ],

              // ── الثغرة تُقال قبل المزامنة لا بعدها ────────────────────
              // الوكيل يملأ ما يجده، وما لا يجده يبقى ناقصاً — وبندُ
              // عرضٍ بلا سعر يُطرَح في الخادم. فيُعرَض هنا بعدده
              // وبطريقَي حسمه: يُملأ أو يُترك. وكان يُطرَح صامتاً،
              // فيَعِد الشريطُ بعشرين بنداً ويصل منها سبعة عشر ولا أحد
              // يعرف أين ذهبت الثلاثة.
              // ── الملف نشرة أسعار؟ ────────────────────────────────────
              // الوكيل يعرف العرض بخصمٍ أو بونص، وهذا صحيح — لكنّ نشرة
              // الأسعار الصرف عرضٌ تامّ في السوق بلا علامةٍ يلتقطها.
              // فكان الملفّ الأشيع يُخرج صفر عروضٍ بلا أن يُقال لماذا.
              if (showPriceList) ...[
                const SizedBox(height: AppSpacing.md),
                _PriceListNotice(
                  enabled: widget.priceListMode,
                  itemCount: priceable,
                  onChanged: widget.onPriceListChanged,
                ),
              ],

              if (gaps > 0 && !widget.gapsIgnored) ...[
                const SizedBox(height: AppSpacing.md),
                _GapNotice(
                  count: gaps,
                  onFill: () =>
                      setState(() => _filter = _RowFilter.missingPrice),
                  onIgnore: widget.onIgnoreGaps,
                ),
              ],

              const SizedBox(height: AppSpacing.lg),

              // لوحة الحصيلة: كل بطاقةٍ عدّادٌ وفلترٌ في آن.
              //
              // الدمج مقصود — العدّاد يُثير السؤال («غير موجود: ١٢؟»)
              // والنقر يُجيبه في مكانه، بدل رقمٍ يُعرَض ثم يُترك المستخدم
              // يبحث عن أصحابه في قائمةٍ بمئات الأسطر.
              _FilterBoard(
                counts: counts,
                active: _filter,
                onPick: (f) => setState(
                  () => _filter = _filter == f ? _RowFilter.all : f,
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              AppSectionHeader(
                title: _filter == _RowFilter.all
                    ? 'الأصناف (${rows.length})'
                    : '${_filter.label} (${visible.length})',
                appIcon: AppIcons.pill,
                trailing: GestureDetector(
                  onTap: widget.onToggleAll,
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
              else if (visible.isEmpty)
                UiEmpty(
                  message: 'لا صنف في «${_filter.label}»',
                  description: 'جرّب تصنيفاً آخر أو اعرض الكل',
                  appIcon: AppIcons.pill,
                )
              else if (grouped)
                for (final group in _groupByCompany(rows, visible)) ...[
                  _CompanyHeader(
                    company: group.key,
                    count: group.value.length,
                  ),
                  for (final i in group.value)
                    Padding(
                      key: ValueKey(rows[i].id),
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _MatchRow(
                        row: rows[i],
                        onToggle: () => widget.onToggle(i),
                        onPickCandidate: () => widget.onPickCandidate(i),
                        onEditPrice: () => widget.onEditPrice(i),
                      ),
                    ),
                ]
              else
                for (final i in visible)
                  Padding(
                    key: ValueKey(rows[i].id),
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _Appear(
                      // ترتيب الظهور من موضع الصفّ في المعروض لا في
                      // القائمة الكاملة، وإلا تأخّر أولُ سطرٍ بعد الفلترة
                      // بمقدار فهرسه الأصلي فبدا وكأن شيئاً لا يحدث.
                      index: visible.indexOf(i),
                      child: _MatchRow(
                        row: rows[i],
                        onToggle: () => widget.onToggle(i),
                        onPickCandidate: () => widget.onPickCandidate(i),
                        onEditPrice: () => widget.onEditPrice(i),
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
                    onPressed: widget.onRestart,
                  ),
                ),

                // ما ستفعله العروض مقولٌ هنا، وتحريرها نقرةٌ لمن أراد.
                // كانت شاشةً تُفرَض بين المراجعة والمزامنة، فصارت خياراً.
                if (widget.onEditOffers != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: _OfferPlanChip(
                      count: widget.offerCount,
                      companies: widget.offerCompanies,
                      noCoverage: widget.noCoverage,
                      onTap: widget.onEditOffers!,
                    ),
                  ),
                ],

                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 2,
                  child: AppButton(
                    label: selected.isEmpty
                        ? 'لا شيء محدَّد'
                        : widget.offerCount > 0
                            ? 'مزامنة ${selected.length} صنفاً '
                                'و${widget.offerCount} عرضاً'
                            : 'مزامنة ${selected.length} صنفاً',
                    appIcon: AppIcons.check,
                    onPressed: selected.isEmpty ? null : widget.onApply,
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

/// خيار «الملف نشرة أسعار» — يُعرَض حين لا يجد الوكيل عرضاً وفي الملف أسعار.
///
/// الوكيل يعرف بند العرض بخصمٍ أو بونص، وهو صادق فيما يرى: ذانك علامتا
/// العرض. لكنّ أكثر ما يصل المستودعات نشرةُ أسعارٍ صرف — اسمٌ وسعرٌ
/// وشركة — وهي عرضٌ تامّ في السوق بلا علامةٍ تُلتقَط.
///
/// فكان الملفّ الأشيع يُخرج صفر عروضٍ ولا يُقال لصاحبه لماذا. وهذا
/// السؤال يُقال له، والجواب عنده: هو وحده يعرف أرفع نشرةَ أسعارٍ أم جرداً.
class _PriceListNotice extends StatelessWidget {
  const _PriceListNotice({
    required this.enabled,
    required this.itemCount,
    required this.onChanged,
  });

  final bool enabled;
  final int itemCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    final fg = enabled ? cs.primary : tk.hint;

    return Material(
      color: enabled ? tk.brandSurface : cs.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: () => onChanged(!enabled),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: enabled ? cs.primary.withValues(alpha: 0.6) : cs.outline,
              width: enabled ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              AppCheckbox(
                selection: enabled ? AppCheckState.all : AppCheckState.none,
              ),
              const SizedBox(width: AppSpacing.md),
              AppIcon(AppIcons.gift, size: 18, color: fg),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('هذا الملف نشرة أسعار',
                        style: context.text.labelMedium?.copyWith(color: fg)),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? 'كل صنفٍ مسعَّر بندُ عرض — $itemCount بنداً، '
                              'مجموعةً بشركاتها.'
                          : 'لا صنف في الملف يحمل خصماً أو بونصاً، فلا عرض '
                              'يُنشأ منه. وإن كانت هذه نشرة أسعارك فعلّمها '
                              'هنا، فتصير أصنافها الـ$itemCount بنودَ عرض.',
                      style: context.text.bodySmall,
                    ),
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

/// لافتةُ نقصٍ في الحقول اللازمة — بعددها وطريقَي حسمها.
///
/// الحقول اللازمة معروفةٌ عندنا لا عند الوكيل: بند العرض يلزمه سعرٌ
/// موجب، والباقي له افتراضٌ صحيح (الكمية واحد، والوحدة «علبة»). وشغل
/// الوكيل أن يجد ما في الملف — فإن لم يجد السعر فالنقص حقيقيّ لا خطأ
/// قراءة، ولا يُسدّ برقمٍ نخترعه.
///
/// فيُقال لصاحب الملف: هذا عددُ ما ينقص، إمّا تُدخله وإمّا تمضي بدونه.
/// وكان يُطرَح صامتاً في الخادم فلا يعرف أين ذهبت بنودُه.
///
/// وتخطيطها شريطٌ أفقي لا بطاقة: الشاشة عريضة، والعدّ والشرح والزرّان
/// يسعون في سطرٍ واحد — فلا تدفع قائمةَ الأصناف تحت الطيّة وهي المقصودة.
class _GapNotice extends StatelessWidget {
  const _GapNotice({
    required this.count,
    required this.onFill,
    required this.onIgnore,
  });

  final int count;
  final VoidCallback onFill;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final cs = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: tk.warningSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tk.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          AppIcon(AppIcons.alertTriangle, size: 20, color: tk.warning),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count ${count == 1 ? "بند عرضٍ ينقصه" : "بنود عرضٍ ينقصها"} '
                  'السعر',
                  style: context.text.labelMedium?.copyWith(color: tk.warning),
                ),
                const SizedBox(height: 2),
                Text(
                  'بند العرض يلزمه سعرٌ موجب — وهذه لم يجد الوكيل لها سعراً '
                  'في الملف. تدخل أسعارها فتدخل العروض، أو تمضي بدونها '
                  'فتبقى في «أدويتي» وحدها.',
                  style: context.text.bodySmall?.copyWith(color: cs.onSurface),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          SizedBox(
            width: 150,
            child: AppButton(
              label: 'تجاهلها',
              variant: AppButtonVariant.text,
              onPressed: onIgnore,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 190,
            child: AppButton(
              label: 'أدخل الأسعار',
              variant: AppButtonVariant.outline,
              appIcon: AppIcons.pencil,
              onPressed: onFill,
            ),
          ),
        ],
      ),
    );
  }
}

/// ملخّص خطة العروض في شريط المراجعة — ونقرةٌ تفتح تحريرها.
class _OfferPlanChip extends StatelessWidget {
  const _OfferPlanChip({
    required this.count,
    required this.companies,
    required this.onTap,
    this.noCoverage = false,
  });

  final int count;
  final int companies;
  final bool noCoverage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tk = context.tokens;

    // خطةٌ بلا عروضٍ رغم وجود شركات: الاستهداف لم يُعرَف بعد، والمزامنة
    // ستسأل عنه. يُقال الآن لا عندها.
    final needsSetup = count == 0 && companies > 0;
    final fg = needsSetup ? tk.warning : cs.primary;

    return Material(
      color: needsSetup ? tk.warningSurface : tk.brandSurface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(needsSetup ? AppIcons.alertTriangle : AppIcons.gift,
                  size: 18, color: fg),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  needsSetup
                      ? (noCoverage
                          ? 'حدّد مناطق تغطيتك أولاً'
                          : 'العروض تحتاج ضبطاً')
                      : count == 0
                          ? 'بلا عروض'
                          : '$count عروض جاهزة',
                  style: context.text.labelMedium?.copyWith(color: fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppIcon(AppIcons.pencil, size: 14, color: fg),
            ],
          ),
        ),
      ),
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

/// يجمع الفهارس المعروضة بالشركة، الأكثر بنوداً أولاً.
///
/// الشركة هي وحدة التجميع لأنها وحدة التفاوض: المستودع يتّفق مع شركةٍ
/// على شروطٍ فتسري على أصنافها، والعرض يُنشأ لها لا لصنفٍ منفرد. فرؤية
/// البنود مجموعةً هنا هي رؤيةُ العروض قبل إنشائها.
List<MapEntry<String, List<int>>> _groupByCompany(
    List<ImportRow> rows, List<int> visible) {
  final byCompany = <String, List<int>>{};

  for (final i in visible) {
    final company = rows[i].company?.trim() ?? '';
    byCompany.putIfAbsent(company.isEmpty ? 'بلا شركة' : company, () => [])
        .add(i);
  }

  final groups = byCompany.entries.toList();

  // «بلا شركة» آخراً: لا عرض يُنشأ لها غالباً، فلا تتصدّر ما يُنشأ.
  groups.sort((a, b) {
    final aUnnamed = a.key == 'بلا شركة';
    final bUnnamed = b.key == 'بلا شركة';
    if (aUnnamed != bUnnamed) return aUnnamed ? 1 : -1;
    return b.value.length.compareTo(a.value.length);
  });

  return groups;
}

/// ترويسة مجموعة شركة داخل قائمة المراجعة.
class _CompanyHeader extends StatelessWidget {
  const _CompanyHeader({required this.company, required this.count});

  final String company;
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;

    return Padding(
      padding: const EdgeInsets.only(
          top: AppSpacing.sm, bottom: AppSpacing.sm),
      child: Row(
        children: [
          AppIcon(AppIcons.warehouse, size: 16, color: cs.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(company,
                style: context.text.labelLarge?.copyWith(color: cs.primary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          StatusBadge(label: '$count بنداً', tone: StatusTone.brand),
        ],
      ),
    );
  }
}

/// لوحة التصنيفات — عدّادٌ وفلترٌ في بطاقةٍ واحدة.
class _FilterBoard extends StatelessWidget {
  const _FilterBoard({
    required this.counts,
    required this.active,
    required this.onPick,
  });

  final Map<_RowFilter, int> counts;
  final _RowFilter active;
  final void Function(_RowFilter) onPick;

  @override
  Widget build(BuildContext context) {
    // الخانات الفارغة تُطرح: «يلزم تأكيد: ٠» ليس خبراً، ووجوده يُزاحم
    // ما يعني المستخدم. و«الكل» تبقى دائماً لأنها طريق العودة.
    final shown = [
      // الثغرة أولاً حين توجد: هي وحدها ما يحتاج يداً قبل المزامنة،
      // وما عداها خبرٌ يُقرأ. وتقديمُ ما يُطلَب على ما يُعلَم قاعدةٌ
      // لا ترتيبَ ذوق.
      _RowFilter.missingPrice,

      // ثم بنود العرض: هي الخبر الجديد في الملف، وهي ما يقود إلى خطوة
      // إنشاء العروض.
      _RowFilter.offers,
      _RowFilter.newItem,
      _RowFilter.priceUpdate,
      _RowFilter.needsConfirm,
      _RowFilter.notFound,
    ].where((f) => (counts[f] ?? 0) > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── صفٌّ واحد على سطح المكتب ───────────────────────────────────
        // كانت عمودين ثابتين، فتنزل الست بطاقات في ثلاثة صفوف تأكل نصف
        // الشاشة وتدفع قائمة الأصناف تحت الطيّة — وهي المقصودة. والشاشة
        // عريضة تسعهنّ في سطر، فيُقرأ الملخّص كلّه بنظرةٍ واحدة.
        LayoutBuilder(
          builder: (context, constraints) {
            // بطاقةٌ لكل ٢٠٠ بكسل: أضيق منها يقطع «خارج الكتالوج» سطرين.
            final columns =
                (constraints.maxWidth / 200).floor().clamp(2, shown.length);

            return Column(
              children: [
                for (var i = 0; i < shown.length; i += columns) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      for (var j = i; j < i + columns; j++) ...[
                        if (j > i) const SizedBox(width: AppSpacing.sm),
                        // مكانٌ خالٍ لا بطاقةٌ ممدودة حين لا يكتمل الصفّ:
                        // المدّ يجعل الأخيرة ضعف أخواتها فتبدو أهمّ بلا
                        // سبب.
                        Expanded(
                          child: j < shown.length
                              ? _CountTile(
                                  value: counts[shown[j]] ?? 0,
                                  label: shown[j].label,
                                  icon: _iconFor(shown[j]),
                                  tone: shown[j].tone,
                                  active: active == shown[j],
                                  onTap: () => onPick(shown[j]),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            );
          },
        ),
        if (active != _RowFilter.all) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              AppFilterChip(
                label: '${active.label} (${counts[active] ?? 0})',
                onRemoved: () => onPick(active),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('من ${counts[_RowFilter.all] ?? 0} صنفاً',
                  style: context.text.labelSmall
                      ?.copyWith(color: context.tokens.hint)),
            ],
          ),
        ],
      ],
    );
  }

  static AppIcons _iconFor(_RowFilter f) => switch (f) {
        _RowFilter.offers => AppIcons.gift,
        _RowFilter.missingPrice => AppIcons.alertTriangle,
        _RowFilter.newItem => AppIcons.plus,
        _RowFilter.priceUpdate => AppIcons.tag,
        _RowFilter.needsConfirm => AppIcons.alertTriangle,
        _RowFilter.notFound => AppIcons.x,
        _RowFilter.all => AppIcons.pill,
      };
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.tone,
    this.active = false,
    this.onTap,
  });

  /// البطاقة المفعَّلة تُميَّز بحدٍّ أعرض — لا بلونٍ آخر، فاللون يحمل
  /// معنى التصنيف أصلاً وتبديله يُضيّعه.
  final bool active;
  final VoidCallback? onTap;

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

    final tile = Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: fg.withValues(alpha: active ? 0.9 : 0.2),
          width: active ? 1.6 : 1,
        ),
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

    if (onTap == null) return tile;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: tile,
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, this.usage = const ImportUsage()});
  final ImportSummary summary;
  final ImportUsage usage;

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

          // الفاصل تابعٌ للسطر: إظهاره فوق فراغٍ يترك خطّاً معلّقاً
          // في آخر البطاقة بلا ما يفصله عمّا بعده.
          if (usage.reported) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            _UsageLine(usage: usage),
          ],
        ],
      ),
    );
  }
}

/// مصروف التحليل من وحدات النموذج — إدخالاً وإخراجاً.
///
/// يُعرَض لأن الحصّة المجانية محدودة وصاحب المستودع من يدفع ثمن تجاوزها.
/// والشقّان مفصولان لأن علاجهما مختلف: الإدخال يُخفَّض بملفٍ أصغر أو
/// أعمدةٍ أقلّ، والإخراج بعدد الأصناف المستخرجة — وجمعُهما في رقمٍ واحد
/// يُخفي أيّهما ارتفع.
class _UsageLine extends StatelessWidget {
  const _UsageLine({required this.usage});
  final ImportUsage usage;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;

    // خادمٌ لا يُبلّغ عن المصروف أصلاً: لا سطر. ادّعاء «بلا مصروف» هنا
    // كذبٌ — الغياب جهلٌ بالرقم لا علمٌ بأنه صفر.
    if (!usage.reported) return const SizedBox.shrink();

    // صفرٌ صريح خبرٌ طيّب: الملف قُرئ من ترويسته مباشرةً بلا نموذج،
    // فلم يُصرَف منه شيء. وقولُه خيرٌ من إخفاء السطر.
    if (usage.isFree) {
      return Row(
        children: [
          AppIcon(AppIcons.check, size: 14, color: tk.success),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'قُرئ الملف مباشرةً بلا استدعاء النموذج — بلا مصروف',
              style: context.text.labelSmall?.copyWith(color: tk.success),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        AppIcon(AppIcons.info, size: 14, color: tk.hint),
        const SizedBox(width: AppSpacing.sm),
        Text('مصروف التحليل',
            style: context.text.labelSmall?.copyWith(color: tk.hint)),
        const Spacer(),
        _UsageChip(
          label: 'إدخال',
          value: usage.inputTokens,
          tone: StatusTone.neutral,
        ),
        const SizedBox(width: AppSpacing.xs),
        _UsageChip(
          label: 'إخراج',
          value: usage.outputTokens,
          tone: StatusTone.info,
        ),
      ],
    );
  }
}

class _UsageChip extends StatelessWidget {
  const _UsageChip({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final int value;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final (fg, bg) = tone == StatusTone.info
        ? (context.colors.primary, tk.brandSurface)
        : (context.colors.onSurfaceVariant, context.colors.surfaceContainerHighest);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ',
              style: context.text.labelSmall?.copyWith(color: fg)),
          Text(_compact(value),
              style: context.text.labelSmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  /// آلافٌ مختصرة: «١٢٬٤٠٠» أطول من أن يُقرأ بطرف العين، و«12.4k» يكفي
  /// للمقارنة بين ملفٍ وآخر وهو كلّ المقصود من الرقم هنا.
  static String _compact(int v) => v < 1000
      ? '$v'
      : '${(v / 1000).toStringAsFixed(v < 10000 ? 1 : 0)}k';
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
      // لم يعد عطلاً بل وصفاً: الصنف يُضاف باسمه كما ورد في الملف،
      // ونبرتُه تحذيرٌ لا خطر — فالمستخدم يُراجعه ولا يُمنَع منه.
      ImportMatch.notFound => ('يُضاف باسمه', StatusTone.warning),
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
                // Wrap لا Row: الشروط التجارية تُضاف إلى شارة الحالة،
                // وصفٌّ بخصمٍ وبونصٍ ومرشّحين يتجاوز عرض السطر فيفيض.
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(label: label, tone: tone),

                    // ما يجعل الصفّ بند عرض — يُعرَض على الصفّ نفسه لا
                    // في شاشةٍ أخرى: المستخدم يُقرّر ضمَّه إلى العرض وهو
                    // يراه، لا بعد أن ينتقل.
                    if ((row.discountPercentage ?? 0) > 0)
                      StatusBadge(
                        label: 'خصم ${_num(row.discountPercentage!)}٪',
                        tone: StatusTone.info,
                      ),
                    if (row.bonusLabel != null)
                      BonusBadge(label: 'بونص ${row.bonusLabel}'),

                    if (row.candidates.length > 1)
                      GestureDetector(
                        onTap: onPickCandidate,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
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
    this.publishing = false,
    this.publishFailed = const [],
  });

  final ImportReport report;
  final VoidCallback onDone;
  final VoidCallback onAgain;

  /// نشر العروض جارٍ الآن.
  final bool publishing;

  /// ما تعذّر نشره — بأسمائه.
  final List<String> publishFailed;

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

        // ── العروض المُنشأة ──────────────────────────────────────────
        // تُعرَض قبل الأعطال لأنها الخبر الأهمّ: شيءٌ جديد صار موجوداً،
        // ويُقال صراحةً إنه مسوّدة حتى لا يُظنّ أنه بلغ الصيدليات.
        if (report.offers.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(AppIcons.gift, size: 18, color: context.colors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text('أُنشئ ${report.offers.length} عرضاً',
                          style: context.text.labelLarge),
                    ),
                    if (publishing)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              context.colors.primary),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),

                // حالة النشر تُقال في موضعها: «أُنشئ» وحدها كانت تترك
                // السؤال معلّقاً — أوصلت الصيدليات أم لا؟
                Text(
                  publishing
                      ? 'يَنشرها الآن…'
                      : publishFailed.isEmpty
                          ? 'نُشرت — تراها الصيدليات في مناطق استهدافك'
                          : 'نُشر ${report.offers.length - publishFailed.length} '
                              'من ${report.offers.length}',
                  style: context.text.bodySmall?.copyWith(
                    color: publishFailed.isEmpty
                        ? context.tokens.success
                        : context.tokens.warning,
                  ),
                ),
                if (publishFailed.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'تعذّر نشر: ${publishFailed.join(' · ')} — انشرها من شاشة '
                    'العروض',
                    style: context.text.labelSmall
                        ?.copyWith(color: context.tokens.warning),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                for (final o in report.offers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(o.title,
                              style: context.text.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        StatusBadge(
                          label: '${o.itemCount} بنداً',
                          tone: StatusTone.neutral,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'كلّها «مسوّدة» — افتح شاشة العروض لمراجعتها ونشرها.',
                  style: context.text.labelSmall?.copyWith(color: tk.hint),
                ),
              ],
            ),
          ),
        ],

        if (report.offerFailures.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _NoticeCard(
            appIcon: AppIcons.alertTriangle,
            tone: StatusTone.warning,
            title: 'تعذّر إنشاء ${report.offerFailures.length} عرضاً',
            body: report.offerFailures
                .map((f) => '${f.company}: ${f.message}')
                .join('\n'),
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
