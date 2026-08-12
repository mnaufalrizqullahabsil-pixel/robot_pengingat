import 'dart:io';
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
  final TextEditingController portController = TextEditingController(text: "12345");
  final TextEditingController messageController = TextEditingController();

  Socket? socket;
  String status = "Disconnected";
  bool isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  // Memuat IP & Port yang terakhir tersimpan di HP
  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      ipController.text = prefs.getString('esp_ip') ?? "192.168.43.100";
      portController.text = prefs.getString('esp_port') ?? "12345";
    });
    connect();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp_ip', ipController.text.trim());
    await prefs.setString('esp_port', portController.text.trim());
  }

  // Fungsi Connect via TCP Socket
  Future<void> connect() async {
    if (isConnecting) return;
    
    await _saveSettings();
    disconnect();

    setState(() {
      isConnecting = true;
      status = "Connecting...";
    });

    try {
      final ip = ipController.text.trim();
      final port = int.parse(portController.text.trim());

      socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 6));

      setState(() {
        status = "Connected";
        isConnecting = false;
      });

      // Mendengarkan data masuk dari ESP8266 (misal info storage)
      socket!.listen(
        (data) {
          String message = String.fromCharCodes(data);
          print("Pesan dari ESP: $message");

          if (message.startsWith("STORAGE|")) {
            final parts = message.split('|');
            if (parts.length >= 3) {
              setState(() {
                totalBytes = int.parse(parts[1]);
                usedBytes = int.parse(parts[2]);
              });
            }
          }
        },
        onError: (error) {
          print("Socket Error: $error");
          disconnect();
        },
        onDone: () {
          print("Socket Disconnected by server");
          disconnect();
        },
      );
    } catch (e) {
      print("Connection failed error: $e");
      setState(() {
        status = "Connection failed";
        isConnecting = false;
      });
    }
  }

  // Generate Google TTS MP3
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
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      },
    );

    if (response.statusCode != 200) {
      throw Exception("TTS failed: ${response.statusCode}");
    }

    await mp3File.writeAsBytes(response.bodyBytes);
    print("MP3 size: ${await mp3File.length()} bytes");
    return mp3File;
  }
  // Kirim Audio & Format Header TCP Socket
  Future<void> sendText() async {
    if (socket == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Belum terhubung ke ESP8266! Klik Connect dulu.")),
      );
      await connect();
      if (socket == null) return;
    }

    final text = messageController.text.trim();
    if (text.isEmpty) return;

    try {
      setState(() => status = "Generating TTS...");
      final mp3File = await generateTtsMp3(text);
      final bytes = await mp3File.readAsBytes();

      setState(() => status = "Sending audio...");
      
      // Format header TCP yang dikenali oleh parsing.ino di ESP8266
      socket!.write("AUDIO|reminder.mp3|${bytes.length}\n");
      socket!.add(bytes);
      await socket!.flush();

      setState(() => status = "Connected (Sent!)");
      messageController.clear();
      print("Sent ${bytes.length} bytes successfully via TCP");
    } catch (e) {
      print("Send error: $e");
      setState(() => status = "Send failed");
    }
  }

  void disconnect() {
    socket?.destroy();
    socket = null;
    if (mounted) {
      setState(() {
        status = "Disconnected";
      });
    }
  }

  @override
  void dispose() {
    disconnect();
    ipController.dispose();
    portController.dispose();
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings ESP8266 (TCP)"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: ipController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "ESP IP Address",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Port (12345)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isConnecting ? null : connect,
                    icon: const Icon(Icons.link),
                    label: Text(isConnecting ? "Connecting..." : "Connect"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: disconnect,
                    icon: const Icon(Icons.link_off),
                    label: const Text("Disconnect"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: status == "Connected" ? Colors.green.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: status == "Connected" ? Colors.green : Colors.grey.shade400,
                ),
              ),
              child: Text(
                "Status: $status",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: status == "Connected" ? Colors.green.shade700 : Colors.black87,
                ),
              ),
            ),
            const Divider(height: 30),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Storage Wemos LittleFS:", style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: totalBytes > 0 ? (usedBytes / totalBytes).clamp(0.0, 1.0) : 0,
                ),
                const SizedBox(height: 8),
                Text("Terpakai: ${(usedBytes / 1024).toStringAsFixed(1)} KB / Total: ${(totalBytes / 1024).toStringAsFixed(1)} KB"),
                Text("Free: ${((totalBytes - usedBytes) / 1024).toStringAsFixed(1)} KB", style: const TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: messageController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "Pesan Text-to-Speech",
                hintText: "Ketik pengingat...",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: sendText,
              icon: const Icon(Icons.record_voice_over),
              label: const Text("Generate TTS & Kirim"),
            ),
          ],
        ),
      ),
    );
  }
}