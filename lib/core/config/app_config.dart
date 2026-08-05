import 'package:package_info_plus/package_info_plus.dart';

class AppConfig {
  AppConfig._();

  static const appName = 'MYARAP';
  static const apiVersion = '1.0.1'; // V2 legacy (kept for reference)
  static const baseUrl = 'https://localhost:8000';

  // ── เวอร์ชัน ────────────────────────────────────────────────────────────────
  //
  // 🔴 **ห้าม hardcode เวอร์ชันที่นี่อีก** — เดิมเป็น const '3.0.0' ซึ่งเป็นเลขของ
  // pubspec (เวอร์ชันภายในของโปรเจกต์ Flutter) ไม่ใช่เลขของตัวติดตั้งที่ผู้ใช้เห็น
  // (macOS/MSI = 1.0.0.3) ทำให้หน้า Hardware แสดงเวอร์ชัน agent ผิดมาตลอด
  // และหลุดไม่ตรงกันซ้ำอีกทุกครั้งที่ bump เพราะต้องแก้ 5 ที่พร้อมกัน:
  //   pubspec.yaml · app_config.dart · AppInfo.xcconfig · product.wxs · setup.iss
  //
  // ตอนนี้อ่านจาก **bundle จริงตอน runtime** (CFBundleShortVersionString บน macOS /
  // FileVersion บน Windows) → ไม่มีทางไม่ตรงกับตัวติดตั้งได้อีก
  static String _version = '';
  static String _build = '';

  /// ต้องเรียกครั้งเดียวตอน start ก่อนใช้ [appVersion] — ถ้าไม่เรียกจะได้ค่าว่าง
  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _build = info.buildNumber;
    } catch (_) {
      // อ่านไม่ได้ = ปล่อยว่าง ดีกว่าโกหกด้วยเลขที่ hardcode ไว้
    }
  }

  /// เวอร์ชันที่ผู้ใช้เห็น — **normalize ให้เป็น 4 ส่วนเสมอทั้ง 2 แพลตฟอร์ม**
  ///
  /// ที่ต้อง normalize เพราะแต่ละ OS เก็บคนละแบบ:
  ///   macOS   CFBundleShortVersionString = MYARAP_DISPLAY_VERSION = "1.0.0.4" (4 ส่วนอยู่แล้ว)
  ///   Windows ProductVersion = FLUTTER_VERSION = ส่วนหน้า `+` ของ pubspec = "1.0.0"
  ///           ส่วน build number ("4") แยกมาอีกทาง
  /// ถ้าไม่รวมให้ตรงกัน เครื่อง Windows กับ macOS ที่ลงรุ่นเดียวกันจะโชว์คนละเลข
  static String get appVersion {
    if (_version.isEmpty) return '';
    if (_version.split('.').length >= 4) return _version; // macOS
    if (_build.isEmpty) return _version;
    return '\$_version.\$_build';                          // Windows: 1.0.0 + 4 → 1.0.0.4
  }

  static String get buildNumber => _build;

  /// เวอร์ชันที่ agent รายงานให้ backend (payload V3) — ตัวเดียวกับที่แสดงใน Settings
  static String get agentVersion => appVersion;
}
