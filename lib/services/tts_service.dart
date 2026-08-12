import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Service untuk generate TTS MP3 via StreamElements API
class TtsService {
  /// Generate file MP3 dari [text] dan simpan ke direktori temporary.
  /// Returns [File] yang siap diplay atau dikirim ke ESP.
  static Future<File> generateMp3(String text) async {
    final dir     = await getTemporaryDirectory();
    final mp3File = File('${dir.path}/tts_preview.mp3');

    final url = Uri.parse(
      'https://translate.google.com/translate_tts'
      '?ie=UTF-8'
      '&tl=id'
      '&client=tw-ob'
      '&q=${Uri.encodeComponent(text)}',
    );

    final response = await http.get(
      url,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36',
      },
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception('TTS timeout — cek koneksi internet'),
    );

    if (response.statusCode != 200) {
      throw Exception('TTS API gagal: HTTP ${response.statusCode} (Coba kurangi panjang teks)');
    }

    if (response.bodyBytes.isEmpty) {
      throw Exception('TTS menghasilkan file kosong');
    }

    await mp3File.writeAsBytes(response.bodyBytes);
    return mp3File;
  }

  /// Generate nama file unik untuk alarm baru
  static String generateFilename(String label) {
    final now   = DateTime.now();
    final stamp = '${now.year}${_pad(now.month)}${_pad(now.day)}'
                  '_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    // Bersihkan label untuk dijadikan bagian nama file
    final clean = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .substring(0, label.length.clamp(0, 12));
    return 'alarm_${clean}_$stamp.mp3';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
