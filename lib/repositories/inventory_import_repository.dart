import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tawrid_app/core/network/api_client.dart';
import 'package:tawrid_app/core/network/api_endpoints.dart';
import 'package:tawrid_app/models/ai_import_models.dart';

final inventoryImportRepositoryProvider =
    Provider<InventoryImportRepository>((ref) {
  return InventoryImportRepository(ref.watch(apiClientProvider));
});

/// استيراد المخزون بالـ AI — كل العمل في الخادم.
///
/// الملف يُرفع كما هو، والخادم يقرؤه وينادي وكيل الـ AI ويطابق مع الكتالوج.
/// ولهذا لا قارئ Excel في التطبيق ولا مفتاح وكيل على الجهاز: مفتاحٌ في
/// تطبيقٍ موزَّع مفتاحٌ مكشوف.
class InventoryImportRepository {
  InventoryImportRepository(this._api);
  final ApiClient _api;

  /// يرفع الملف ويُنشئ المهمة. يعود فوراً — التحليل يجري خلفياً.
  ///
  /// [skipCatalogMatching] يتخطّى مطابقة الكتالوج الوطني، فتصير المزامنة
  /// مع المخزون والعروض وحدهما: كل صفٍّ يدخل «أدويتي» صنفاً حرّاً باسمه
  /// وعياره. ويُسقط ذلك مرحلةَ مطابقةٍ كاملة ونداءات مراجعتها.
  Future<ImportStarted> start({
    required List<int> bytes,
    required String fileName,
    bool skipCatalogMatching = false,
    void Function(int sent, int total)? onProgress,
  }) async {
    final data = await _api.postFile(
      skipCatalogMatching
          ? '${ApiEndpoints.whImport}?skipCatalogMatching=true'
          : ApiEndpoints.whImport,
      bytes: bytes,
      fileName: fileName,
      onProgress: onProgress,
    ) as Map<String, dynamic>;

    return ImportStarted.fromJson(data);
  }

  /// حالة المهمة. [includeRows] فارغاً عند متابعة التقدّم: استطلاعٌ متكرّر
  /// لا يحتاج مئات الصفوف في كل رد.
  Future<ImportJob> get(String jobId, {bool includeRows = true}) async {
    final data = await _api.get(
      ApiEndpoints.whImportById(jobId),
      queryParameters: {'includeRows': includeRows},
    ) as Map<String, dynamic>;

    return ImportJob.fromJson(data);
  }

  /// أحدث مهمة لم تنتهِ — يستأنف بها المستخدم بعد إغلاق الشاشة، فلا يظنّ
  /// أن عمله ذهب. تُعيد null إن لم توجد.
  Future<ImportJob?> active() async {
    final data = await _api.get(ApiEndpoints.whImportActive);
    return data is Map<String, dynamic> ? ImportJob.fromJson(data) : null;
  }

  /// يوقف مهمة جارية.
  ///
  /// إلغاءٌ حقيقي لا إغلاقٌ للشاشة: الخادم يوسمها ملغاةً فلا تُستأنف،
  /// ويقطع نداء الوكيل الجاري بدل انتظار انتهاء الدفعة. وهو آمنٌ بلا
  /// تراجع لأن لا شيء يُكتب في «أدويتي» قبل خطوة التطبيق.
  Future<ImportJob> cancel(String jobId) async {
    final data = await _api.post(ApiEndpoints.whImportCancel(jobId))
        as Map<String, dynamic>;
    return ImportJob.fromJson(data);
  }

  /// يُصحّح خريطة الأعمدة ويُعيد المهمة بصفوفها المقروءة من جديد.
  ///
  /// بلا نداء وكيل: الخلايا الخام محفوظةٌ في كل صفّ، والتصحيح قراءةٌ
  /// حتمية من عمودٍ يُسمّيه صاحب الملف. فهو فوريٌّ على سبعمئة صفّ.
  ///
  /// كل فهرسٍ فارغ يعني «اترك ما قرأه الوكيل» — لا «امسحه». ومن أراد
  /// الإفراغ يُمرّر [clearUnmapped].
  Future<ImportJob> remapColumns(
    String jobId, {
    int? name,
    int? price,
    int? company,
    int? quantity,
    int? unit,
    int? discount,
    int? bonus,
    int? strength,
    bool clearUnmapped = false,
  }) async {
    final data = await _api.post(
      ApiEndpoints.whImportRemap(jobId),
      data: {
        'name': ?name,
        'price': ?price,
        'company': ?company,
        'quantity': ?quantity,
        'unit': ?unit,
        'discount': ?discount,
        'bonus': ?bonus,
        'strength': ?strength,
        if (clearUnmapped) 'clearUnmapped': true,
      },
      receiveTimeout: const Duration(minutes: 3),
    ) as Map<String, dynamic>;

    return ImportJob.fromJson(data);
  }

  /// يكتب المختار في «أدويتي» ويُعيد ماذا أُضيف وماذا عُدِّل.
  ///
  /// الصفوف تُمرَّر صريحةً دائماً: لا يُكتب في مخزون أحدٍ ما لم يره ويوافق.
  /// ولا عروض هنا — تلك [createOffers] بعده.
  ///
  /// مهلته طويلةٌ عمداً: الكتابة تمرّ على كل صنفٍ مختار، وملفٌ بمئتي
  /// صنفٍ يأخذ دقائق. والمهلة العامة (ثلاثون ثانية) كانت تقطع الطلب
  /// والخادم ما زال يكتب — فيُسقِط الردّ لا العمل.
  Future<ImportReport> apply(
    String jobId, {
    required List<String> selectedRowIds,
    Map<String, double?> priceOverrides = const {},
    Map<String, String> catalogOverrides = const {},
  }) async {
    final data = await _api.post(
      ApiEndpoints.whImportApply(jobId),
      data: {
        'selectedRowIds': selectedRowIds,
        if (priceOverrides.isNotEmpty) 'priceOverrides': priceOverrides,
        if (catalogOverrides.isNotEmpty) 'catalogOverrides': catalogOverrides,
      },
      receiveTimeout: const Duration(minutes: 20),
    ) as Map<String, dynamic>;

    return ImportReport.fromJson(data);
  }

  /// يُنشئ العروض من مهمةٍ طُبِّقت — واحدٌ لكل شركة أقرّها المستخدم.
  ///
  /// نداءٌ مستقلّ بعد [apply] لا حقلٌ فيه. وكان حقلاً فيه ولم يصل قطّ:
  /// جسم الطلب في الخادم لم يكن يحمل العروض، فكانت تُرسَل وتُسقَط بصمت —
  /// ولم يُنشأ عرضٌ واحد من استيراد قطّ.
  ///
  /// وفصلُه يُصلح أكثر: ردُّ التطبيق يعود حين يفرغ المخزون، وما تعذّر من
  /// العروض يُعاد طلبه وحده بلا إعادة رفع الملف.
  ///
  /// ليس آمناً للتكرار: نداؤه مرّتين يُنشئ عرضين. الشاشة تُناديه مرّةً
  /// لكل تطبيق.
  Future<ImportOffersResult> createOffers(
    String jobId,
    List<ImportOfferPlan> offers,
  ) async {
    final data = await _api.post(
      ApiEndpoints.whImportOffers(jobId),
      data: {'offers': offers.map((o) => o.toJson()).toList()},
      receiveTimeout: const Duration(minutes: 10),
    ) as Map<String, dynamic>;

    return ImportOffersResult.fromJson(data);
  }
}
