import 'dart:io';

import 'package:dio/dio.dart';

/// صنف العطل — ما يحدّد ما يُعرض للمستخدم وهل يُجدي إعادة المحاولة.
///
/// الفرق ليس تجميلياً: «تحقق من الحقول» نصيحةٌ صحيحة لخطأ تحقّق وكاذبةٌ
/// لانقطاع الشبكة. وزرّ «أعد المحاولة» مفيدٌ مع عطل عابر وعبثٌ مع بيانات
/// مرفوضة ما لم تتغيّر.
enum ApiErrorKind {
  /// لا اتصال، أو الخادم لم يُجب ضمن المهلة. العطل في الطريق لا في الطلب.
  network,

  /// الخادم ردّ بخمسمئة فما فوق — خلل عنده، لا شيء يُصلحه المستخدم.
  server,

  /// ما رفضه الخادم عن قصد: تحقّق، صلاحية، قاعدة عمل. الرسالة هنا ذات
  /// معنى وتُعرض كما جاءت.
  request,
}

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.kind = ApiErrorKind.request,
  });

  final String message;
  final int? statusCode;
  final ApiErrorKind kind;

  bool get isNetwork => kind == ApiErrorKind.network;
  bool get isServer => kind == ApiErrorKind.server;

  @override
  String toString() => message;

  static ApiException fromDio(DioException e) {
    if (_isNetworkFailure(e)) {
      return const ApiException(
        'تعذّر الاتصال بالخادم — تحقّق من اتصالك بالإنترنت',
        kind: ApiErrorKind.network,
      );
    }

    final status = e.response?.statusCode;
    final kind = status != null && status >= 500
        ? ApiErrorKind.server
        : ApiErrorKind.request;

    // رسالة الخادم عند الخمسمئة لا تُعرض: إمّا مبهمة وإمّا تُفشي داخله.
    // ونصُّنا هنا يقول ما يعني المستخدم — أن العطل ليس عنده.
    if (kind == ApiErrorKind.server) {
      return ApiException(
        'عطلٌ مؤقّت في الخادم — نعمل على إصلاحه، أعد المحاولة بعد قليل',
        statusCode: status,
        kind: ApiErrorKind.server,
      );
    }

    final body = e.response?.data;
    String msg = 'حدث خطأ، الرجاء المحاولة لاحقاً';
    if (body is Map<String, dynamic>) {
      // ASP.NET Core ProblemDetails: errors map contains field-level messages
      final errorsMap = body['errors'];
      if (errorsMap is Map && errorsMap.isNotEmpty) {
        final parts = <String>[];
        for (final entry in errorsMap.entries) {
          final value = entry.value;
          if (value is! List) continue;
          // اسم الحقل يُذكر مع رسالته: «القيمة مستعملة سابقاً» وحدها
          // تُحيّر — أيُّ قيمة؟ ومعها الحقل تصير قابلة للإصلاح.
          final field = _fieldName(entry.key.toString());
          for (final err in value) {
            final text = _toArabic(err.toString());
            parts.add(field == null ? text : '$field: $text');
          }
        }
        if (parts.isNotEmpty) {
          return ApiException(parts.join(' · '), statusCode: status);
        }
      }
      msg =
          body['message'] as String? ??
          body['title'] as String? ??
          body['error'] as String? ??
          msg;
      if (msg.startsWith('One or more validation')) {
        msg = 'بيانات غير صحيحة — تحقق من الحقول وأعد المحاولة';
      }
    }
    return ApiException(msg, statusCode: status);
  }

  /// عطلٌ قبل أن يصل الطلب أو قبل أن يكتمل الردّ.
  ///
  /// [DioExceptionType.unknown] تُفحَص لأن انقطاع الشبكة يصل غالباً
  /// مغلّفاً بها: [SocketException] أو [HandshakeException] في `error`.
  static bool _isNetworkFailure(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      case DioExceptionType.unknown:
        return e.error is SocketException || e.error is HandshakeException;
      default:
        return false;
    }
  }

  /// اسم الحقل بالعربية — أو بمفتاحه كما جاء إن لم يُعرَف.
  ///
  /// مفاتيح ProblemDetails تأتي بأسماء الخصائص في الخادم، وقد تحمل
  /// فهرساً («Offers[0].Title»): يُؤخذ آخر مقطعٍ منها فهو اسم الحقل.
  /// والمفاتيح العامة (`$`، `request`) لا تُضيف شيئاً فتُترك.
  static String? _fieldName(String key) {
    final last = key.split('.').last.replaceAll(RegExp(r'\[\d+\]'), '').trim();
    if (last.isEmpty || last == r'$' || _genericKeys.contains(last.toLowerCase())) {
      return null;
    }
    return _fieldNames[last.toLowerCase()] ?? last;
  }

  static const _genericKeys = {'request', 'model', 'body', 'dto', 'command'};

  static const _fieldNames = <String, String>{
    'title': 'العنوان',
    'name': 'الاسم',
    'displayname': 'الاسم',
    'company': 'الشركة',
    'price': 'السعر',
    'quantity': 'الكمية',
    'description': 'الوصف',
    'startsat': 'تاريخ البدء',
    'expiresat': 'تاريخ الانتهاء',
    'targetregions': 'مناطق الاستهداف',
    'email': 'البريد الإلكتروني',
    'username': 'اسم المستخدم',
    'phonenumber': 'رقم الهاتف',
    'phone': 'رقم الهاتف',
    'password': 'كلمة المرور',
    'catalogitemid': 'صنف الكتالوج',
  };

  static String _toArabic(String e) {
    if (e.contains('is already taken')) return 'اسم المستخدم مستخدم من قبل';
    if (e.contains('already taken')) return 'هذه القيمة مستخدمة بالفعل';
    if (e.contains('is invalid')) return 'تنسيق غير صحيح';
    if (e.toLowerCase().contains('password')) {
      return 'كلمة المرور لا تستوفي المتطلبات';
    }
    if (e.toLowerCase().contains('email') && e.contains('taken')) {
      return 'البريد الإلكتروني مسجّل مسبقاً';
    }
    return e;
  }

  static ApiException from(Object e) {
    if (e is ApiException) return e;
    if (e is DioException) return fromDio(e);
    if (e is SocketException || e is HandshakeException) {
      return const ApiException(
        'تعذّر الاتصال بالخادم — تحقّق من اتصالك بالإنترنت',
        kind: ApiErrorKind.network,
      );
    }
    return ApiException(e.toString());
  }
}
