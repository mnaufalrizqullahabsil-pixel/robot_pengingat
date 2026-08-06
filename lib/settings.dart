import 'dart:io';

import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

int totalBytes = 1;
int usedBytes = 0;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController ipController =
      TextEditingController(text: "192.168.43.100");

  final TextEditingController portController =
      TextEditingController(text: "12345");

  final TextEditingController messageController = TextEditingController();

  Socket? socket;
  String status = "Disconnected";

  Future<void> connect() async {
    try {
      socket = await Socket.connect(
        ipController.text,
        int.parse(portController.text),
        timeout: const Duration(seconds: 5),
      );

      setState(() {
        status = "Connected";
      });

      socket!.listen(
        (data) {
          String message = String.fromCharCodes(data);

          print(message);

          if (message.startsWith("STORAGE|")) {
            final parts = message.split('|');

            setState(() {
              totalBytes = int.parse(parts[1]);
              usedBytes = int.parse(parts[2]);
            });
          }
        },
        onDone: () {
          setState(() {
            status = "Disconnected";
          });
        },
      );
    } catch (e) {
      setState(() {
        status = "Connection failed";
      });

      print(e);
    }
  }

  Future<File> generateTtsMp3(String text) async {
    final dir = await getTemporaryDirectory();

    final mp3File = File("${dir.path}/tts.mp3");

    final url =
        "https://translate.google.com/translate_tts"
        "?ie=UTF-8"
        "&client=tw-ob"
        "&tl=id"
        "&q=${Uri.encodeComponent(text)}";

    final response = await http.get(
      Uri.parse(url),
      headers: {
        "User-Agent":
            "Mozilla/5.0",
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        "TTS failed: ${response.statusCode}",
      );
    }

    await mp3File.writeAsBytes(
      response.bodyBytes,
    );

    print(
      "MP3 size: ${await mp3File.length()} bytes",
    );

    return mp3File;
  }

  Future<void> sendText() async {
    if (socket == null) {
      print("Socket not connected");
      return;
    }

    final text = messageController.text.trim();

    if (text.isEmpty) {
      return;
    }

    try {
      final mp3File = await generateTtsMp3(text);

      final bytes = await mp3File.readAsBytes();

      socket!.write(
        "AUDIO|reminder.mp3|${bytes.length}\n",
      );

      socket!.add(bytes);

      await socket!.flush();

      print(
        "Sent ${bytes.length} bytes",
      );
    } catch (e) {
      print(e);
    }
  }

  void disconnect() {
    socket?.destroy();
    socket = null;

    setState(() {
      status = "Disconnected";
    });
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
        title: const Text("Settings"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: "ESP IP Address",
              ),
            ),

            TextField(
              controller: portController,
              decoration: const InputDecoration(
                labelText: "Port",
              ),
            ),

            const SizedBox(height: 20),

            Text(
              "Status: $status",
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: connect,
              child: const Text("Connect"),
            ),

            ElevatedButton(
              onPressed: disconnect,
              child: const Text("Disconnect"),
            ),

            const Divider(),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Storage Wemos"),
                LinearProgressIndicator(
                  value: usedBytes / totalBytes,
                ),
                const SizedBox(height: 8),
                Text(
                    "${(usedBytes / 1024).toStringAsFixed(1)} KB / "
                    "${(totalBytes / 1024).toStringAsFixed(1)} KB"),
                Text(
                    "Free: ${((totalBytes - usedBytes) / 1024).toStringAsFixed(1)} KB"),
              ],
            ),

            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: "Message",
              ),
            ),

            ElevatedButton(
              onPressed: sendText,
              child: const Text("Generate TTS"),
            ),
          ],
        ),
      ),
    );
  }
}