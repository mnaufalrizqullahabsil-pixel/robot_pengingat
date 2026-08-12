import 'package:flutter/material.dart';
import 'pages/alarm_list_page.dart';
import 'services/tcp_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Auto-connect pada startup menggunakan pengaturan tersimpan
  final (ip, port) = await TcpService.loadSettings();
  TcpService.instance.connect(ip, port);

  runApp(const RobotPengingatApp());
}

class RobotPengingatApp extends StatelessWidget {
  const RobotPengingatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Robot Pengingat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary:   Color(0xFF4F8EF7),
          secondary: Color(0xFFFFC857),
          surface:   Color(0xFF1C2333),
          error:     Color(0xFFFF5C5C),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1117),
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
        ),
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white),
        ),
      ),
      home: const AlarmListPage(),
    );
  }
}