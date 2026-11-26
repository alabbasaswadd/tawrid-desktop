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
  Future<ImportStarted> start({
    required List<int> bytes,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final data = await _api.postFile(
      ApiEndpoints.whImport,
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

  /// يكتب المختار في «أدويتي» ويُعيد ماذا أُضيف وماذا عُدِّل.
  ///
  /// الصفوف تُمرَّر صريحةً دائماً: لا يُكتب في مخزون أحدٍ ما لم يره ويوافق.
  /// [offers] عروضٌ تُنشأ مسوّدةً من بنود الملف، واحدٌ لكل شركة أقرّها
  /// المستخدم. فارغةً لا يُنشأ عرض — وهو الوضع الطبيعي لملف جردٍ صرف.
  Future<ImportReport> apply(
    String jobId, {
    required List<String> selectedRowIds,
    Map<String, double?> priceOverrides = const {},
    Map<String, String> catalogOverrides = const {},
    List<ImportOfferPlan> offers = const [],
  }) async {
    final data = await _api.post(
      ApiEndpoints.whImportApply(jobId),
      data: {
        'selectedRowIds': selectedRowIds,
        if (priceOverrides.isNotEmpty) 'priceOverrides': priceOverrides,
        if (catalogOverrides.isNotEmpty) 'catalogOverrides': catalogOverrides,
        if (offers.isNotEmpty)
          'offers': offers.map((o) => o.toJson()).toList(),
      },
    ) as Map<String, dynamic>;

    return ImportReport.fromJson(data);
  }
}
