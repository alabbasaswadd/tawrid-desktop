import 'money.dart';

/// حدود حقول العرض — نسخةُ العميل من `CreateSalesOfferValidator`.
///
/// ── لماذا موضعٌ واحد؟ ───────────────────────────────────────────────────
/// الحدّ نفسه كان يُكتب مرّتين في الشاشة: مرّةً في `validator` الحقل
/// (تُلوّن الحقل أثناء الكتابة) ومرّةً في حارس الإرسال (يقرأ النموذج لأن
/// الحقل لا يكون في الشجرة وقتها). ونسختان لحدٍّ واحد تفترقان عند أول
/// تعديل — فيمرّ ما يردّه الخادم، أو يُردّ ما يقبله.
///
/// وكلّها تُعيد **رسالةً عربية أو `null`**: وهي صيغة `FormFieldValidator`
/// نفسها، فتصلح للاثنين بلا غلاف.
///
/// ── ولماذا تُكرَّر هنا وهي في الخادم؟ ──────────────────────────────────
/// لأن رحلةً إلى الخادم لتكتشف خطأً تعرفه الشاشة هدرٌ، ولأن رسالة الخادم
/// لا تسمّي الصنف — تقول «نسبة الحسم بين صفر ومئة» ولا تقول في أيّ
/// صنفٍ من عشرين. والحدود هنا تطابق مدقّق الخادم رقماً برقم.
class OfferRules {
  const OfferRules._();

  /// سقف مدّة السداد — يطابق `MaxPaymentPeriodDays` في مدقّق الخادم.
  static const int maxPaymentPeriodDays = 730;

  /// سقفُ حوار الكمية حين يكون الصنف «كمية مفتوحة» (أي كميته صفر).
  ///
  /// الصفر عند المستودع يعني «غير محدَّد»، وشاشة الصيدلي تقرؤه كذلك —
  /// فسقفُ واحدٍ كان يكذّب تلميحه «كمية مفتوحة» ويمنعه من طلب علبتين.
  static const int openQuantityCap = 9999;

  /// سعر الوحدة — مطلوبٌ وموجب.
  static String? unitPrice(String? raw) {
    final value = parseDecimalInput(raw ?? '');
    return value == null || value <= 0 ? 'سعرٌ أكبر من صفر' : null;
  }

  /// الكمية المتاحة — فارغةٌ مسموحة متى كانت [open].
  ///
  /// الصفر يُرسَل للخادم ويعني «مفتوحة»، والسالب لا معنى له.
  static String? quantity(String? raw, {required bool open}) {
    if (open) return null;
    final value = parseDecimalInput(raw ?? '');
    return value == null || value <= 0 ? 'كمية غير صالحة' : null;
  }

  /// نسبة الحسم — اختيارية، وبين صفر ومئة متى وُجدت.
  ///
  /// بلا حدٍّ كانت تُضرب في سعر السلّة: `net = السعر × (١ − الحسم/١٠٠)`.
  /// فحسمُ ١٥٠٪ يجعله سالباً، والسالب يرفعه فوق المعلَن.
  static String? discount(String? raw) => _optionalPercentage(raw);

  /// نسبة الدفع المقدَّم — اختيارية، وبين صفر ومئة متى وُجدت.
  static String? upfrontPercentage(String? raw) => _optionalPercentage(raw);

  /// مدّة السداد بالأيام — اختيارية، وصحيحةٌ غير سالبة متى وُجدت.
  static String? paymentPeriodDays(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;

    final days = int.tryParse(text);
    return days == null || days < 0 || days > maxPaymentPeriodDays
        ? 'بين ٠ و$maxPaymentPeriodDays يوماً'
        : null;
  }

  /// كمية دواء الهديّة — مطلوبةٌ موجبة متى اختير دواءٌ لها.
  ///
  /// اسمٌ بلا كمية نصفُ هديّة: تُعرض على الصيدلي ناقصةً فلا يعرف ماذا ينال.
  static String? bonusQuantity(String? raw, {required bool hasMedicine}) {
    if (!hasMedicine) return null;
    final value = parseDecimalInput(raw ?? '');
    return value == null || value <= 0 ? 'كميةٌ أكبر من صفر' : null;
  }

  /// الوحدة — مطلوبة، والفراغ ليس وحدة.
  static String? unit(String? raw) =>
      (raw ?? '').trim().isEmpty ? 'مطلوب' : null;

  static String? _optionalPercentage(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;

    final value = parseDecimalInput(text);
    return value == null || value < 0 || value > 100 ? 'بين ٠ و١٠٠' : null;
  }
}
