import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/tcp_service.dart';
import '../services/tts_service.dart';

class AddAlarmPage extends StatefulWidget {
  const AddAlarmPage({super.key});

  @override
  State<AddAlarmPage> createState() => _AddAlarmPageState();
}

class _AddAlarmPageState extends State<AddAlarmPage> {
  final _tcp = TcpService.instance;

  final _labelCtrl = TextEditingController();
  final _ttsCtrl   = TextEditingController();
  final _player    = AudioPlayer();

  TimeOfDay _selectedTime = TimeOfDay.now();
  DateTime  _selectedDate = DateTime.now();
  bool      _isRecurring  = true; // Harian atau Sekali

  String _phase = ''; // '' | 'generating' | 'sending' | 'done' | 'error'
  String _errorMsg = '';
  File?  _previewFile;
  bool   _isPlaying = false;

  // ─── Helpers ───────────────────────────────────────────────────────────────
  String get _timespecString {
    final hh = _selectedTime.hour.toString().padLeft(2, '0');
    final mm = _selectedTime.minute.toString().padLeft(2, '0');
    if (_isRecurring) return '$hh:$mm';

    final y  = _selectedDate.year.toString().padLeft(4, '0');
    final mo = _selectedDate.month.toString().padLeft(2, '0');
    final d  = _selectedDate.day.toString().padLeft(2, '0');
    return '$y/$mo/$d $hh:$mm';
  }

  String get _displayTime {
    final m = _selectedTime.minute.toString().padLeft(2, '0');
    return '${_selectedTime.hour.toString().padLeft(2, '0')}:$m';
  }

  String get _displayDate {
    final months = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agt','Sep','Okt','Nov','Des'];
    return '${_selectedDate.day} ${months[_selectedDate.month - 1]} ${_selectedDate.year}';
  }

