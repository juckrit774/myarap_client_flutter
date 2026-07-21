import 'dart:io';
import 'dart:ui' show AppExitResponse; // ตัว enum ตอบ didRequestAppExit (มาจาก engine ไม่ได้ re-export ผ่าน material)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/config/app_colors.dart';
import 'core/config/app_config.dart';
import 'core/services/network_manager.dart';
import 'core/storage/cache_manager.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/settings/presentation/screens/settings_screen.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NetworkManager.instance.updateBaseUrl();

  NetworkManager.onUnauthorized = () {
    CacheManager.clear().then((_) {
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    });
  };

  runApp(const MyarapApp());
}

class MyarapApp extends StatefulWidget {
  const MyarapApp({super.key});

  @override
  State<MyarapApp> createState() => _MyarapAppState();
}

class _MyarapAppState extends State<MyarapApp> with WidgetsBindingObserver {
  static const _windowChannel = MethodChannel('com.myarap/window');

  @override
  void initState() {
    super.initState();
    // POC: ดักตอนแอปจะปิด (คลิก X บน Windows / Quit menu+⌘Q บน macOS) → ขอรหัส admin ก่อน
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isMacOS) {
      _windowChannel.setMethodCallHandler(_handleWindowCall);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ถูกเรียกเมื่อ OS ขอปิดแอป (window close/quit) — ปิดจริงเฉพาะเมื่อใส่รหัส admin ถูก
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    final ok = await _promptAdminPassword();
    return ok ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  Future<bool> _promptAdminPassword() async {
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return false; // ไม่มี UI ให้ถาม → ไม่ปิด (ปลอดภัยไว้ก่อน)
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dctx) {
        var wrong = false;
        return StatefulBuilder(
          builder: (dctx, setLocal) {
            void submit() {
              if (controller.text == AppConfig.adminClosePassword) {
                Navigator.of(dctx).pop(true);
              } else {
                setLocal(() => wrong = true);
              }
            }

            return AlertDialog(
              title: const Text('ปิดโปรแกรม MYARAP'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('กรุณาใส่รหัสผ่านผู้ดูแลระบบเพื่อปิดโปรแกรม'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    autofocus: true,
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      labelText: 'รหัสผ่าน admin',
                      errorText: wrong ? 'รหัสผ่านไม่ถูกต้อง' : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dctx).pop(false),
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
                  onPressed: submit,
                  child: const Text('ปิดโปรแกรม'),
                ),
              ],
            );
          },
        );
      },
    );
    return result ?? false;
  }

  Future<void> _handleWindowCall(MethodCall call) async {
    switch (call.method) {
      case 'openSetting':
        // Navigate to settings from anywhere in the app
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.mainPurple,
          primary: AppColors.mainPurple,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bgColor,
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.deepPurple,
          foregroundColor: Colors.white,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
