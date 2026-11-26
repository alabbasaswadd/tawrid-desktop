// صياغة زمنية بأسلوب منشورات فيسبوك: "الآن"، "منذ N دقيقة"، "اليوم، HH:mm"،
// "الأمس، HH:mm"، ثم تاريخ كامل للأقدم. التاريخ لا يُعرَض كرقم خام إن كان
// اليوم — تحديداً كما طُلب.
//
// ── والمستقبل كالماضي ────────────────────────────────────────────────────
// كانت الدالّة تحسب `now.difference(dt)` وتفرّع على موجبه وحده. والفرق
// لتاريخٍ قادم سالب، و«سالبٌ أصغر من ستين» صادق دائماً — فكان كل تاريخٍ
// مستقبلي يُعرَض «الآن».
//
// وأثرُه لم يكن تجميلياً: شاشة العرض تكتب «ساري من كذا إلى ${expiresAt}»،
// فعرضٌ أمامه ثلاثون يوماً يُقرأ «إلى الآن» — يظنّ صاحبه أنه انتهى
// لحظةَ إنشائه، ويظنّه الصيدلي كذلك.
String formatSmartTimestamp(DateTime dateTime) {
  final dt = dateTime.isUtc ? dateTime.toLocal() : dateTime;
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.isNegative) return _ahead(dt, -diff, now);
  return _behind(dt, diff, now);
}

/// ما مضى — «الآن» و«منذ كذا».
String _behind(DateTime dt, Duration diff, DateTime now) {
  final time = _formatTime(dt);

  if (diff.inSeconds < 60) return 'الآن';
  if (diff.inMinutes < 60) {
    return 'منذ ${diff.inMinutes} ${_minuteWord(diff.inMinutes)}';
  }
  if (_isSameDay(dt, now)) return 'اليوم، $time';

  final yesterday = now.subtract(const Duration(days: 1));
  if (_isSameDay(dt, yesterday)) return 'الأمس، $time';

  if (diff.inDays < 7) {
    return 'منذ ${diff.inDays} ${_dayWord(diff.inDays)}';
  }

  return '${_date(dt)}، $time';
}

/// ما هو آتٍ — «بعد كذا» و«غداً».
///
/// مقابلةٌ لما مضى حرفاً بحرف: ما بعد أسبوعٍ تاريخٌ كامل، لأن «بعد ثلاثين
/// يوماً» يُحسَب ذهنياً ولا يُقرأ.
String _ahead(DateTime dt, Duration left, DateTime now) {
  final time = _formatTime(dt);

  if (left.inSeconds < 60) return 'الآن';
  if (left.inMinutes < 60) {
    return 'بعد ${left.inMinutes} ${_minuteWord(left.inMinutes)}';
  }
  if (_isSameDay(dt, now)) return 'اليوم، $time';

  final tomorrow = now.add(const Duration(days: 1));
  if (_isSameDay(dt, tomorrow)) return 'غداً، $time';

  if (left.inDays < 7) {
    return 'بعد ${left.inDays} ${_dayWord(left.inDays)}';
  }

  return '${_date(dt)}، $time';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// تمييز العدد في العربية — لا «١٢ دقائق».
///
/// القاعدة: الواحد مفرد، والاثنان مثنّى، ومن ثلاثةٍ إلى عشرة جمعُ قلّة،
/// وما جاوز العشرة يعود مفرداً منصوباً. وكان الكود يفرّق بين الواحد وما
/// سواه فحسب، فيُخرِج «١٢ دقائق» و«٢ أيام».
String _minuteWord(int n) => switch (n) {
      1 => 'دقيقة',
      2 => 'دقيقتين',
      >= 3 && <= 10 => 'دقائق',
      _ => 'دقيقة',
    };

String _dayWord(int n) => switch (n) {
      1 => 'يوم',
      2 => 'يومين',
      >= 3 && <= 10 => 'أيام',
      _ => 'يوماً',
    };

String _date(DateTime dt) {
  final y = dt.year.toString();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y/$m/$d';
}

String _formatTime(DateTime dt) {
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour < 12 ? 'ص' : 'م';
  return '$hour12:$minute $period';
}
