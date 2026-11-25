import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'package:tawrid_app/core/constants/storage_keys.dart';
import 'package:tawrid_app/core/network/api_client.dart';
import 'package:tawrid_app/core/network/api_endpoints.dart';
import 'package:tawrid_app/core/storage/app_secure_storage.dart';
import 'package:tawrid_app/models/ai_import_models.dart';

final _log = Logger();

final inventoryImportHubProvider = Provider<InventoryImportHub>((ref) {
  final hub = InventoryImportHub();
  ref.onDispose(hub.dispose);
  return hub;
});

/// المهمة عطبت — برسالة صالحة للعرض.
class ImportFailedEvent {
  const ImportFailedEvent({required this.jobId, required this.message});
  final String jobId;
  final String message;
}

/// قناة تقدّم استيراد المخزون (SignalR).
///
/// **قناة استقبال فقط، وتسريعٌ لا أكثر.** حالة المهمة الدائمة في قاعدة
/// بيانات الخادم، والعميل يستطيع سؤالها عبر REST متى شاء. فإن سقطت القناة
/// لا يضيع شيء — الشاشة تسأل الخادم وتُكمل.
///
/// ولهذا لا يُبنى عليها ما لا يُسترجَع: عند [onReconnected] تُعاد قراءة
/// المهمة من الخادم بدل محاولة تعويض الإطارات التي فاتت أثناء الانقطاع.
///
/// قناة منفصلة عن قناة المحادثات: هذه تُفتح لشاشة الاستيراد وتُغلق بإغلاقها،
/// وتلك تبقى مفتوحة ما دام التطبيق يعمل.
class InventoryImportHub {
  HubConnection? _connection;

  final _progress = StreamController<ImportProgressEvent>.broadcast();
  final _ready = StreamController<String>.broadcast();
  final _failed = StreamController<ImportFailedEvent>.broadcast();
  final _reconnected = StreamController<void>.broadcast();

  /// تقدّم مرحلي — المستمع يُصفّي ما يعني مهمّته.
  Stream<ImportProgressEvent> get progress => _progress.stream;

  /// معرّف مهمة صارت جاهزة للمراجعة.
  Stream<String> get ready => _ready.stream;

  Stream<ImportFailedEvent> get failed => _failed.stream;

  /// نبضة بعد كل عودة اتصال — إشارة لإعادة قراءة حالة المهمة.
  Stream<void> get onReconnected => _reconnected.stream;

  bool get isConnected => _connection?.state == HubConnectionState.Connected;

  /// يفتح القناة لجلسة مستودع قائمة. آمن للاستدعاء المتكرّر.
  Future<void> connect() async {
    if (_connection != null) return;

    final token = await appSecureStorage.read(key: StorageKeys.warehouseToken);
    if (token == null || token.isEmpty) {
      _log.w('[ImportHub] لا توكن مستودع — لم تُفتح القناة.');
      return;
    }

    final connection = HubConnectionBuilder()
        .withUrl(
          '$apiBaseUrl${ApiEndpoints.inventoryImportsHub}',
          options: HttpConnectionOptions(
            // تُقرأ عند كل محاولة اتصال لا مرة واحدة: الرمز قد يتغيّر بين
            // انقطاع وعودة، وقراءته هنا تجعل إعادة الاتصال تحمل الحالي.
            accessTokenFactory: () async =>
                await appSecureStorage.read(
                  key: StorageKeys.warehouseToken,
                ) ??
                '',
          ),
        )
        .withAutomaticReconnect(
          retryDelays: [0, 2000, 5000, 10000, 20000],
        )
        .build();

    connection.on('importProgress', _onProgress);
    connection.on('importReady', _onReady);
    connection.on('importFailed', _onFailed);

    connection.onreconnected(({connectionId}) {
      _log.i('[ImportHub] عاد الاتصال.');
      if (!_reconnected.isClosed) _reconnected.add(null);
    });

    _connection = connection;

    try {
      await connection.start();
      _log.i('[ImportHub] اتصلت.');
    } on Object catch (e) {
      // فشل الاتصال لا يُسقط الشاشة: تُكمل بالاستعلام الدوري.
      _log.w('[ImportHub] تعذّر الاتصال: $e');
      _connection = null;
    }
  }

  Future<void> disconnect() async {
    final connection = _connection;
    _connection = null;
    if (connection == null) return;

    try {
      await connection.stop();
    } on Object catch (_) {
      // الإغلاق على اتصال ساقط أصلاً لا يستحق إبلاغاً.
    }
  }

  void _onProgress(List<Object?>? args) {
    final data = _firstMap(args);
    if (data == null || _progress.isClosed) return;
    _progress.add(ImportProgressEvent.fromJson(data));
  }

  void _onReady(List<Object?>? args) {
    final data = _firstMap(args);
    final jobId = data?['jobId'] as String?;
    if (jobId == null || _ready.isClosed) return;
    _ready.add(jobId);
  }

  void _onFailed(List<Object?>? args) {
    final data = _firstMap(args);
    final jobId = data?['jobId'] as String?;
    if (jobId == null || _failed.isClosed) return;
    _failed.add(ImportFailedEvent(
      jobId: jobId,
      message: data?['message'] as String? ?? 'تعذّر الاستيراد',
    ));
  }

  static Map<String, dynamic>? _firstMap(List<Object?>? args) {
    final first = args == null || args.isEmpty ? null : args.first;
    return first is Map<String, dynamic> ? first : null;
  }

  void dispose() {
    disconnect();
    _progress.close();
    _ready.close();
    _failed.close();
    _reconnected.close();
  }
}
