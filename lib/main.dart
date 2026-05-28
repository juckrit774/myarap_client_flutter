import 'dart:io';
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

class _MyarapAppState extends State<MyarapApp> {
  static const _windowChannel = MethodChannel('com.myarap/window');

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _windowChannel.setMethodCallHandler(_handleWindowCall);
    }
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
