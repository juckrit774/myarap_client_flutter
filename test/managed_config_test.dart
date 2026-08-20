import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:myarap/core/config/managed_config.dart';

/// ค่าที่ผู้ดูแลตั้งไว้ระดับเครื่องต้อง **ชนะ** ค่าที่ผู้ใช้ตั้งเอง (AG-SEC-08)
/// เทสนี้ครอบเฉพาะเส้นทาง macOS (ไฟล์) — ฝั่ง Windows อ่าน registry ผ่าน `reg.exe`
/// ซึ่งทดสอบบนเครื่องนี้ไม่ได้
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('myarap_mc');
    ManagedConfig.macPath = '${tmp.path}/server_url';
    ManagedConfig.resetForTest();
  });
  tearDown(() async => tmp.delete(recursive: true));

  test('ไม่มีไฟล์ = ไม่ได้กำหนด (ผู้ใช้ตั้งเองได้เหมือนเดิม)', () async {
    expect(await ManagedConfig.serverUrl(), isNull);
  });

  test('มีไฟล์ = คืนค่านั้น และตัดช่องว่าง/บรรทัดใหม่ทิ้ง', () async {
    await File(ManagedConfig.macPath).writeAsString('  https://myarap.example \n');
    expect(await ManagedConfig.serverUrl(), 'https://myarap.example');
  });

  test('ไฟล์ว่าง = ถือว่าไม่ได้กำหนด ไม่ใช่ URL ว่างที่ทำให้ agent ยิงไปไหนไม่ได้', () async {
    await File(ManagedConfig.macPath).writeAsString('   \n');
    expect(await ManagedConfig.serverUrl(), isNull);
  });

  test('อ่านครั้งเดียวแล้วจำไว้ — แก้ไฟล์ทีหลังไม่มีผลจนกว่าจะ restart', () async {
    await File(ManagedConfig.macPath).writeAsString('https://a.example');
    expect(await ManagedConfig.serverUrl(), 'https://a.example');
    await File(ManagedConfig.macPath).writeAsString('https://b.example');
    expect(await ManagedConfig.serverUrl(), 'https://a.example');
  });
}
