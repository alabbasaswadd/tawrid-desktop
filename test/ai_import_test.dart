import 'package:flutter_test/flutter_test.dart';
import 'package:tawrid_app/core/network/api_endpoints.dart';
import 'package:tawrid_app/models/ai_import_models.dart';

void main() {
  group('حالة المهمة', () {
    test('الأرقام تُترجَم لمراحل، والمجهول يسقط على الانتظار', () {
      expect(ImportStatus.fromCode(2), ImportStatus.analyzing);
      expect(ImportStatus.fromCode(4), ImportStatus.ready);
      expect(ImportStatus.fromCode(6), ImportStatus.applied);

      // خادمٌ أحدث أضاف مرحلةً لا نعرفها: لا يجوز أن تنكسر الشاشة.
      expect(ImportStatus.fromCode(99), ImportStatus.pending);
      expect(ImportStatus.fromCode(null), ImportStatus.pending);
    });

    test('isRunning يغطّي المراحل الثلاث التي تُستطلَع', () {
      expect(ImportStatus.pending.isRunning, isTrue);
      expect(ImportStatus.analyzing.isRunning, isTrue);
      expect(ImportStatus.matching.isRunning, isTrue);
      expect(ImportStatus.ready.isRunning, isFalse);
      expect(ImportStatus.applied.isRunning, isFalse);
      expect(ImportStatus.failed.isRunning, isFalse);
    });
  });

  group('صفّ المراجعة', () {
    Map<String, dynamic> rowJson({
      int match = 1,
      Map<String, dynamic>? matched,
      List<Map<String, dynamic>> candidates = const [],
    }) =>
        {
          'id': 'row-1',
          'rowNumber': 7,
          'rawCells': '7 | بانادول | 500 | 12500',
          'name': 'بانادول',
          'strength': 500,
          'form': 'أقراص',
          'manufacturer': '',
          'quantity': 30,
          'price': 12500.5,
          'confidence': 0.92,
          'note': null,
          'matchStatus': match,
          'selected': true,
          'matched': matched,
          'candidates': candidates,
          'previousPrice': null,
          'outcome': 0,
        };

    test('يفكّك الحقول ويُسقِط النصوص الفارغة', () {
      final row = ImportRow.fromJson(rowJson(matched: {
        'catalogItemId': 'cat-1',
        'displayName': 'بانادول',
        'sakoCode': 'SK-1',
        'strength': 500,
        'manufacturerName': 'جمجوم',
        'pricePublic': 16000,
      }));

      expect(row.rowNumber, 7);
      expect(row.name, 'بانادول');
      expect(row.form, 'أقراص');
      expect(row.manufacturer, isNull); // نصّ فارغ ← null لا ''
      expect(row.price, 12500.5);
      expect(row.confidence, closeTo(0.92, 0.001));
      expect(row.matched?.displayName, 'بانادول');
      expect(row.isActionable, isTrue);
    });

    test('غير الموجود ليس قابلاً للتنفيذ ولو حُدِّد', () {
      final row = ImportRow.fromJson(rowJson(match: 3));
      expect(row.matchStatus, ImportMatch.notFound);
      expect(row.isActionable, isFalse);
    });

    test('المطابقة بلا صنف ليست قابلة للتنفيذ', () {
      // matched فارغ مع حالة «مطابق» — تعارضٌ لا يجوز أن يُنتج إضافةً
      // بلا صنف كتالوج.
      final row = ImportRow.fromJson(rowJson(matched: null));
      expect(row.isActionable, isFalse);
    });

    test('copyWith يحفظ المرشّحين وما لم يُمرَّر', () {
      final row = ImportRow.fromJson(rowJson(
        match: 2,
        matched: {'catalogItemId': 'a', 'displayName': 'أ'},
        candidates: [
          {'catalogItemId': 'a', 'displayName': 'أ'},
          {'catalogItemId': 'b', 'displayName': 'ب'},
        ],
      ));

      final picked = row.copyWith(
        matched: const ImportCandidate(catalogItemId: 'b', displayName: 'ب'),
        matchStatus: ImportMatch.matched,
      );

      expect(picked.matched?.catalogItemId, 'b');
      expect(picked.matchStatus, ImportMatch.matched);
      expect(picked.candidates, hasLength(2));
      expect(picked.rowNumber, 7);
      expect(picked.price, 12500.5);
    });
  });

  group('المهمة والتقرير', () {
    test('ImportJob يقرأ التقدّم والعدّادات والملخّص', () {
      final job = ImportJob.fromJson({
        'jobId': 'job-1',
        'fileName': 'جرد.xlsx',
        'status': 3,
        'totalRows': 120,
        'analyzedRows': 120,
        'matchedRows': 60,
        'progress': 0.85,
        'activity': 'طابق ٦٠ من ١٢٠…',
        'summary': {
          'text': 'ملف جرد فيه ١٢٠ صنفاً',
          'columns': ['الاسم', 'السعر', ''],
          'warnings': ['عمودٌ بلا ترويسة'],
        },
        'counts': {
          'total': 120,
          'new': 90,
          'priceUpdate': 25,
          'needsConfirm': 4,
          'notFound': 1,
        },
        'rows': const [],
      });

      expect(job.status, ImportStatus.matching);
      expect(job.progress, closeTo(0.85, 0.001));
      expect(job.summary.columns, ['الاسم', 'السعر']); // الفارغ يُسقَط
      expect(job.summary.warnings, hasLength(1));
      expect(job.counts.newItems, 90);
      expect(job.counts.priceUpdate, 25);
    });

    test('التقرير يفصل المُضاف عن المُعدَّل ويحمل السعر السابق', () {
      final report = ImportReport.fromJson({
        'jobId': 'job-1',
        'added': [
          {'rowNumber': 3, 'displayName': 'أموكسيل', 'price': 8000},
        ],
        'modified': [
          {
            'rowNumber': 9,
            'displayName': 'بانادول',
            'price': 13000,
            'previousPrice': 12500,
          },
        ],
        'failed': [
          {'rowNumber': 11, 'name': 'دواء', 'message': 'مرفوض'},
        ],
        'skippedCount': 5,
      });

      expect(report.added, hasLength(1));
      expect(report.modified.single.previousPrice, 12500);
      expect(report.modified.single.price, 13000);
      expect(report.total, 2);
      expect(report.hasFailures, isTrue);
      expect(report.skippedCount, 5);
    });

    test('حدث التقدّم يُقرأ من حمولة القناة', () {
      final event = ImportProgressEvent.fromJson({
        'jobId': 'job-1',
        'phase': 2,
        'done': 60,
        'total': 120,
        'activity': 'يحلّل الوكيل الدفعة ١ من ٢…',
      });

      expect(event.phase, ImportStatus.analyzing);
      expect(event.done, 60);
      expect(event.activity, contains('الدفعة'));
    });
  });

  group('مسارات الاستيراد', () {
    test('تُبنى على بادئة المستودع', () {
      expect(ApiEndpoints.whImport, '/tawrid-api/warehouse/medicines/import');
      expect(ApiEndpoints.whImportActive,
          '/tawrid-api/warehouse/medicines/import/active');
      expect(ApiEndpoints.whImportById('j1'),
          '/tawrid-api/warehouse/medicines/import/j1');
      expect(ApiEndpoints.whImportApply('j1'),
          '/tawrid-api/warehouse/medicines/import/j1/apply');
    });

    test('قناة الاستيراد منفصلة عن قناة المحادثات', () {
      expect(ApiEndpoints.inventoryImportsHub,
          '/tawrid-api/hubs/inventory-imports');
      expect(ApiEndpoints.inventoryImportsHub,
          isNot(ApiEndpoints.conversationsHub));
    });
  });
}
