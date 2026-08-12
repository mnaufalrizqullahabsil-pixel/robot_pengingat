import 'package:flutter/material.dart';
import '../models/alarm.dart';
import '../services/tcp_service.dart';
import 'add_alarm_page.dart';
import 'settings_page.dart';

class AlarmListPage extends StatefulWidget {
  const AlarmListPage({super.key});

  @override
  State<AlarmListPage> createState() => _AlarmListPageState();
}

class _AlarmListPageState extends State<AlarmListPage> {
  final _tcp = TcpService.instance;
  List<Alarm> _alarms = [];
  String _status = 'Disconnected';
  int _totalBytes = 1;
  int _usedBytes = 0;

  @override
  void initState() {
    super.initState();
    _status = _tcp.status;
    _alarms = List.from(_tcp.alarms);
    _totalBytes = _tcp.totalBytes;
    _usedBytes  = _tcp.usedBytes;

    _tcp.statusStream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _tcp.alarmsStream.listen((list) {
      if (mounted) setState(() {
        _alarms = list;
      });
    });
    _tcp.storageStream.listen((m) {
      if (mounted) setState(() {
        _totalBytes = m['total'] ?? 1;
        _usedBytes  = m['used']  ?? 0;
      });
    });
  }

  Future<void> _refresh() async {
    _tcp.requestAlarmList();
    await Future.delayed(const Duration(seconds: 3));
  }

  Future<void> _deleteAlarm(Alarm alarm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Alarm', style: TextStyle(color: Colors.white)),
        content: Text(
          'Hapus "${alarm.label}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Color(0xFFFF5C5C))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _tcp.deleteAlarm(alarm.id);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        elevation: 0,
        title: const Text(
          'Robot Pengingat',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          // Status koneksi
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _StatusBadge(status: _status),
          ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white54),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Storage bar ────────────────────────────────────────────────────
          _StorageBar(total: _totalBytes, used: _usedBytes),

          // ── Alarm list ────────────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF4F8EF7),
              backgroundColor: const Color(0xFF1C2333),
              onRefresh: _refresh,
              child: _alarms.isEmpty
                  ? _EmptyState(isConnected: _tcp.isConnected)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: _alarms.length,
                      itemBuilder: (_, i) => _AlarmCard(
                        alarm: _alarms[i],
                        onDelete: () => _deleteAlarm(_alarms[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF4F8EF7),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_alarm_rounded),
        label: const Text('Tambah Alarm',
            style: TextStyle(fontWeight: FontWeight.w600)),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddAlarmPage()),
        ),
      ),
    );
  }
}

// ─── Widget: Status badge ──────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isConn   = status == 'Connected';
    final isLoading = status.contains('Connecting') || status.contains('Generating') || status.contains('Sending');
    final color    = isConn ? const Color(0xFF4CAF82) : isLoading ? const Color(0xFFFFC857) : const Color(0xFF6E7A8A);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          isConn ? 'Terhubung' : isLoading ? 'Menghubungkan...' : 'Terputus',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ─── Widget: Storage bar ───────────────────────────────────────────────────────
class _StorageBar extends StatelessWidget {
  final int total, used;
  const _StorageBar({required this.total, required this.used});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final freeKb = ((total - used) / 1024).toStringAsFixed(1);
    final usedKb = (used / 1024).toStringAsFixed(1);
    final totalKb = (total / 1024).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2333),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage_rounded, color: Color(0xFF4F8EF7), size: 14),
              const SizedBox(width: 6),
              Text(
                'Storage ESP8266  •  $usedKb KB / $totalKb KB',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const Spacer(),
              Text(
                'Sisa: $freeKb KB',
                style: const TextStyle(color: Colors.white30, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                pct > 0.8 ? const Color(0xFFFF5C5C) : const Color(0xFF4F8EF7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Widget: Empty state ───────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool isConnected;
  const _EmptyState({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(
          isConnected ? Icons.alarm_off_rounded : Icons.wifi_off_rounded,
          size: 72,
          color: Colors.white12,
        ),
        const SizedBox(height: 20),
        Text(
          isConnected ? 'Belum ada alarm' : 'Tidak terhubung ke ESP8266',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isConnected
              ? 'Tap tombol + untuk menambah alarm baru'
              : 'Buka Settings dan sambungkan ke robot',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white24, fontSize: 13),
        ),
      ],
    );
  }
}

// ─── Widget: Alarm card ────────────────────────────────────────────────────────
class _AlarmCard extends StatelessWidget {
  final Alarm alarm;
  final VoidCallback onDelete;
  const _AlarmCard({required this.alarm, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isRecurring = alarm.isRecurring;
    final badgeColor  = isRecurring ? const Color(0xFF4CAF82) : const Color(0xFFFFC857);
    // Untuk alarm harian, tampilkan jam besar; untuk sekali tampilkan info lengkap
    final bigTime = isRecurring
        ? alarm.timespec
        : alarm.timespec.length >= 16
            ? alarm.timespec.substring(11, 16)
            : alarm.timespec;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1C2333),
            const Color(0xFF1C2333).withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // ── Jam besar ──────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bigTime,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alarm.label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (!isRecurring) ...[
                    const SizedBox(height: 2),
                    Text(
                      alarm.displayTime,
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Badge tipe
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isRecurring ? Icons.repeat_rounded : Icons.event_available_rounded,
                          color: badgeColor,
                          size: 12,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          alarm.typeLabel,
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Tombol hapus ───────────────────────────────────────────────
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: const Color(0xFFFF5C5C),
              tooltip: 'Hapus alarm',
            ),
          ],
        ),
      ),
    );
  }
}
