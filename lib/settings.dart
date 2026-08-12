import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

int totalBytes = 1;
int usedBytes = 0;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController ipController = TextEditingController(text: "192.168.43.100");
  final TextEditingController portController = TextEditingController(text: "80");
  final TextEditingController messageController = TextEditingController();

  String status = "Ready";
  bool isLoading = false;

  String get baseUrl => "http://${ipController.text.trim()}:${portController.text.trim()}";

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  // Memuat IP dan Port yang tersimpan sebelumnya
  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      ipController.text = prefs.getString('esp_ip') ?? "192.168.43.100";
      portController.text = prefs.getString('esp_port') ?? "80";
    });
    // Otomatis cek storage saat halaman pertama kali dibuka
    fetchStorageInfo();
  }

  // Menyimpan IP dan Port ke local storage HP
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp_ip', ipController.text.trim());
    await prefs.setString('esp_port', portController.text.trim());
  }

  // 1. Cek Koneksi & Kapasitas LittleFS ESP8266
  Future<void> fetchStorageInfo() async {
    await _saveSettings();

    setState(() {
      status = "Menghubungkan ke ESP...";
      isLoading = true;
    });

    try {
      final response = await http
          .get(Uri.parse("$baseUrl/storage"))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final message = response.body.trim();
        if (message.startsWith("STORAGE|")) {
          final parts = message.split('|');
          setState(() {
            totalBytes = int.parse(parts[1]);
            usedBytes = int.parse(parts[2]);
            status = "Terhubung ke ESP8266";
          });
        }
      } else {
        setState(() => status = "Respon ESP: Status ${response.statusCode}");
      }
    } catch (e) {
      setState(() => status = "Gagal terhubung: Pastikan satu Wi-Fi & IP benar");
      print("Error fetchStorage: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // 2. Generate Google TTS MP3 (Berjalan lancar di Aplikasi HP)
  Future<File> generateTtsMp3(String text) async {
    final dir = await getTemporaryDirectory();
    final mp3File = File("${dir.path}/tts.mp3");

    final url = "https://translate.google.com/translate_tts"
        "?ie=UTF-8"
        "&client=tw-ob"
        "&tl=id"
        "&q=${Uri.encodeComponent(text)}";

    final response = await http.get(
      Uri.parse(url),
      headers: {
        // Di aplikasi HP, header User-Agent ini diizinkan oleh Google
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "*/*",
      },
    );

    if (response.statusCode != 200) {
      throw Exception("Gagal TTS (${response.statusCode})");
    }

    await mp3File.writeAsBytes(response.bodyBytes);
    return mp3File;
  }

  // 3. Generate Suara dan Kirim ke ESP8266
Future<void> sendText() async {
    final text = messageController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Teks pesan tidak boleh kosong!")),
      );
      return;
    }

    await _saveSettings();

    setState(() {
      isLoading = true;
      status = "Sedang generate TTS MP3...";
    });

    try {
      // 1. Dapatkan file MP3 dari TTS
      final mp3File = await generateTtsMp3(text);
      final fileSize = await mp3File.length();

      setState(() => status = "Mengirim audio ($fileSize bytes)...");

      // 2. Kirim via MultipartRequest (Streaming upload)
      final request = http.MultipartRequest(
        'POST',
        Uri.parse("$baseUrl/upload-audio"),
      );

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          mp3File.path,
          filename: 'reminder.mp3',
        ),
      );

      final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        setState(() => status = "Audio Berhasil Terkirim & Dimainkan!");
        messageController.clear();
        await fetchStorageInfo();
      } else {
        setState(() => status = "Gagal kirim: Status ${response.statusCode}");
      }
    } catch (e) {
      setState(() => status = "Error: $e");
      print("Error sendText: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    ipController.dispose();
    portController.dispose();
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = totalBytes > 0 ? (usedBytes / totalBytes) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings ESP8266"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isLoading ? null : fetchStorageInfo,
            tooltip: "Refresh Status",
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: ipController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "IP Address ESP",
                        hintText: "Misal: 192.168.43.100",
                        prefixIcon: Icon(Icons.wifi),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Port",
                        hintText: "80",
                        prefixIcon: Icon(Icons.numbers),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: isLoading ? null : fetchStorageInfo,
                      icon: const Icon(Icons.link),
                      label: const Text("Tes Koneksi & Storage"),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Status: $status",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: status.contains("Terhubung") || status.contains("Berhasil")
                            ? Colors.green
                            : (status.contains("Gagal") || status.contains("Error")
                                ? Colors.red
                                : Colors.blueGrey),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text("Kapasitas LittleFS ESP8266:", style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Terpakai: ${(usedBytes / 1024).toStringAsFixed(1)} KB"),
                        Text("Total: ${(totalBytes / 1024).toStringAsFixed(1)} KB"),
                      ],
                    ),
                    Text(
                      "Sisa: ${((totalBytes - usedBytes) / 1024).toStringAsFixed(1)} KB",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: messageController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: "Pesan Text-to-Speech",
                        hintText: "Ketik pesan pengingat...",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: isLoading ? null : sendText,
                        icon: const Icon(Icons.record_voice_over),
                        label: const Text("Generate TTS & Kirim"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}