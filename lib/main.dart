import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tawrid_app/app/app.dart';
import 'package:tawrid_app/core/notifications/push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // لا تهيئة Firebase في نسخة سطح المكتب: `firebase_messaging` بلا تنفيذ
  // لويندوز، والتنبيه الفوري كان معطَّلاً هناك بحارسٍ صريح أصلاً — بينما
  // وجود `firebase_core` وحده كان يسحب Firebase C++ SDK (٩١٦ ميغابايت)
  // ويترجمه مع كل بناء جديد. راجع `push_service.dart` للتفصيل.

  // حاوية واحدة للتهيئة والتطبيق معاً: لو مرّرنا ProviderScope بلا حاوية
  // لصار لدينا نسختان من كل مزوّد — تُسجَّل الأجهزة في واحدة وتقرأ
  // الشاشات من الأخرى.
  final container = ProviderContainer();

  // تهيئة الإشعارات قبل الإقلاع. الدالة محروسة بالكامل: غياب التنبيه
  // الفوري يُعطّله ولا يمنع التطبيق من العمل.
  await container.read(pushServiceProvider).init();

  runApp(
    UncontrolledProviderScope(container: container, child: const TawridApp()),
  );
}
