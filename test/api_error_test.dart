// ترجمة أخطاء الخادم إلى رسائل تُقرأ وتُصلح.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tawrid_app/core/network/api_exception.dart';

DioException _err(int status, Object? body) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
        data: body,
      ),
    );

void main() {
  group('٤٠٤', () {
    test('بلا جسمٍ = مسارٌ لا يعرفه الخادم، لا بياناتٌ مفقودة', () {
      // «غير موجود» عندنا يأتي بجسمٍ يحمل رسالته، أمّا مسارٌ لم يُنشَر
      // بعد فيردّ ٤٠٤ عارياً من ASP.NET. وكانا يخرجان معاً بـ«حدث خطأ،
      // الرجاء المحاولة لاحقاً» — فيُعيد المستخدم المحاولة بلا طائل.
      final e = ApiException.from(_err(404, null));

      expect(e.message, contains('أقدم من التطبيق'));
      expect(e.message, contains('مسؤول النظام'));
      expect(e.message, isNot(contains('أعد المحاولة لاحقاً')));
    });

    test('بجسمٍ يحمل رسالة = خطأُ بياناتٍ يُصلحه المستخدم', () {
      final e = ApiException.from(
        _err(404, {'message': 'العرض غير موجود أو لا ينتمي لهذا المستودع'}),
      );

      expect(e.message, 'العرض غير موجود أو لا ينتمي لهذا المستودع');
    });

    test('الجسم النصّي الفارغ كالمعدوم', () {
      final e = ApiException.from(_err(404, ''));
      expect(e.message, contains('أقدم من التطبيق'));
    });
  });

  group('أخطاء التحقّق', () {
    test('اسمُ الحقل يُذكر مع رسالته', () {
      final e = ApiException.from(_err(400, {
        'message': 'فشل التحقق من الصحة.',
        'errors': {
          'Items[0].UnitPrice': ['سعر الوحدة يجب أن يكون أكبر من صفر'],
        },
      }));

      expect(e.message, contains('سعر الوحدة يجب أن يكون أكبر من صفر'));
    });

    test('رسالة الخادم تُعرَض كما هي حين لا حقول', () {
      final e = ApiException.from(_err(400, {'message': 'نسبة الحسم بين صفر ومئة'}));
      expect(e.message, 'نسبة الحسم بين صفر ومئة');
    });
  });

  group('الخمسمئة', () {
    test('لا تُعرض رسالة الخادم — إمّا مبهمة وإمّا تُفشي داخله', () {
      final e = ApiException.from(
        _err(500, {'message': 'Npgsql.PostgresException: 42703'}),
      );

      expect(e.message, isNot(contains('Npgsql')));
      expect(e.kind, ApiErrorKind.server);
    });
  });
}
