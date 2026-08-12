import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/tcp_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _tcp      = TcpService.instance;
  final _ipCtrl   = TextEditingController();
  final _portCtrl = TextEditingController();

  String _status     = '';
  int    _totalBytes = 1;
  int    _usedBytes  = 0;
  bool   _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _status     = _tcp.status;
    _totalBytes = _tcp.totalBytes;
    _usedBytes  = _tcp.usedBytes;

    _tcp.statusStream.listen((s) {
      if (mounted) setState(() {
        _status = s;
        _isConnecting = s.contains('Connecting');
      });
    });
    _tcp.storageStream.listen((m) {
      if (mounted) setState(() {
        _totalBytes = m['total'] ?? 1;
        _usedBytes  = m['used']  ?? 0;
      });
    });
  }

  Future<void> _loadSettings() async {
    final (ip, port) = await TcpService.loadSettings();
    setState(() {
      _ipCtrl.text   = ip;
      _portCtrl.text = port.toString();
    });
  }

  Future<void> _connect() async {
    final ip   = _ipCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 12345;
    await TcpService.saveSettings(ip, port);
    await _tcp.connect(ip, port);
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usedKb  = (_usedBytes / 1024).toStringAsFixed(1);
    final totalKb = (_totalBytes / 1024).toStringAsFixed(1);
    final freeKb  = ((_totalBytes - _usedBytes) / 1024).toStringAsFixed(1);
    final pct     = _totalBytes > 0 ? (_usedBytes / _totalBytes).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white54),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Pengaturan Koneksi',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Status card ────────────────────────────────────────────────
            _StatusCard(status: _status),
            const SizedBox(height: 20),

            // ── IP Address ────────────────────────────────────────────────
            const _Label('IP Address ESP8266'),
            const SizedBox(height: 8),
            _DarkField(
              controller: _ipCtrl,
              hint: '192.168.43.100',
              icon: Icons.router_outlined,
              inputType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
            const SizedBox(height: 14),

            // ── Port ──────────────────────────────────────────────────────
            const _Label('Port TCP'),
            const SizedBox(height: 8),
            _DarkField(
              controller: _portCtrl,
              hint: '12345',
              icon: Icons.numbers_rounded,
              inputType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 20),

            // ── Connect / Disconnect buttons ───────────────────────────────
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F8EF7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _isConnecting ? null : _connect,
                    icon: _isConnecting
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.link_rounded),
                    label: Text(
                      _isConnecting ? 'Menghubungkan...' : 'Connect',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF5C5C),
                      side: const BorderSide(color: Color(0xFFFF5C5C)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _tcp.disconnect,
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('Disconnect',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // ── Storage ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2333),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.sd_storage_outlined,
                          color: Color(0xFF4F8EF7), size: 18),
                      SizedBox(width: 8),
                      Text('Storage LittleFS',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        pct > 0.8
                            ? const Color(0xFFFF5C5C)
                            : const Color(0xFF4F8EF7),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _StorageStat(label: 'Terpakai', value: '$usedKb KB',
                          color: const Color(0xFF4F8EF7)),
                      const SizedBox(width: 20),
                      _StorageStat(label: 'Total', value: '$totalKb KB',
                          color: Colors.white54),
                      const SizedBox(width: 20),
                      _StorageStat(label: 'Sisa', value: '$freeKb KB',
                          color: const Color(0xFF4CAF82)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Info ───────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cara Mendapatkan IP:',
                      style: TextStyle(
                          color: Colors.white60, fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  SizedBox(height: 6),
                  Text(
                    '1. Pastikan HP & ESP8266 di WiFi yang sama\n'
                    '2. Upload firmware Arduino ke ESP8266\n'
                    '3. Buka Serial Monitor (115200 baud)\n'
                    '4. IP akan muncul setelah ESP terhubung WiFi',
                    style: TextStyle(color: Colors.white38, fontSize: 12,
                        height: 1.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Colors.white54,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    ),
  );
}

class _DarkField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType inputType;
  final List<TextInputFormatter>? inputFormatters;

  const _DarkField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.inputType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: inputType,
    inputFormatters: inputFormatters,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white24),
      prefixIcon: Icon(icon, color: Colors.white38, size: 20),
      filled: true,
      fillColor: const Color(0xFF1C2333),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF4F8EF7)),
      ),
    ),
  );
}

class _StatusCard extends StatelessWidget {
  final String status;
  const _StatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final isConn    = status == 'Connected';
    final isLoading = status.contains('Connecting');
    final color     = isConn
        ? const Color(0xFF4CAF82)
        : isLoading
            ? const Color(0xFFFFC857)
            : const Color(0xFF6E7A8A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Text(
            'Status: $status',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StorageStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      const SizedBox(height: 2),
      Text(value,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 14)),
    ],
  );
}
