import 'package:flutter_riverpod/flutter_riverpod.dart';

/// عدّادٌ يرتفع كلّما تغيّر مخزون المستودع من خارج شاشته.
///
/// شاشتا «أدويتي» و«العروض» فرعان في `StatefulShellRoute`، وأفرعُه تبقى
/// حيّةً في `IndexedStack`: تُحمَّل مرّةً في `initState` ثم لا يُعاد
/// بناؤها عند العودة إليها. فاستيرادٌ يكتب مئتي صنفٍ في الخادم لا يُغيّر
/// شيئاً أمام العين — القائمة المعروضة هي التي جُلبت قبله، ويبدو الاستيراد
/// كأنه لم يحدث وقد حدث.
///
/// ورقمٌ يُرفَع هنا أهون من تحويل الشاشتين إلى مزوّدات: من كتب يرفعه،
/// ومن يعرض يسمعه فيُحدِّث نفسه بهدوء.
class InventoryRevision extends Notifier<int> {
  @override
  int build() => 0;

  /// يُعلن أن المخزون تغيّر — تُناديها الشاشة التي كتبت.
  void bump() => state++;
}

final inventoryRevisionProvider =
    NotifierProvider<InventoryRevision, int>(InventoryRevision.new);
