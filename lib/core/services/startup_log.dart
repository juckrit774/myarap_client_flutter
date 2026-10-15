import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// log ช่วงเปิดโปรแกรม — ไว้ไล่อาการ "เปิดแล้ว (Not Responding) แล้วปิดตัวเอง" บน Windows
///
/// ไฟล์: `%TEMP%\myarap-startup.log` (รอบก่อนหน้าย้ายไปเป็น `.prev.log` — เครื่องที่พังแล้วถูกเปิดใหม่
/// จะยังเหลือ log ของรอบที่พังให้ดู)
///
/// 🔴 **ทำไมต้องมี**: Flutter 3.44 บน Windows รวม UI thread กับ platform thread เป็นเธรดเดียว
/// โค้ด Dart ที่บล็อกนาน = หน้าต่าง Not Responding ทันที แต่ไม่มี error อะไรให้เห็นเลย
/// แล้วพอแอปถูกปิด powershell ลูกที่ค้างท่ออยู่ก็ล้มด้วย 0xE0434352 ตามไปบังต้นเหตุ
/// (เจอจริงบนเครื่องที่ลง MSI 1.0.0.25 ครั้งแรก — 2026-10-15)
///
/// อ่าน log ยังไง:
///   - บรรทัดสุดท้ายก่อนเงียบ = ขั้นที่ค้าง
///   - `STALL` = เธรดหลักไม่ได้ทำงานตามนาฬิกาเกิน 2 วินาที (บอกว่าค้างนานแค่ไหน)
///   - `ps:<ชื่อ> start` ที่ไม่มี `end` ตามมา = สคริปต์ PowerShell ที่ยังรันอยู่ตอนแอปตาย
///
/// ⚠️ ไม่มีความลับในไฟล์นี้ — ห้าม log token / body ของ request (บทเรียน AG-SEC-07)
class StartupLog {
  StartupLog._();

  /// ช่วงที่ log ทุกอย่าง — หลังจากนี้ trace เฉพาะงานที่ช้าผิดปกติหรือ error
  /// (polling USB 15 วิ / foreground app 60 วิ จะได้ไม่ทำไฟล์บวมทั้งวัน)
  static const _verboseWindow = Duration(minutes: 10);
  static const _slowAfterWindow = Duration(seconds: 30);
  static const _stallThreshold = Duration(seconds: 2);
  static const _watchdogFor = Duration(minutes: 10);

  static File? _file;
  static final _t0 = DateTime.now();

  static bool get _verbose => DateTime.now().difference(_t0) < _verboseWindow;

  /// เรียกบรรทัดแรกของ main() — ก่อนทุกอย่าง
  static void init() {
    try {
      final dir = Directory.systemTemp.path;
      final sep = Platform.pathSeparator;
      final f = File('$dir${sep}myarap-startup.log');
      if (f.existsSync()) {
        f.copySync('$dir${sep}myarap-startup.prev.log');
      }
      f.writeAsStringSync('');
      _file = f;
    } catch (_) {
      _file = null; // เขียนไม่ได้ต้องไม่ทำให้แอปเปิดไม่ขึ้น
    }
    log('=== start pid=$pid os=${Platform.operatingSystemVersion}'
        ' user=${Platform.environment['USERNAME'] ?? '-'}');

    // error ที่ไม่มีใครจับ — จดลงไฟล์แล้วส่งต่อให้ handler เดิมทำงานตามปกติ
    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      log('FlutterError: ${details.exceptionAsString()}');
      prevFlutter?.call(details);
    };
    final prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      log('Uncaught: $error\n$stack');
      return prevPlatform?.call(error, stack) ?? false;
    };

    _startWatchdog();
  }

  static void log(String msg) {
    final ms = DateTime.now().difference(_t0).inMilliseconds;
    final line = '${DateTime.now().toIso8601String()} +${ms}ms  $msg';
    debugPrint('[STARTUP] $line');
    final f = _file;
    if (f == null) return;
    try {
      f.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// log ขั้นเริ่ม/จบของงาน async พร้อมเวลาที่ใช้ — ผลเป็น ProcessResult จะจด exit code ด้วย
  /// หลังพ้นช่วงแรกจะจดเฉพาะงานที่ช้าเกิน 30 วินาทีหรือ throw
  static Future<T> trace<T>(String tag, Future<T> Function() fn) async {
    final verbose = _verbose;
    final sw = Stopwatch()..start();
    if (verbose) log('$tag start');
    try {
      final r = await fn();
      final extra = r is ProcessResult
          ? ' exit=${r.exitCode}${r.exitCode != 0 ? ' stderr=${_short(r.stderr)}' : ''}'
          : '';
      if (verbose || sw.elapsed > _slowAfterWindow) {
        log('$tag end ${sw.elapsedMilliseconds}ms$extra');
      }
      return r;
    } catch (e) {
      log('$tag FAILED ${sw.elapsedMilliseconds}ms $e');
      rethrow;
    }
  }

  static String _short(Object? s) {
    final t = (s ?? '').toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 300 ? '${t.substring(0, 300)}…' : t;
  }

  /// นาฬิกาเดินทุก 1 วินาที — เธรดหลักถูกบล็อกเมื่อไร รอบถัดไปจะมาช้า แล้วจดเป็น STALL
  /// เดินแค่ช่วงแรก (ช่วงที่อาการเกิด) แล้วหยุดเอง
  static void _startWatchdog() {
    var last = DateTime.now();
    var ticks = 0;
    Timer.periodic(const Duration(seconds: 1), (t) {
      final now = DateTime.now();
      final gap = now.difference(last);
      if (gap > _stallThreshold + const Duration(seconds: 1)) {
        log('STALL main thread blocked ~${gap.inMilliseconds - 1000}ms');
      }
      last = now;
      if (++ticks % 30 == 0) log('alive');
      if (now.difference(_t0) > _watchdogFor) {
        log('watchdog stopped');
        t.cancel();
      }
    });
  }
}
