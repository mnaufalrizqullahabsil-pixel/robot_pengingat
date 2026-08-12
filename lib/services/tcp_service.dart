import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alarm.dart';

/// Singleton service untuk komunikasi TCP dengan ESP8266.
/// Gunakan [TcpService.instance] di seluruh app.
class TcpService {
  TcpService._();
  static final TcpService instance = TcpService._();

  Socket? _socket;
  bool _isConnecting = false;
  String _buffer = '';

  // ── State ──────────────────────────────────────────────────────────────────
  String status = 'Disconnected';
  int totalBytes = 1;
  int usedBytes = 0;
  List<Alarm> alarms = [];

  // ── Streams ────────────────────────────────────────────────────────────────
  final _statusCtrl  = StreamController<String>.broadcast();
  final _storageCtrl = StreamController<Map<String, int>>.broadcast();
  final _alarmsCtrl  = StreamController<List<Alarm>>.broadcast();

  Stream<String>           get statusStream  => _statusCtrl.stream;
  Stream<Map<String, int>> get storageStream => _storageCtrl.stream;
  Stream<List<Alarm>>      get alarmsStream  => _alarmsCtrl.stream;

  bool get isConnected => _socket != null && status == 'Connected';

  // ── Koneksi ────────────────────────────────────────────────────────────────
  Future<void> connect(String ip, int port) async {
    if (_isConnecting) return;
    disconnect();
    _isConnecting = true;
    _setStatus('Connecting...');

    try {
      _socket = await Socket.connect(
        ip, port,
        timeout: const Duration(seconds: 6),
      );

      _setStatus('Connected');
      _isConnecting = false;
      _buffer = '';

      _socket!.listen(
        _onData,
        onError: (_) => disconnect(),
        onDone:  () => disconnect(),
      );

      // Sync waktu ke ESP dan minta daftar alarm
      syncTime();
      requestAlarmList();
    } catch (e) {
      _setStatus('Gagal: $e');
      _isConnecting = false;
    }
  }

  void disconnect() {
    _socket?.destroy();
    _socket = null;
    _isConnecting = false;
    _setStatus('Disconnected');
  }

  void _setStatus(String s) {
    status = s;
    _statusCtrl.add(s);
  }

  Completer<void>? _readyCompleter;
  Completer<void>? _storageCompleter;
  Completer<void>? _alarmCompleter;

  void _completeSafely(Completer<void>? completer) {
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void _completeErrorSafely(Completer<void>? completer, Object error) {
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }

  // ── Terima data dari ESP ────────────────────────────────────────────────────
  void _onData(List<int> data) {
    _buffer += String.fromCharCodes(data);
    while (_buffer.contains('\n')) {
      final idx  = _buffer.indexOf('\n');
      final line = _buffer.substring(0, idx).trim();
      _buffer    = _buffer.substring(idx + 1);
      if (line.isNotEmpty) _processLine(line);
    }
  }

  void _processLine(String line) {
    if (line == 'READY_TO_RECEIVE') {
      _completeSafely(_readyCompleter);
    } else if (line.startsWith('ERROR_')) {
      final exception = Exception('ESP Error: ${line.substring(6)}');
      _completeErrorSafely(_readyCompleter, exception);
      _completeErrorSafely(_storageCompleter, exception);
      _completeErrorSafely(_alarmCompleter, exception);
    } else if (line.startsWith('STORAGE|')) {
      final parts = line.split('|');
      if (parts.length >= 3) {
        totalBytes = int.tryParse(parts[1]) ?? 1;
        usedBytes  = int.tryParse(parts[2]) ?? 0;
        _storageCtrl.add({'total': totalBytes, 'used': usedBytes});
      }
      _completeSafely(_storageCompleter);
    } else if (line.startsWith('ALARMS|')) {
      _parseAlarmList(line);
      _completeSafely(_alarmCompleter);
    }
  }

  void _parseAlarmList(String line) {
    // Format: ALARMS|count|filename|label|type|timespec|...
    final parts = line.split('|');
    if (parts.length < 2) return;

    final count     = int.tryParse(parts[1]) ?? 0;
    final newAlarms = <Alarm>[];

    int idx = 2;
    for (int i = 0; i < count; i++) {
      if (idx + 3 >= parts.length) break;
      newAlarms.add(Alarm(
        id:       parts[idx],
        label:    parts[idx + 1],
        type:     parts[idx + 2],
        timespec: parts[idx + 3],
      ));
      idx += 4;
    }

    alarms = newAlarms;
    _alarmsCtrl.add(alarms);
  }

  // ── Kirim perintah ke ESP ──────────────────────────────────────────────────
  void syncTime() {
    final unix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _socket?.write('TIME|$unix\n');
  }

  void requestAlarmList() {
    _socket?.write('LIST_ALARMS\n');
  }

  Future<void> sendAudio(String filename, List<int> bytes) async {
    if (_socket == null) return;

    // 1. Kirim Header Informasi Audio
    _readyCompleter = Completer<void>();
    _socket!.write('AUDIO|$filename|${bytes.length}\n');
    await _socket!.flush();

    // 2. Tunggu ESP mengirimkan sinyal siap pertama (READY_TO_RECEIVE)
    await _readyCompleter!.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw Exception('ESP tidak merespon perintah kirim audio'),
    );

    // 3. Kirim data byte audio dalam bentuk chunk (masing-masing 1KB)
    int offset = 0;
    const chunkSize = 1024;

    while (offset < bytes.length) {
      int end = offset + chunkSize;
      if (end > bytes.length) end = bytes.length;
      final chunk = bytes.sublist(offset, end);

      _readyCompleter = Completer<void>(); // Re-init completer untuk chunk berikutnya
      _socket!.add(chunk);
      await _socket!.flush();

      // Tunggu konfirmasi READY_TO_RECEIVE dari ESP untuk chunk ini
      await _readyCompleter!.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw Exception('Timeout saat mengirim audio chunk pada offset $offset'),
      );

      offset = end;
    }

    // 4. Kirim sinyal bahwa seluruh biner audio selesai dikirim
    _storageCompleter = Completer<void>();
    _socket!.write('AUDIO_COMPLETE\n');
    await _socket!.flush();

    // 5. Tunggu ESP selesai menulis file ke flash memory (STORAGE|...)
    await _storageCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception('Timeout saat menulis file audio ke robot'),
    );
  }

  Future<void> sendAlarmSchedule({
    required String filename,
    required String label,
    required String type,
    required String timespec,
  }) async {
    if (_socket == null) return;

    // Kirim jadwal alarm dan tunggu konfirmasi penambahan dari ESP (list alarm baru)
    _alarmCompleter = Completer<void>();
    _socket!.write('ALARM|$filename|$label|$type|$timespec\n');
    await _socket!.flush();

    await _alarmCompleter!.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw Exception('Timeout saat menyimpan jadwal alarm di robot'),
    );
  }

  Future<void> deleteAlarm(String filename) async {
    if (_socket == null) return;
    _socket!.write('DELETE_ALARM|$filename\n');
    await _socket!.flush();
  }

  // ── Simpan & load pengaturan koneksi ──────────────────────────────────────
  static Future<(String, int)> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final ip    = prefs.getString('esp_ip')   ?? '192.168.43.100';
    final port  = int.tryParse(prefs.getString('esp_port') ?? '') ?? 12345;
    return (ip, port);
  }

  static Future<void> saveSettings(String ip, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp_ip',   ip);
    await prefs.setString('esp_port', port.toString());
  }

  void dispose() {
    disconnect();
    _statusCtrl.close();
    _storageCtrl.close();
    _alarmsCtrl.close();
  }
}
