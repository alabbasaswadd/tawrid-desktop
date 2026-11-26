/// صياغة المبالغ.
///
/// الأرقام هنا تُقرأ داخل قرار شراء، و«530000» بلا فواصل تُقرأ خطأً — لذا
/// فاصل آلاف دائماً.
///
/// والكسور **تتبع العملة** لا ذوق الشاشة: الليرة لا تُكسَّر عملياً فتُعرض
/// صحيحة، أما الدولار فنشرات المستودعات تُسعّر به بمنزلتين (2.25 · 0.87 ·
/// 0.35) — وتدويرها يحوّل 0.35 إلى «صفر» و0.87 إلى «واحد»، فيصير السعر
/// المعروض سعراً آخر. لذلك لا يُصاغ مبلغ بلا عملة: الدوالّ كلها تطلبها.
library;

/// عدد المنازل العشرية المعروضة لكل عملة.
///
/// عملة لا نعرفها تأخذ منزلتين لا صفراً: الكسر الزائد يُقرأ، أما المبتور
/// فيكذب.
int currencyDecimals(String code) => switch (code.toUpperCase()) {
  'SYP' => 0,
  _ => 2,
};

/// «530,000» · «2.25» — الرقم وحده بمنازل عملته وبفاصل آلاف.
/// لجداول تحمل العملة في ترويستها (ومنها جدول الـ PDF) فلا تكرّرها كل سطر.
String formatAmount(num value, String currency) =>
    _group(value, currencyDecimals(currency));

/// «530,000 ل.س» · «2.25 $» — المبلغ مع رمز عملته.
String formatMoneyWith(num value, String currency) =>
    '${formatAmount(value, currency)} ${currencySymbol(currency)}';

/// رمز العملة بالعربية؛ ما لا يُعرف يُعرض كما جاء من الخادم.
String currencySymbol(String code) => switch (code.toUpperCase()) {
  'SYP' => 'ل.س',
  'USD' => '\$',
  'EUR' => '€',
  'TRY' => '₺',
  _ => code,
};

/// اسم العملة كاملاً — لقوائم الاختيار وشاشات الإعدادات.
String currencyName(String code) => switch (code.toUpperCase()) {
  'SYP' => 'ليرة سورية',
  'USD' => 'دولار أمريكي',
  'EUR' => 'يورو',
  'TRY' => 'ليرة تركية',
  _ => code,
};

/// صياغة كمية (عبوات/قطع) لا مبلغ: حتى ٣ منازل بلا أصفار لاحقة —
/// «12» و«2.5» لا «12.000». الكميات المجانية قد تأتي كسرية من شريحة بونص.
String formatQuantity(num value) {
  final rounded = (value * 1000).round() / 1000;
  if (rounded == rounded.roundToDouble()) return _group(rounded, 0);
  return _group(rounded, 3).replaceFirst(RegExp(r'0+$'), '');
}

/// يقرأ رقماً كتبه مستخدمٌ عربي — بأي فاصلةٍ وبأي أرقام.
///
/// `double.tryParse` وحده لا يكفي هنا، وثلاثةُ أشياء كانت تُسقِط الإدخال:
///
/// **الأرقام العربية-الهندية**: من يكتب «٢٫٢٥» بلوحة مفاتيح عربية يُنتج
/// محارف لا يعرفها المحلّل، فيعود `null` ويُقال له «أدخل سعراً أكبر من
/// صفر» — وقد أدخله.
///
/// **الفاصلة العشرية**: الكود السابق كان `replaceAll(',', '')` يحذفها
/// بوصفها فاصل آلاف. فمن كتب «٣,٥» قاصداً ثلاثةً ونصفاً حُفظ له «٣٥» —
/// سعرٌ عشرةُ أضعاف ما أراد، يذهب إلى الصيدليات بلا أن يُنبَّه.
///
/// **والفاصلة نفسها تحتمل المعنيين**، فتُحسَم بقرينة: «12,500» بثلاث
/// خاناتٍ بعدها فاصلُ آلاف، و«3,5» فاصلةٌ عشرية. وحين تجتمع مع النقطة
/// فآخرُهما هو العشري وما قبله تجميع.
///
/// يُعيد `null` لما لا يُقرأ رقماً — والفارغ منه.
double? parseDecimalInput(String input) {
  if (input.trim().isEmpty) return null;

  final buffer = StringBuffer();
  for (final ch in input.trim().split('')) {
    final code = ch.codeUnitAt(0);

    // ٠-٩ (عربية-هندية) و ۰-۹ (فارسية) ← لاتينية.
    if (code >= 0x0660 && code <= 0x0669) {
      buffer.write(String.fromCharCode(code - 0x0660 + 0x30));
    } else if (code >= 0x06F0 && code <= 0x06F9) {
      buffer.write(String.fromCharCode(code - 0x06F0 + 0x30));
    } else if (ch == '٫') {
      // الفاصلة العشرية العربية.
      buffer.write('.');
    } else if (ch == '-' || ch == '.' || ch == ',' ||
        (code >= 0x30 && code <= 0x39)) {
      buffer.write(ch);
    }
    // وما عداه — فواصل التجميع العربية (٬ و ،) والمسافات ورموز العملة
    // والحروف — يُطرح.
  }

  var s = buffer.toString();
  if (s.isEmpty) return null;

  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');

  if (lastDot >= 0 && lastComma >= 0) {
    // اجتمعا: آخرُهما هو العشري، والآخر تجميعٌ يُطرَح.
    final decimal = lastComma > lastDot ? ',' : '.';
    final group = decimal == ',' ? '.' : ',';

    s = s.replaceAll(group, '');
    final at = s.lastIndexOf(decimal);
    s = '${s.substring(0, at).replaceAll(decimal, '')}'
        '.'
        '${s.substring(at + 1)}';
  } else if (lastComma >= 0) {
    // فاصلةٌ واحدة بثلاث خاناتٍ بعدها وأرقامٌ قبلها = فاصل آلاف
    // («12,500»). وما عداه عشريّ («3,5» و«,5»).
    final after = s.length - lastComma - 1;
    final grouping = s.indexOf(',') != lastComma ||
        (after == 3 && lastComma > 0);
    s = grouping ? s.replaceAll(',', '') : s.replaceFirst(',', '.');
  }

  return double.tryParse(s);
}

/// يكتب رقماً في حقل إدخالٍ بلا أصفارٍ لاحقة ولا فواصل آلاف.
///
/// الفواصل تُطرح لأن ما يُكتب هنا يُقرأ ثانيةً، والأصفار اللاحقة لأن
/// «2.00» يُغري بالتحرير الخاطئ. وأهمُّ من ذلك أنه **لا يُدوّر**:
/// الحقل كان يُملأ بـ`toStringAsFixed(0)`، فصنفٌ سعره ٢٫٢٥ يُفتَح حواره
/// فيظهر «2» — ويكفي أن يضغط صاحبه «حفظ» ليصير سعره اثنين.
String formatForInput(num value) {
  final rounded = (value * 1000).round() / 1000;
  if (rounded == rounded.roundToDouble()) {
    return rounded.toStringAsFixed(0);
  }
  return rounded
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

// ─────────────────────────────────────────────────────────────────────

String _group(num value, int decimals) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(decimals);

  final dot = fixed.indexOf('.');
  final whole = dot < 0 ? fixed : fixed.substring(0, dot);
  final fraction = dot < 0 ? '' : fixed.substring(dot);

  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }

  return '${negative ? '-' : ''}$buf$fraction';
}
