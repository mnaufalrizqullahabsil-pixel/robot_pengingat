/// Model data untuk satu alarm
class Alarm {
  final String id;       // nama file MP3, e.g. "alarm_20260812_0830.mp3"
  final String label;    // label yang tampil di UI, e.g. "Minum Obat"
  final String type;     // "R" = Harian, "O" = Sekali
  final String timespec; // "HH:MM" atau "YYYY/MM/DD HH:MM"

  const Alarm({
    required this.id,
    required this.label,
    required this.type,
    required this.timespec,
  });

  bool get isRecurring => type == 'R';

  /// Tampilan jam yang ramah: "08:30" atau "12 Agt 2026 • 08:30"
  String get displayTime {
    if (isRecurring) return timespec;

    // "YYYY/MM/DD HH:MM" → "DD/MM/YYYY HH:MM"
    if (timespec.length >= 16) {
      final date = timespec.substring(0, 10); // "YYYY/MM/DD"
      final time = timespec.substring(11, 16); // "HH:MM"
      final parts = date.split('/');
      if (parts.length == 3) {
        final months = [
          '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
          'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des'
        ];
        final m = int.tryParse(parts[1]) ?? 0;
        return '${parts[2]} ${months[m]} ${parts[0]} • $time';
      }
    }
    return timespec;
  }

  /// Untuk ditampilkan di badge
  String get typeLabel => isRecurring ? 'Harian' : 'Sekali';

  Alarm copyWith({
    String? id,
    String? label,
    String? type,
    String? timespec,
  }) {
    return Alarm(
      id: id ?? this.id,
      label: label ?? this.label,
      type: type ?? this.type,
      timespec: timespec ?? this.timespec,
    );
  }

  @override
  String toString() => 'Alarm($id, $label, $type, $timespec)';
}
