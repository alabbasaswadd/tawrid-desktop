import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tawrid_app/core/network/api_client.dart';
import 'package:tawrid_app/core/network/api_endpoints.dart';
import 'package:tawrid_app/models/warehouse_medicine_models.dart';

final warehouseMedicineRepositoryProvider = Provider<WarehouseMedicineRepository>((ref) {
  return WarehouseMedicineRepository(ref.watch(apiClientProvider));
});

/// صفحةٌ من «أدويتي» مع عددها الكلّي.
/// شركةٌ في «أدويتي» وعددُ أصنافها — لشريحة الفلترة.
class MedicineCompany {
  const MedicineCompany({required this.name, required this.count});

  final String name;

  /// عدد أصناف هذه الشركة في المستودع كلّه — لا في المحمَّل.
  final int count;

  factory MedicineCompany.fromJson(Map<String, dynamic> j) => MedicineCompany(
        name: j['name'] as String? ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

class PagedMedicines {
  const PagedMedicines({
    required this.items,
    required this.total,
    required this.offset,
  });

  final List<WarehouseMedicine> items;

  /// كم صنفاً في المستودع كلّه — لا كم وصل.
  final int total;
  final int offset;

  /// هل خلف هذه الصفحة المزيد؟
  bool get hasMore => offset + items.length < total;
}

class WarehouseMedicineRepository {
  WarehouseMedicineRepository(this._api);
  final ApiClient _api;

  /// [search] يُمرَّر إلى الخادم لا يُطبَّق محلياً: القائمة مُرقَّمة، وما
  /// لم يصل من صفحاتها لا يمكن البحث فيه على الجهاز.
  Future<List<WarehouseMedicine>> getMine({
    String? search,
    int limit = 50,
    int offset = 0,
  }) async =>
      (await getMinePage(search: search, limit: limit, offset: offset)).items;

  /// صفحةٌ بعددها الكلّي — وهو ما كان يُرمى.
  ///
  /// `itemsOf` تأخذ العناصر وتُسقط غلاف الترقيم، فكان المستودع صاحب
  /// أربعمئة صنفٍ يقرأ «٥٠ دواءً في مستودعك»: رقمُ ما حُمِّل معروضاً
  /// كأنه رقم ما يملك. والعدد الكلّي شرطُ ترقيمٍ صادق أيضاً — بلا معرفة
  /// النهاية لا يُعرَف متى يتوقّف الجلب.
  Future<PagedMedicines> getMinePage({
    String? search,
    String? company,
    int limit = 50,
    int offset = 0,
  }) async {
    final raw = await _api.get(ApiEndpoints.whMedicines, queryParameters: {
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (company != null && company.trim().isNotEmpty) 'company': company.trim(),
      'limit': limit,
      'offset': offset,
    });

    final items = ApiClient.itemsOf(raw)
        .map((e) => WarehouseMedicine.fromJson(e as Map<String, dynamic>))
        .toList();

    return PagedMedicines(
      items: items,
      // خادمٌ يُعيد مصفوفةً عاريةً لا يعرف العدد الكلّي: يُفترض أن ما وصل
      // هو الكل، فلا يُعِد الترقيمُ طلبَ صفحةٍ لا وجود لها.
      total: ApiClient.totalOf(raw),
      offset: offset,
    );
  }

  /// «أدويتي» كلّها — للتصدير وحده.
  ///
  /// الشاشة تُحمّل ستّين صنفاً وتزيد بالتمرير، وكان التصدير يكتب ما
  /// حُمِّل منها: فملفٌّ عنوانه «أدويتي» يخرج بستّين صنفاً من أربعمئة
  /// بلا أن يقول إنه ناقص — وهو أسوأ من تصديرٍ يفشل.
  ///
  /// ويحترم البحث والفلترة: من فلتر بشركةٍ ثم صدّر يريد تلك الشركة
  /// كاملةً لا المستودع كلّه.
  Future<List<WarehouseMedicine>> getAllMine({
    String? search,
    String? company,
  }) async {
    final raw = await _api.get(ApiEndpoints.whMedicinesAll, queryParameters: {
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (company != null && company.trim().isNotEmpty) 'company': company.trim(),
    });

    return ApiClient.itemsOf(raw)
        .map((e) => WarehouseMedicine.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// شركاتُ «أدويتي» مع عدد أصناف كلٍّ منها.
  ///
  /// تُحسَب في الخادم على المستودع كلّه لا على المحمَّل: قائمةُ فلترةٍ
  /// ناقصة تُوهم بأنّ ما ليس فيها غيرُ موجود.
  Future<List<MedicineCompany>> getCompanies() async {
    final raw = await _api.get(ApiEndpoints.whMedicineCompanies);

    return ApiClient.itemsOf(raw)
        .map((e) => MedicineCompany.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// [price] اختياري عند الإضافة، فلا تلزم خطوة تسعير منفصلة لمن يملكه الآن.
  Future<WarehouseMedicine> add(String catalogItemId, {double? price}) async {
    final data = await _api.post(ApiEndpoints.whMedicines, data: {
      'catalogItemId': catalogItemId,
      'price': ?price,
    }) as Map<String, dynamic>;
    return WarehouseMedicine.fromJson(data);
  }

  /// تعديل السعر وحده. [price] فارغاً يسحب السعر: يختفي الصنف من البحث
  /// المقارن ويبقى في «أدويتي» — سحب التسعير ليس حذفاً.
  Future<WarehouseMedicine> setPrice(String id, double? price) async {
    final data = await _api.patch(
      ApiEndpoints.whMedicinePrice(id),
      data: {'price': price},
    ) as Map<String, dynamic>;
    return WarehouseMedicine.fromJson(data);
  }

  Future<void> remove(String id) => _api.delete(ApiEndpoints.whMedicineById(id));
}