  // ─── Pilih jam ─────────────────────────────────────────────────────────────
  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (ctx, child) => Theme(
        data: _timePickerTheme(ctx),
        child: child!,
      ),
    );
    if (t != null) setState(() => _selectedTime = t);
  }

  // ─── Pilih tanggal ─────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(DateTime.now()) ? DateTime.now() : _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (ctx, child) => Theme(
        data: _timePickerTheme(ctx),
        child: child!,
      ),
    );
    if (d != null) setState(() => _selectedDate = d);
  }

  // ─── Preview lokal ─────────────────────────────────────────────────────────
  Future<void> _preview() async {
    final ttsText = _ttsCtrl.text.trim();
    if (ttsText.isEmpty) {
      _showSnack('Isi teks pengingat dulu!', isError: true);
      return;
    }

    setState(() { _phase = 'generating'; _errorMsg = ''; });

    try {
      _previewFile = await TtsService.generateMp3(ttsText);
      setState(() { _phase = ''; _isPlaying = true; });

      await _player.play(DeviceFileSource(_previewFile!.path));
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _isPlaying = false);
      });
    } catch (e) {
      setState(() { _phase = 'error'; _errorMsg = e.toString(); });
    }
  }

  Future<void> _stopPreview() async {
    await _player.stop();
    setState(() => _isPlaying = false);
  }

  // ─── Simpan & kirim ke ESP ─────────────────────────────────────────────────
  Future<void> _saveAndSend() async {
    final label   = _labelCtrl.text.trim();
    final ttsText = _ttsCtrl.text.trim();

    if (label.isEmpty) {
      _showSnack('Isi label alarm!', isError: true);
      return;
    }
    if (ttsText.isEmpty) {
      _showSnack('Isi teks pengingat!', isError: true);
      return;
    }
    if (!_tcp.isConnected) {
      _showSnack('Belum terhubung ke ESP8266!', isError: true);
      return;
    }

    // Validasi tanggal one-time: jangan boleh di masa lalu
    if (!_isRecurring) {
      final now = DateTime.now();
      final alarmDt = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day,
        _selectedTime.hour, _selectedTime.minute,
      );
      if (alarmDt.isBefore(now)) {
        _showSnack('Waktu alarm sudah lewat!', isError: true);
        return;
      }
    }

    try {
      // 1. Generate TTS (gunakan file preview jika sudah ada)
      setState(() => _phase = 'generating');
      final mp3File = _previewFile ?? await TtsService.generateMp3(ttsText);

      // 2. Kirim audio ke ESP
      setState(() => _phase = 'sending');
      final filename = TtsService.generateFilename(label);
      final bytes    = await mp3File.readAsBytes();
      await _tcp.sendAudio(filename, bytes);

      // 3. Kirim jadwal alarm
      await _tcp.sendAlarmSchedule(
        filename: filename,
        label:    label,
        type:     _isRecurring ? 'R' : 'O',
        timespec: _timespecString,
      );

      setState(() => _phase = 'done');
      _showSnack('Alarm berhasil disimpan ke robot! ✅');
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _phase = 'error'; _errorMsg = e.toString(); });
      _showSnack('Gagal: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFFF5C5C) : const Color(0xFF4CAF82),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  void dispose() {
    _player.dispose();
    _labelCtrl.dispose();
    _ttsCtrl.dispose();
    super.dispose();
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
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
          'Alarm Baru',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Label ────────────────────────────────────────────────────────
            _SectionLabel('Label Alarm'),
            const SizedBox(height: 8),
            _DarkTextField(
              controller: _labelCtrl,
              hint: 'Misal: Minum Obat, Rapat Tim...',
              icon: Icons.label_outline_rounded,
              onChanged: (v) {
                // Auto-isi TTS jika masih kosong
                if (_ttsCtrl.text.isEmpty) _ttsCtrl.text = v;
              },
            ),

            const SizedBox(height: 24),

            // ── Pilih Jam ─────────────────────────────────────────────────────
            _SectionLabel('Waktu Alarm'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickTime,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C2333),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded, color: Color(0xFF4F8EF7), size: 22),
                    const SizedBox(width: 16),
                    Text(
                      _displayTime,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white24),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Harian / Sekali toggle ─────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C2333),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  _ToggleRow(
                    icon: Icons.repeat_rounded,
                    label: 'Alarm Harian',
                    sublabel: 'Berbunyi setiap hari pada jam yang dipilih',
                    value: _isRecurring,
                    onChanged: (v) => setState(() => _isRecurring = v),
                  ),
                  if (!_isRecurring) ...[
                    Divider(color: Colors.white10, height: 1),
                    ListTile(
                      leading: const Icon(Icons.event_outlined, color: Color(0xFFFFC857), size: 20),
                      title: const Text('Tanggal', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _displayDate,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 18),
                        ],
                      ),
                      onTap: _pickDate,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Teks TTS ──────────────────────────────────────────────────────
            _SectionLabel('Teks Pengingat (TTS)'),
            const SizedBox(height: 8),
            _DarkTextField(
              controller: _ttsCtrl,
              hint: 'Teks yang akan diucapkan robot...',
              icon: Icons.record_voice_over_outlined,
              maxLines: 3,
            ),
            const SizedBox(height: 12),

            // ── Preview button ────────────────────────────────────────────────
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4F8EF7),
                side: const BorderSide(color: Color(0xFF4F8EF7)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _phase == 'generating' ? null
                  : _isPlaying ? _stopPreview
                  : _preview,
              icon: Icon(_isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded),
              label: Text(
                _phase == 'generating' ? 'Membuat audio...'
                    : _isPlaying ? 'Stop Preview'
                    : '▶  Preview Audio',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),

            const SizedBox(height: 32),

            // ── Status bar ────────────────────────────────────────────────────
            if (_phase.isNotEmpty && _phase != 'done') ...[
              _PhaseIndicator(phase: _phase, error: _errorMsg),
              const SizedBox(height: 16),
            ],

            // ── Simpan & Kirim ─────────────────────────────────────────────────
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F8EF7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: (_phase == 'generating' || _phase == 'sending') ? null : _saveAndSend,
              icon: const Icon(Icons.send_rounded),
              label: Text(
                _phase == 'generating' ? 'Membuat Audio...'
                    : _phase == 'sending' ? 'Mengirim ke Robot...'
                    : 'Simpan & Kirim ke Robot',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers: ThemeData untuk time/date picker ────────────────────────────────
ThemeData _timePickerTheme(BuildContext context) {
  return ThemeData.dark().copyWith(
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF4F8EF7),
      onPrimary: Colors.white,
      surface: Color(0xFF1C2333),
      onSurface: Colors.white,
    ),
  );
}

// ─── Widget: Section label ────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

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

// ─── Widget: Dark text field ──────────────────────────────────────────────────
class _DarkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const _DarkTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    maxLines: maxLines,
    onChanged: onChanged,
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

// ─── Widget: Toggle row (Harian/Sekali) ──────────────────────────────────────
class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label, sublabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF4CAF82), size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              Text(sublabel,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: const Color(0xFF4CAF82),
          inactiveThumbColor: Colors.white38,
          inactiveTrackColor: Colors.white12,
        ),
      ],
    ),
  );
}

// ─── Widget: Phase indicator ──────────────────────────────────────────────────
class _PhaseIndicator extends StatelessWidget {
  final String phase, error;
  const _PhaseIndicator({required this.phase, required this.error});

  @override
  Widget build(BuildContext context) {
    final isError = phase == 'error';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isError ? const Color(0xFFFF5C5C) : const Color(0xFF4F8EF7)).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (isError ? const Color(0xFFFF5C5C) : const Color(0xFF4F8EF7)).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          if (!isError)
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF4F8EF7),
              ),
            )
          else
            const Icon(Icons.error_outline, color: Color(0xFFFF5C5C), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isError
                  ? error
                  : phase == 'generating'
                      ? 'Membuat audio TTS...'
                      : 'Mengirim ke robot...',
              style: TextStyle(
                color: isError ? const Color(0xFFFF5C5C) : const Color(0xFF4F8EF7),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
