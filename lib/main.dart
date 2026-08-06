import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'core/config/app_colors.dart';
import 'core/config/app_config.dart';
import 'core/services/network_manager.dart';
import 'core/storage/cache_manager.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'shared/widgets/app_shell.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ต้องมาก่อน updateBaseUrl — heartbeat แรกส่ง agentVersion ไปด้วย ถ้ายังไม่ init
  // จะรายงานค่าว่างให้ backend แล้วหน้า Hardware จะโชว์ '-' จนกว่าจะ heartbeat รอบถัดไป
  await AppConfig.init();
  await NetworkManager.instance.updateBaseUrl();

  // Windows: กด X → ย่อลง system tray (mini bar) แทนปิดโปรแกรม (agent ต้องรันต่อเนื่อง)
  // macOS มี behavior นี้อยู่แล้วผ่าน NSStatusBar + custom close() ใน MainFlutterWindow.swift
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true); // ดัก close (ปุ่ม X) เพื่อ hide แทน quit
    await _setupTray();
  }

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

// Windows system-tray (mini bar): ไอคอน + เมนู Show / Quit
Future<void> _setupTray() async {
  await trayManager.setIcon('assets/tray_icon.ico');
  await trayManager.setToolTip(AppConfig.appName);
  await trayManager.setContextMenu(Menu(items: [
    MenuItem(key: 'show', label: 'Show ${AppConfig.appName}'),
    MenuItem.separator(),
    MenuItem(key: 'exit', label: 'Quit ${AppConfig.appName}'),
  ]));
}

class MyarapApp extends StatefulWidget {
  const MyarapApp({super.key});

  @override
  State<MyarapApp> createState() => _MyarapAppState();
}

/// ThemeData จาก palette เดียว — ให้สว่าง/มืดใช้โครงเดียวกัน ต่างแค่ค่าสี
ThemeData _theme(AppPalette c) => ThemeData(
      useMaterial3: true,
      brightness: c.isDark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.violet,
        primary: c.violet,
        surface: c.card,
        brightness: c.isDark ? Brightness.dark : Brightness.light,
      ),
      scaffoldBackgroundColor: c.bg,
      dividerColor: c.line,
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      // แบบ A ไม่มี app bar แล้ว (ใช้เมนูซ้ายแทน) — เหลือไว้เผื่อ dialog/หน้าต่างย่อย
      appBarTheme: AppBarTheme(
        backgroundColor: c.card,
        foregroundColor: c.ink,
        elevation: 0,
      ),
    );

class _MyarapAppState extends State<MyarapApp> with WindowListener, TrayListener {
  static const _windowChannel = MethodChannel('com.myarap/window');

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this); // ดัก onWindowClose (ปุ่ม X)
      trayManager.addListener(this); // ดักคลิก tray icon/เมนู
    }
    if (Platform.isMacOS) {
      _windowChannel.setMethodCallHandler(_handleWindowCall);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  // Windows: กดปุ่ม X (setPreventClose=true จึงไม่ปิด) → ซ่อนหน้าต่างลง tray
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  // Windows: คลิกซ้ายที่ tray icon → เรียกหน้าต่างกลับมา
  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  // Windows: คลิกขวาที่ tray icon → เปิด context menu (Show / Quit)
  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'exit':
        // ปิดจริง: ปลด preventClose ก่อน แล้ว destroy หน้าต่าง + ลบ tray icon
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
        break;
    }
  }

  Future<void> _handleWindowCall(MethodCall call) async {
    switch (call.method) {
      case 'openSetting':
        // สลับหน้าในคอนโซล ไม่ push หน้าซ้อน — เมนูซ้ายต้องอยู่ในสายตาเสมอ
        await windowManager.show();
        await windowManager.focus();
        requestedSection.value = AppSection.settings;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      // ตามโหมดของระบบปฏิบัติการ — โปรแกรมค้างบนเครื่องทั้งวัน ควรกลืนกับ OS
      themeMode: ThemeMode.system,
      theme: _theme(AppColors.light),
      darkTheme: _theme(AppColors.dark),
      home: const HomeScreen(),
    );
  }
}
