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

    // Potong teks panjang menjadi bagian-bagian maksimal 150 karakter
    final chunks = _splitText(text, 150);
    final List<int> allBytes = [];

    for (final chunk in chunks) {
      final url = Uri.parse(
        'https://translate.google.com/translate_tts'
        '?ie=UTF-8'
        '&tl=id'
        '&client=tw-ob'
        '&q=${Uri.encodeComponent(chunk)}',
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
        throw Exception('TTS API gagal: HTTP ${response.statusCode}');
      }

      allBytes.addAll(response.bodyBytes);
    }

    if (allBytes.isEmpty) {
      throw Exception('TTS menghasilkan file kosong');
    }

    await mp3File.writeAsBytes(allBytes);
    return mp3File;
  }

  /// Generate nama file unik untuk alarm baru
  static String generateFilename(String label) {
    final now = DateTime.now();
    // Gunakan epoch timestamp hex (8 karakter) untuk menghemat panjang nama berkas
    final hexStamp = (now.millisecondsSinceEpoch ~/ 1000).toRadixString(16);

    final clean = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final shortClean = clean.substring(0, clean.length.clamp(0, 6));
    return 'al_${shortClean}_$hexStamp.mp3';
  }

  // Fungsi pembantu untuk memotong teks secara rapi berdasarkan spasi kata
  static List<String> _splitText(String text, int maxLength) {
    List<String> chunks = [];
    List<String> words = text.split(' ');
    String currentChunk = '';

    for (String word in words) {
      if ('$currentChunk $word'.trim().length <= maxLength) {
        currentChunk = '$currentChunk $word'.trim();
      } else {
        if (currentChunk.isNotEmpty) {
          chunks.add(currentChunk);
        }
        currentChunk = word;
      }
    }
    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk);
    }
    return chunks;
  }
}
