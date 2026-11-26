import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:tawrid_app/app/router/router.dart';
import 'package:tawrid_app/app/router/routes.dart';
import 'package:tawrid_app/core/constants/storage_keys.dart';
import 'package:tawrid_app/core/notifications/message_notifications.dart';
import 'package:tawrid_app/core/storage/app_secure_storage.dart';
import 'package:tawrid_app/repositories/device_repository.dart';

final _log = Logger();

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));

/// نسخة سطح المكتب من خدمة الإشعارات — بلا Firebase.
///
/// **لماذا ملفٌّ بلا FCM أصلاً:** التنبيه الفوري على ويندوز كان معطَّلاً
/// في النسخة الكاملة بحارسَين صريحين (`init` و`registerForSession` يعودان
/// فوراً على `TargetPlatform.windows`)، لأن `firebase_messaging` لا يملك
/// تنفيذاً لويندوز — والإشعارات هناك عبر `flutter_local_notifications`.
///
/// ومع ذلك كان مجرّد وجود `firebase_core` في الاعتمادات يُدرِجه في قائمة
/// إضافات ويندوز، فيسحب CMake حزمة **Firebase C++ SDK بحجم ٩١٦ ميغابايت**
/// ويترجمها في كل بيئة بناء جديدة — ثمنٌ كامل مقابل سطرٍ لا أثر له على
/// هذه المنصّة.
///
/// فهذه النسخة تحتفظ بنفس الواجهة العامّة وبنفس السلوك الذي كان يراه
/// مستخدم ويندوز فعلاً، وتُسقِط ما لم يكن يعمل لديه أصلاً. أندرويد و iOS
/// والويب تبقى على النسخة الكاملة بلا أي تغيير.
class PushService {
  PushService(this._ref);

  final Ref _ref;

  /// جاهزيةٌ لا تتحقّق هنا: لا FCM على سطح المكتب. تُقرأ من شاشات تُقرّر
  /// هل تعرض حالة «التنبيه الفوري مفعّل»، فتبقى صادقة.
  bool get isReady => false;

  /// لا رمز جهاز — ولا تسجيل له عند الخادم.
  String? get token => null;

  /// لا تهيئة على سطح المكتب. موجودة لأن `main` يستدعيها، فبقاؤها يُبقي
  /// نقطة الإقلاع واحدة لكل المنصّات.
  Future<void> init() async {}

  /// تسجيل الجهاز يحتاج رمز FCM، ولا رمز هنا.
  Future<void> registerForSession({required bool isWarehouse}) async {}

  /// إلغاء التسجيل يبقى عاملاً: الجهاز قد يكون سُجِّل من نسخة محمولة
  /// بنفس الحساب، وتركُ رمزه حيّاً يُبقي إشعارات حسابٍ خرج تصل إليه.
  Future<void> unregisterForSession({required bool isWarehouse}) async {
    final saved = await appSecureStorage.read(key: StorageKeys.fcmToken);
    if (saved == null || saved.isEmpty) return;

    try {
      await _ref
          .read(deviceRepositoryProvider)
          .unregister(isWarehouse: isWarehouse, token: saved);
    } catch (e) {
      // فشل الإلغاء لا يمنع الخروج: الخادم ينظّف الرموز الميتة لاحقاً.
      _log.w('[Push] تعذّر إلغاء تسجيل الجهاز: $e');
    }
    await appSecureStorage.delete(key: StorageKeys.fcmToken);
    await appSecureStorage.delete(key: StorageKeys.fcmTokenOwner);
  }

  /// تضبطها شاشة الدردشة عند الفتح وتمسحها عند الخروج. تبقى هنا لأن
  /// الشاشة تستدعيها بلا علمٍ بالمنصّة.
  void setOpenConversation(String? conversationId) {}

  /// انتقال الإشعار الذي أقلع منه التطبيق.
  ///
  /// يبقى عاملاً للإشعارات المحلّية: هذه يبنيها التطبيق بنفسه عبر
  /// `flutter_local_notifications` ولا علاقة لـ FCM بها، فحمولة الإقلاع
  /// تُسأل كما في النسخة الكاملة.
  Future<void> consumeLaunchNotification() async {
    final local = MessageNotifications.takeLaunchPayload();
    if (local == null) return;

    MessageNotifications.clear(local.conversationId).ignore();
    unawaited(_navigateToConversation(local.conversationId, local.title));
  }

  Future<void> _navigateToConversation(
    String conversationId,
    String title,
  ) async {
    // الجهة لا تأتي في الحمولة: الجهاز سُجّل لجهة واحدة، وهي المحفوظة.
    final owner = await appSecureStorage.read(key: StorageKeys.fcmTokenOwner);
    if (owner == null) return; // لا جلسة — لا شاشة تُفتح.

    final destination = owner == 'warehouse'
        ? TRoutes.whConversationDetail(conversationId, title)
        : TRoutes.phConversationDetail(conversationId, title);

    try {
      _ref.read(routerProvider).push(destination);
    } catch (e) {
      _log.w('[Push] تعذّر فتح المحادثة $conversationId: $e');
    }
  }

  void dispose() {}
}
