class AppConfig {
  AppConfig._();

  static const appName = 'MYARAP';
  // version เดียวทั้งแอป — ต้อง bump ให้ตรงกับ pubspec.yaml (version: x.y.z+build)
  static const appVersion = '3.0.0';
  static const buildNumber = '1';
  static const apiVersion = '1.0.1'; // V2 legacy (kept for reference)
  static const agentVersion = appVersion; // payload V3 ใช้ตัวเดียวกับหน้า Settings
  static const baseUrl = 'https://localhost:8000';
}
