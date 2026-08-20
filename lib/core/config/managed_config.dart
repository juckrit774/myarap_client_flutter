import 'dart:io';

/// ค่าที่ **ผู้ดูแลระบบตั้งไว้ระดับเครื่อง** — ผู้ใช้ทั่วไปแก้ไม่ได้
///
/// 🔴 **ทำไมต้องมี**: เดิม `server_url` อยู่ใน SharedPreferences และแก้ได้จากหน้าตั้งค่า
/// **โดยไม่ต้องมีสิทธิ์ผู้ดูแล** ผู้ที่มีสิทธิ์ผู้ใช้ธรรมดาบนเครื่องนั้นจึงชี้ agent
/// ไปเซิร์ฟเวอร์ของตัวเองได้ แล้วส่ง deploy job พร้อมตัวติดตั้งของตัวเองเข้ามา
/// ผู้ใช้จะเห็นกล่อง UAC ที่ดูเหมือนการติดตั้งซอฟต์แวร์ปกติของ MYARAP → กด Yes
/// = ผู้โจมตีได้สิทธิ์ Administrator (AG-SEC-08 / BUG-120 ของ MYARAP-NEW)
///
/// ที่เก็บ (เขียนได้เฉพาะผู้ดูแลระบบ):
///   Windows  `HKLM\SOFTWARE\ARSoft\MyARAP` ค่า `ServerUrl` — MSI เขียนให้ตอนติดตั้ง
///            (`msiexec /i MyARAP.msi MYARAP_SERVER_URL=https://myarap.example`)
///   macOS    `/Library/Application Support/MyARAP/server_url` (ไฟล์ข้อความบรรทัดเดียว)
///
/// ⚠️ **ไม่มีค่า = ไม่ล็อก** — ยังใช้ค่าจาก SharedPreferences เหมือนเดิม เพื่อให้เครื่อง dev
/// และการติดตั้งด้วยมือยังตั้งค่าเองได้ · การล็อกจึงเป็นสิ่งที่ผู้ดูแล "เปิดใช้" ตอน rollout
/// ไม่ใช่สิ่งที่ทำให้ของที่ใช้อยู่พังทันที
class ManagedConfig {
  ManagedConfig._();

  static String? _cached;
  static bool _read = false;

  /// ที่อยู่ไฟล์ฝั่ง macOS — แยกเป็นตัวแปรเพื่อให้เทสชี้ไปที่ temp dir ได้
  /// (ของจริงอยู่ใต้ `/Library` ซึ่งเขียนได้เฉพาะ root — ซึ่งคือทั้งหมดของเรื่องนี้)
  static String macPath = '/Library/Application Support/MyARAP/server_url';

  /// ล้างค่าที่จำไว้ — ใช้ในเทสเท่านั้น
  static void resetForTest() {
    _cached = null;
    _read = false;
  }

  /// URL ที่ถูกกำหนดไว้ระดับเครื่อง — `null` = ไม่ได้กำหนด (ผู้ใช้ตั้งเองได้)
  ///
  /// อ่านครั้งเดียวแล้วจำไว้ — ค่านี้เปลี่ยนได้เฉพาะตอนติดตั้ง/แก้ registry ซึ่งต้อง
  /// restart agent อยู่แล้ว การอ่านซ้ำทุกครั้งที่เปิดหน้าตั้งค่าจึงเป็นการเสียเวลาเปล่า
  static Future<String?> serverUrl() async {
    if (_read) return _cached;
    _read = true;
    try {
      if (Platform.isWindows) {
        _cached = await _fromRegistry();
      } else if (Platform.isMacOS) {
        _cached = await _fromFile();
      }
    } catch (_) {
      // อ่านไม่ได้ = ถือว่าไม่ได้กำหนด ดีกว่าทำให้ agent เปิดไม่ขึ้น
    }
    return _cached;
  }

  /// ใช้ `reg.exe` ไม่ใช่ PowerShell — เร็วกว่ามากและเส้นทางนี้อยู่บน startup path
  static Future<String?> _fromRegistry() async {
    final r = await Process.run(
      'reg',
      [r'query', r'HKLM\SOFTWARE\ARSoft\MyARAP', '/v', 'ServerUrl'],
      stdoutEncoding: const SystemEncoding(),
    );
    if (r.exitCode != 0) return null;
    // รูปแบบผลลัพธ์:  "    ServerUrl    REG_SZ    https://myarap.example"
    for (final line in r.stdout.toString().split('\n')) {
      final i = line.indexOf('REG_SZ');
      if (i >= 0) {
        final v = line.substring(i + 'REG_SZ'.length).trim();
        if (v.isNotEmpty) return v;
      }
    }
    return null;
  }

  static Future<String?> _fromFile() async {
    final f = File(macPath);
    if (!await f.exists()) return null;
    final v = (await f.readAsString()).trim();
    return v.isEmpty ? null : v;
  }
}
