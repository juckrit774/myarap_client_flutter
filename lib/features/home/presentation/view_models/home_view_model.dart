import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../../core/config/app_config.dart';
import '../../data/models/device_model.dart';
import '../../../auth/models/login_response_model.dart';
import '../../../../core/services/network_manager.dart';
import '../../../../core/storage/cache_manager.dart';
import '../../../../core/services/remote_input_windows.dart';

// heartbeat interval เมื่อ V3 ไม่ส่ง dueDateTime กลับมา
const _kHeartbeatInterval = Duration(minutes: 10);
// throttle: ส่ง lastApp เร็วสุดทุก 30 วินาที ป้องกัน spam ตอนสลับ app บ่อย
const _kAppChangeCooldown = Duration(seconds: 30);

class HomeViewModel extends ChangeNotifier {
  bool isLoading = true;
  String? errorMessage;
  String? updateErrorMessage; // แสดงเมื่อ PUT /v3/api/device ล้มเหลว
  String? assetUpdatedAt;

  // V3 auth result
  DeviceAuthResponse? _deviceAuth;
  DeviceDetail? deviceDetail;

  Timer? _heartbeatTimer;
  Timer? _appChangeCooldown;
  Timer? _windowsAppTimer;
  String _lastSentApp = '';

  static const _appEventChannel = EventChannel('com.myarap/app_events');

  // USB block policy — จาก allowUsb ที่ backend ส่งกลับใน response ของ PUT /v3/api/device
  // default = true (ไม่บล็อก) จนกว่าจะได้ policy จริงจาก heartbeat แรก
  bool _allowUsb = true;
  Timer? _usbPollTimer;
  Set<String> _knownUsbDrives = {};
  static const _usbEventChannel = EventChannel('com.myarap/usb_events');
  static const _usbControlChannel = MethodChannel('com.myarap/usb_control');

  // SSE policy stream — รับ policy change จาก backend แบบ real-time (ไม่รอ heartbeat)
  StreamSubscription? _policyStreamSub;
  Timer? _policyReconnect;

  // Remote Desktop — capture หน้าจอส่ง backend เมื่อ admin เปิด session
  static const _remoteChannel = MethodChannel('com.myarap/remote');
  static const _remoteEventChannel = EventChannel('com.myarap/remote_events');
  StreamSubscription? _remoteEventSub;
  Timer? _remoteCaptureTimer;
  bool _remoteCapturing = false;
  bool _remoteConsentPending = false; // consent dialog กำลังเปิดอยู่ — กัน remote_start ซ้ำเด้ง popup ซ้อน
  String _remoteSessionId = ''; // session ที่กำลัง active (ใช้ตอนผู้ใช้กด Disconnect เอง)
  Process? _winIndicatorProc;   // Windows: process ของ topmost banner form (kill ตอน stop)
  bool _winIndicatorStopByUs = false; // true = เรา kill เอง (normal stop); false = user กดปุ่มหยุด

  // WebRTC (low-latency upgrade) — สร้างเมื่อได้ SDP offer จาก viewer ผ่าน SSE
  RTCPeerConnection? _remotePc;
  MediaStream? _remoteScreenStream;
  // ตอน WebRTC ต่อติด: ลด HTTP frame upload เหลือ interval ช้า (fallback + keep-alive)
  static const _remoteFrameIntervalSlow = Duration(seconds: 3);
  // interval ระหว่างเฟรม (~2.5 fps) — สมดุลระหว่าง smoothness กับ bandwidth/CPU
  static const _remoteFrameInterval = Duration(milliseconds: 400);

  // Activity Monitor (Asset Detail card) — CPU/Memory/Energy/Disk/Network
  // 2 trigger: (1) periodic self-report ทุก 5 นาที (เก็บ daily avg ฝั่ง backend)
  //            (2) SSE "metrics_request" ตอน viewer เปิด Asset Detail (live pull ทันที)
  static const _metricsChannel = MethodChannel('com.myarap/metrics');
  static const _metricsInterval = Duration(minutes: 5);
  Timer? _metricsTimer;

  String get userName => deviceDetail?.computerName ?? _deviceAuth?.assetTag ?? 'MYARAP User';
  String get assetNo => _deviceAuth?.assetTag ?? '-';
  String? get profileImageUrl => null;
  DateTime? get lastUpdated => null;
  String? get accessToken => _deviceAuth?.accessToken;

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _appChangeCooldown?.cancel();
    _windowsAppTimer?.cancel();
    _usbPollTimer?.cancel();
    _policyStreamSub?.cancel();
    _policyReconnect?.cancel();
    _remoteCaptureTimer?.cancel();
    _remoteEventSub?.cancel();
    _winIndicatorProc?.kill();
    _stopWebrtc();
    _metricsTimer?.cancel();
    super.dispose();
  }

  Future<void> initialize() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    await Future.wait([
      _loadCachedAuth(),
      _loadDeviceInfo(),
    ]);

    // เริ่ม USB guard "ก่อน" authenticate เสมอ — เพราะ _authenticate() ยิง heartbeat แรกทันที
    // ซึ่งอาจได้ policy บล็อกกลับมาแล้วพยายาม sync USB ทันที (ต้องมี native DASession
    // พร้อมใช้งานแล้วก่อน ไม่งั้น sync แรกจะเงียบหายเพราะ session ยังไม่ถูกสร้าง —
    // เจอบั๊กนี้จริงจากการทดสอบบนเครื่องจริง: debug log แสดง "session is nil" ตอน
    // setAllowUsb ถูกเรียกจาก heartbeat แรกก่อน EventChannel เริ่ม listen)
    if (Platform.isMacOS) _listenUsbEventsMac();
    if (Platform.isWindows) _startWindowsUsbPolling();
    if (Platform.isMacOS) _listenRemoteEvents();

    await _authenticate();

    // ต่อ SSE policy stream ค้างไว้ — backend push allowUsb ทันทีที่ admin toggle
    // (heartbeat 10 นาทียังทำงานเป็น fallback sync ตามเดิม)
    _startPolicyStream();

    // เริ่ม listen event app เปลี่ยน
    if (Platform.isMacOS) _listenAppEvents();
    if (Platform.isWindows) _startWindowsAppPolling();

    // Activity Monitor periodic self-report (เก็บ daily avg ฝั่ง backend ทุกรอบ) — ทั้ง 2 platform
    if (Platform.isMacOS || Platform.isWindows) _startMetricsTimer();

    isLoading = false;
    notifyListeners();
  }

  Future<void> _loadCachedAuth() async {
    final cached = await CacheManager.getDeviceAuth();
    if (cached != null) {
      _deviceAuth = DeviceAuthResponse.fromJson(cached);
      // restore token ให้ NetworkManager ใช้ได้ทันทีโดยไม่ต้อง re-auth
      NetworkManager.instance.setAccessToken(_deviceAuth!.accessToken);
    }
  }

  Future<void> _loadDeviceInfo() async {
    deviceDetail = await DeviceDetail.collect();
  }

  Future<void> _authenticate() async {
    final d = deviceDetail;
    if (d == null) return;

    // fingerprint = serialNumber (หรือ hardwareUUID ถ้า serial ว่าง)
    final fingerprint = d.serialNumber.isNotEmpty ? d.serialNumber : d.hardwareUUID;
    if (fingerprint.isEmpty) {
      errorMessage = 'ไม่พบ fingerprint ของเครื่อง';
      return;
    }

    try {
      final data = await NetworkManager.instance.postV3Public(
        '/v3/api/auth',
        {'fingerprint': fingerprint},
      );
      _deviceAuth = DeviceAuthResponse.fromJson(data);
      NetworkManager.instance.setAccessToken(_deviceAuth!.accessToken);
      await CacheManager.saveAccessToken(_deviceAuth!.accessToken);
      await CacheManager.saveRefreshToken(_deviceAuth!.refreshToken);
      await CacheManager.saveDeviceAuth(_deviceAuth!.toJson());

      // รายงาน hardware info ทันทีหลัง auth สำเร็จ
      await _updateDeviceInfo();
    } catch (_) {
      // ใช้ cached auth ถ้ามี — offline fallback
      if (_deviceAuth == null) {
        errorMessage = 'ไม่สามารถเชื่อมต่อได้ กรุณาตรวจสอบ Server URL';
      }
    }
  }

  Future<void> _updateDeviceInfo() async {
    final d = deviceDetail;
    if (d == null) return;

    try {
      final resp = await NetworkManager.instance.putV3('/v3/api/device', _buildDevicePayload(d));
      final allow = resp['allowUsb'];
      if (allow is bool) await _applyUsbPolicy(allow);

      updateErrorMessage = null;
      final now = DateTime.now();
      assetUpdatedAt =
          '${now.month}/${now.day}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')} '
          '${now.hour >= 12 ? 'PM' : 'AM'}';
      notifyListeners();

      // รายงาน installed software (opt-in)
      await _reportSoftware(d);

      // ตั้ง heartbeat ถัดไปด้วย fixed interval (V3 ไม่ส่ง dueDateTime กลับมา)
      _scheduleHeartbeat();
    } catch (e) {
      // server unreachable หรือ error — แสดงข้อความและลองใหม่ตาม heartbeat schedule
      updateErrorMessage = e.toString().contains('unauthorized')
          ? 'Token หมดอายุ — กรุณาเปิดแอปใหม่'
          : 'อัปเดตข้อมูลเครื่องไม่สำเร็จ (${e.runtimeType})';
      notifyListeners();
      _scheduleHeartbeat();
    }
  }

  Future<void> _reportSoftware(DeviceDetail d) async {
    if (d.applications.isEmpty) return;
    try {
      final items = d.applications
          .map((app) => {
                'name': app.name,
                'vendor': '',
                'version': app.version,
                'size': app.size,
              })
          .toList();
      await NetworkManager.instance.putV3('/v3/api/device/software', {'software': items});
    } catch (_) {
      // ไม่ block — software report เป็น optional
    }
  }

  void _scheduleHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer(_kHeartbeatInterval, () => _updateDeviceInfo());
  }

  // รับ event เมื่อ frontmost app เปลี่ยน แล้ว throttle 30s ก่อนส่ง
  void _listenAppEvents() {
    _appEventChannel.receiveBroadcastStream().listen((event) {
      final app = (event as Map)['app'] as String? ?? '';
      if (app.isEmpty) return;
      _appChangeCooldown?.cancel();
      _appChangeCooldown = Timer(_kAppChangeCooldown, () => _sendLastApp(app));
    }, onError: (_) {});
  }

  Future<void> _sendLastApp(String app) async {
    try {
      await NetworkManager.instance.putV3('/v3/api/device', {'lastApp': app});
    } catch (_) {}
  }

  // Windows: poll foreground app ทุก 60s ผ่าน PowerShell Win32 API
  void _startWindowsAppPolling() {
    // ⚠️ script เดิมพัง 2 จุด (ไม่เคยรันสำเร็จ — Windows ไม่มี lastApp เลย):
    //   1. `$pid` เป็น automatic read-only variable ของ PowerShell → assign แล้ว error
    //   2. ต่อ string ข้ามบรรทัดด้วย `+` ที่ "ต้นบรรทัดถัดไป" ไม่ทำงานใน PowerShell
    //      (statement จบตั้งแต่บรรทัดแรก) → signature ได้ครึ่งเดียว Add-Type พัง
    // แก้: here-string + $procId; ส่งชื่อโปรแกรม (Description/ProcessName) แทน window title
    // ให้ semantic ตรงกับ macOS ที่ส่ง localizedName ของแอป
    _windowsAppTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      const script = r'''
$ErrorActionPreference = 'SilentlyContinue'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W32Fg {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint procId);
}
"@
$h = [W32Fg]::GetForegroundWindow()
$procId = [uint32]0
[W32Fg]::GetWindowThreadProcessId($h, [ref]$procId) | Out-Null
$p = Get-Process -Id $procId -ErrorAction SilentlyContinue
if ($p) {
  if ($p.Description) { $p.Description } else { $p.ProcessName }
}
''';
      try {
        final proc = await Process.run(
          'powershell',
          _psArgs(script, hidden: true),
          stdoutEncoding: const SystemEncoding(),
        );
        final app = proc.stdout.toString().trim();
        if (app.isNotEmpty && app != _lastSentApp) {
          _lastSentApp = app;
          await _sendLastApp(app);
        }
      } catch (_) {}
    });
  }

  // ── USB block guard ───────────────────────────────────────
  //
  // ⚠️ ยังไม่ได้ทดสอบบนฮาร์ดแวร์จริง (ไม่มีเครื่อง test USB ในรอบนี้) — เขียนตาม
  // API contract ของ native side (macOS DiskArbitration / Windows PowerShell) เท่านั้น

  // sync policy ปัจจุบันไปที่ native side ทันทีที่ค่าเปลี่ยน
  // macOS = DiskArbitration (native plugin); Windows = registry veto + active dismount (PowerShell)
  Future<void> _applyUsbPolicy(bool allow) async {
    if (_allowUsb == allow) return;
    _allowUsb = allow;
    if (Platform.isMacOS) {
      try {
        await _usbControlChannel.invokeMethod('setAllowUsb', {'allow': allow});
      } catch (_) {}
    } else if (Platform.isWindows) {
      await _applyWindowsUsbPolicy(!allow); // block = !allow
    }
  }

  // Windows USB policy — **revert กลับแบบ Shell Eject verb (2026-07-16 ตาม user สั่ง)**:
  // block = eject drive ออกจริง (Safely Remove) — user ทดสอบจริงยืนยันว่าทำงาน โดยไม่ต้อง admin.
  // unblock = clear state + best-effort pnputil rescan; **drive ไม่ mount กลับเอง ต้องถอด-เสียบใหม่**
  // (ข้อจำกัดที่ user ยอมรับ — เหมือน macOS).
  //
  // ⚠️ ประวัติ: เคยเปลี่ยนเป็น Disable/Enable-PnpDevice เพื่อให้ unblock remount เองได้ แต่
  //    ต้องรัน Administrator (UAC ตอนเปิดแอป) + block ล้มเหลวในการทดสอบจริงรอบแรก —
  //    user สั่งย้อนกลับมาแบบนี้ (Block ทำงานแน่ ไม่มี UAC) แลกกับ unblock ต้องถอด-เสียบ
  Future<void> _applyWindowsUsbPolicy(bool block) async {
    if (block) {
      // eject drive ที่ mount ค้างอยู่แล้วทันที (device หายจาก Explorer)
      await _dismountAllWindowsRemovable();
    } else {
      // best-effort rescan — device ที่ถูก eject ส่วนใหญ่ไม่กลับมาเอง (hardware-level removal)
      // แต่ไม่มีโทษ; drive กลับมาแน่นอนเมื่อถอด-เสียบใหม่
      try {
        await Process.run('pnputil', ['/scan-devices']);
      } catch (_) {}
    }
  }

  // Eject drive ออกจริง (Safely Remove Hardware) ผ่าน Shell verb — device หายจาก Explorer สนิท
  // (ต่างจาก mountvol /P ที่แค่ dismount → ยังเห็น icon แต่เปิดไม่ได้). ไม่ลบ/format ข้อมูลใดๆ
  // ⚠️ verb name ต่างตาม locale (EN "Eject" / TH "นำสื่อออก"/"นำออก") → loop verbs match pattern
  //    ปลอดภัยกว่า InvokeVerb("Eject") ตรงๆ; fallback InvokeVerb + mountvol /P ถ้า eject ไม่ได้
  Future<void> _ejectWindowsDrive(String letter) async {
    final l = letter.replaceAll(':', '').replaceAll('\\', '');
    final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
\$sh = New-Object -ComObject Shell.Application
\$item = \$sh.Namespace(17).ParseName("$l:")
if (\$item) {
  \$done = \$false
  foreach (\$v in \$item.Verbs()) {
    \$n = \$v.Name -replace '&',''
    if (\$n -match 'Eject|นำสื่อออก|นำออก|ดีดออก') { \$v.DoIt(); \$done = \$true; break }
  }
  if (-not \$done) { \$item.InvokeVerb("Eject") }
}
''';
    try {
      await Process.run('powershell', _psArgs(script, hidden: true));
    } catch (_) {}
    // เผื่อ eject verb ไม่ทำงาน (บาง drive/บาง Windows) — dismount + กัน remount เป็น fallback
    try {
      await Process.run('mountvol', ['$l:\\', '/P']);
    } catch (_) {}
  }

  // ไล่ eject ทุก removable drive ที่ mount อยู่ตอนนี้ + รายงาน (เรียกตอน policy flip → block)
  Future<void> _dismountAllWindowsRemovable() async {
    const script = r'''
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" | ForEach-Object { "$($_.DeviceID)|$($_.VolumeName)" }
''';
    try {
      final proc = await Process.run('powershell',
          _psArgs(script, hidden: true),
          stdoutEncoding: const SystemEncoding());
      final lines = proc.stdout.toString().split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
      for (final line in lines) {
        final parts = line.split('|');
        final letter = parts.isNotEmpty ? parts[0].trim() : '';
        if (letter.isEmpty) continue;
        final label = parts.length > 1 ? parts[1].trim() : '';
        await _ejectWindowsDrive(letter); // eject ออกจริง (Safely Remove)
        await _reportUsbBlock(label.isNotEmpty ? label : letter);
      }
    } catch (_) {}
  }

  // macOS: native (DiskArbitration) eject แล้วส่ง event กลับมาผ่าน EventChannel
  void _listenUsbEventsMac() {
    _usbEventChannel.receiveBroadcastStream().listen((event) async {
      final map = event as Map;
      final device = map['device'] as String? ?? 'Unknown USB device';
      await _reportUsbBlock(device);
    }, onError: (_) {});
  }

  // Windows: poll removable drive list ทุก 15s ผ่าน PowerShell (ไม่มี native plugin)
  // เจอ drive letter ใหม่ระหว่าง 2 รอบ + policy บล็อกอยู่ → Disable-PnpDevice (จับ device ที่เสียบใหม่
  // ระหว่าง blocked ที่หลุดรอด real-time SSE — เช่น เสียบตอน stream หลุด). idempotent
  void _startWindowsUsbPolling() {
    const script = r'''
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" | ForEach-Object { "$($_.DeviceID)|$($_.VolumeName)" }
''';
    _usbPollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final proc = await Process.run(
          'powershell',
          _psArgs(script, hidden: true),
          stdoutEncoding: const SystemEncoding(),
        );
        final lines = proc.stdout
            .toString()
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty);

        final current = <String, String>{}; // driveLetter -> volumeLabel
        for (final line in lines) {
          final parts = line.split('|');
          final letter = parts.isNotEmpty ? parts[0].trim() : '';
          if (letter.isEmpty) continue;
          current[letter] = parts.length > 1 ? parts[1].trim() : '';
        }

        final newLetters = current.keys.where((k) => !_knownUsbDrives.contains(k));
        // มี USB drive ใหม่โผล่ระหว่าง blocked → eject ออก (Safely Remove) + รายงาน
        for (final letter in newLetters) {
          if (!_allowUsb) {
            final label = current[letter] ?? '';
            final deviceName = label.isNotEmpty ? label : letter;
            await _ejectWindowsDrive(letter);
            await _reportUsbBlock(deviceName);
          }
        }
        _knownUsbDrives = current.keys.toSet();
      } catch (_) {}
    });
  }

  Future<void> _reportUsbBlock(String deviceName) async {
    try {
      await NetworkManager.instance.postV3('/v3/api/device/usb-block', {'deviceName': deviceName});
    } catch (_) {}
  }

  // ── Policy push stream (SSE) ──────────────────────────────
  //
  // ต่อ GET /v3/api/device/stream ค้างไว้ — backend push {"type":"policy","allowUsb":...}
  // ทันทีที่ admin เปลี่ยน USB policy ใน web UI. event "init" ตอน connect ส่งค่าปัจจุบัน
  // เสมอ ดังนั้น reconnect หลัง stream หลุดจะ sync ค่าล่าสุดได้เอง ไม่มี event ตกหล่น

  Future<void> _startPolicyStream() async {
    _policyReconnect?.cancel();
    await _policyStreamSub?.cancel();
    _policyStreamSub = null;
    try {
      final body = await NetworkManager.instance.openV3Stream('/v3/api/device/stream');
      String buf = '';
      _policyStreamSub = body.stream.listen((chunk) {
        buf += utf8.decode(chunk, allowMalformed: true);
        // SSE event คั่นด้วย blank line — สะสม buffer แล้วตัดทีละ event
        int idx;
        while ((idx = buf.indexOf('\n\n')) >= 0) {
          final rawEvent = buf.substring(0, idx);
          buf = buf.substring(idx + 2);
          for (final line in rawEvent.split('\n')) {
            if (!line.startsWith('data: ')) continue; // ข้าม keepalive comment (": ping")
            try {
              _handleStreamEvent(jsonDecode(line.substring(6)) as Map<String, dynamic>);
            } catch (_) {}
          }
        }
      },
          onError: (_) => _schedulePolicyReconnect(),
          onDone: _schedulePolicyReconnect,
          cancelOnError: true);
    } catch (_) {
      _schedulePolicyReconnect();
    }
  }

  void _schedulePolicyReconnect() {
    _policyReconnect?.cancel();
    _policyReconnect = Timer(const Duration(seconds: 10), _startPolicyStream);
  }

  // dispatch SSE event ตาม field "type" — init/policy (USB) + remote_start/remote_stop (Remote Desktop)
  void _handleStreamEvent(Map<String, dynamic> m) {
    // ทั้ง init และ policy มี allowUsb → sync USB policy (no-op ถ้าค่าเดิม)
    final allow = m['allowUsb'];
    if (allow is bool) _applyUsbPolicy(allow);

    switch (m['type']) {
      case 'remote_start':
        _onRemoteStart(m['sessionId'] as String? ?? '', m['by'] as String? ?? 'ผู้ดูแลระบบ');
        break;
      case 'remote_offer':
        _onRemoteOffer(m['sessionId'] as String? ?? '', m['sdp'] as String? ?? '');
        break;
      case 'remote_stop':
        _stopRemoteCapture();
        break;
      case 'remote_control_request':
        _onRemoteControlRequest(
            m['sessionId'] as String? ?? '', m['by'] as String? ?? 'ผู้ดูแลระบบ');
        break;
      case 'remote_control_revoke':
        _onRemoteControlRevoke();
        break;
      case 'metrics_request':
        // viewer เปิด Asset Detail → ขอวัดค่าตอนนี้เลย (Activity Monitor card, live pull)
        _collectAndSendMetrics();
        break;
      case 'deploy':
        // Part B (Deploy Job) — สั่ง install/uninstall software/patch จริงบนเครื่องนี้
        _handleDeployEvent(m);
        break;
    }
  }

  // ── Deploy Job (Part B) — install/uninstall software/patch จริง ──────────
  //
  // blast radius สูงสุดในระบบ (RCE โดยนิยาม) — verify checksum ก่อนรันเสมอ ไม่มีทาง skip,
  // report ผลกลับ backend ทุกครั้งไม่ว่าสำเร็จ/ล้มเหลว. privilege model (POC): prompt ผู้ใช้ที่
  // เครื่องทุกครั้ง (UAC บน Windows ผ่าน -Verb RunAs, "with administrator privileges" บน macOS)
  // — agent เองไม่ได้รัน elevated ถาวร ไม่มี fallback เงียบๆ ถ้า user ปฏิเสธ prompt = fail ตรงๆ

  Future<void> _handleDeployEvent(Map<String, dynamic> m) async {
    final jobId = m['jobId'] as String? ?? '';
    final action = m['action'] as String? ?? 'install';
    final installerUrl = m['installerUrl'] as String? ?? '';
    final installerChecksum = (m['installerChecksum'] as String? ?? '').toLowerCase();
    final ref = m['ref'] as String? ?? ''; // ชื่อ software (+version) — ใช้ uninstall by name
    if (jobId.isEmpty) return;
    if (!Platform.isWindows && !Platform.isMacOS) {
      await _reportDeployResult(jobId, 'failed', 'unsupported platform');
      return;
    }

    // uninstall — ไม่ต้องดาวน์โหลด installer; หา uninstall string จาก registry ด้วยชื่อ (ref)
    if (action == 'uninstall') {
      if (!Platform.isWindows) {
        await _reportDeployResult(jobId, 'failed', 'macOS uninstall not supported in this POC');
        return;
      }
      if (ref.isEmpty) {
        await _reportDeployResult(jobId, 'failed', 'ref (software name) required for uninstall');
        return;
      }
      final (ok, message) = await _uninstallWindowsByName(ref);
      await _reportDeployResult(jobId, ok ? 'succeeded' : 'failed', message);
      return;
    }

    // install — ต้องมี installer + checksum
    if (installerUrl.isEmpty || installerChecksum.isEmpty) return;
    String? filePath;
    try {
      filePath = await _downloadDeployFile(installerUrl, jobId);
      if (filePath == null) {
        await _reportDeployResult(jobId, 'failed', 'download failed');
        return;
      }
      final actualChecksum = await _sha256OfFile(filePath);
      if (actualChecksum != installerChecksum) {
        await _reportDeployResult(jobId, 'failed', 'checksum mismatch');
        return;
      }
      final (ok, message) = Platform.isWindows
          ? await _runWindowsDeploy(filePath, action)
          : await _runMacDeploy(filePath, action);
      await _reportDeployResult(jobId, ok ? 'succeeded' : 'failed', message);
    } catch (e) {
      await _reportDeployResult(jobId, 'failed', e.toString());
    } finally {
      if (filePath != null) {
        try {
          await File(filePath).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _reportDeployResult(String jobId, String status, String message) async {
    try {
      await NetworkManager.instance.postV3(
          '/v3/api/device/deploy-result', {'jobId': jobId, 'status': status, 'message': message});
    } catch (_) {}
  }

  Future<String?> _downloadDeployFile(String url, String jobId) async {
    try {
      final defaultExt = Platform.isWindows ? '.msi' : '.pkg';
      final uri = Uri.tryParse(url);
      final path = uri?.path ?? '';
      final ext = path.contains('.') ? path.substring(path.lastIndexOf('.')) : defaultExt;
      final savePath = '${Directory.systemTemp.path}${Platform.pathSeparator}myarap_deploy_$jobId$ext';
      final downloader = dio_pkg.Dio(dio_pkg.BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 5),
      ));
      await downloader.download(url, savePath);
      return savePath;
    } catch (_) {
      return null;
    }
  }

  Future<String> _sha256OfFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return sha256.convert(bytes).toString();
  }

  // Windows: msiexec /i (install) หรือ /x (uninstall) ผ่าน Start-Process -Verb RunAs (บังคับ
  // UAC prompt ทุกครั้ง) — capture exit code จริงผ่าน stdout JSON (0/3010 = success, อื่นๆ = fail).
  // ⚠️ ห้ามใช้ -WindowStyle Hidden ที่นี่: parent PowerShell ที่ hidden ทำให้ UAC prompt ของ
  // -Verb RunAs เด้งบน secure-desktop โดยไม่มี owner window ให้ focus → กดไม่ได้ → -Wait ค้าง
  // (เจอจริงตอน uninstall 7-Zip 2026-07-21). ปล่อยให้ window โผล่เพื่อให้ user กด UAC ได้.
  Future<(bool, String)> _runWindowsDeploy(String filePath, String action) async {
    final safePath = filePath.replaceAll("'", "''");
    // Windows patch (.msu) ใช้ wusa.exe — msiexec ติดตั้ง .msu ไม่ได้ (คนละ installer)
    // uninstall .msu ต้องระบุ KB number ไม่ใช่ไฟล์ → รองรับแค่ install patch
    final isMsu = filePath.toLowerCase().endsWith('.msu');
    String script;
    if (isMsu) {
      script = '''
try {
  \$p = Start-Process -FilePath wusa.exe -ArgumentList @('$safePath', '/quiet', '/norestart') -Verb RunAs -Wait -PassThru
  @{ code = \$p.ExitCode } | ConvertTo-Json -Compress
} catch {
  @{ code = -1; err = \$_.Exception.Message } | ConvertTo-Json -Compress
}
''';
    } else {
      final verb = action == 'uninstall' ? '/x' : '/i';
      script = '''
try {
  \$p = Start-Process -FilePath msiexec.exe -ArgumentList @('$verb', '$safePath', '/quiet', '/norestart') -Verb RunAs -Wait -PassThru
  @{ code = \$p.ExitCode } | ConvertTo-Json -Compress
} catch {
  @{ code = -1; err = \$_.Exception.Message } | ConvertTo-Json -Compress
}
''';
    }
    final proc = await Process.run('powershell', _psArgs(script),
        stdoutEncoding: const SystemEncoding());
    try {
      final out = Map<String, dynamic>.from(jsonDecode(proc.stdout.toString().trim()) as Map);
      final code = out['code'] as int? ?? -1;
      if (isMsu) {
        // wusa exit codes ต่างจาก msiexec:
        //   0 / 3010                   = success (3010 = ต้อง reboot)
        //   2359302 (0x240006)         = patch ติดตั้งอยู่แล้ว
        //   2359303 (0x240007)         = ไม่ applicable กับ OS นี้
        //   -2145124329 (0x80240017)   = WU_E_NOT_APPLICABLE (ไม่ตรง OS/prereq) — verified บนเครื่องจริง
        if (code == 0 || code == 3010) return (true, 'patch installed (exit $code)');
        if (code == 2359302) return (true, 'patch already installed');
        if (code == 2359303 || code == -2145124329) return (false, 'patch not applicable to this OS');
        return (false, out['err'] as String? ?? 'wusa exit code $code');
      }
      if (code == 0 || code == 3010) return (true, 'exit code $code');
      return (false, out['err'] as String? ?? 'exit code $code');
    } catch (_) {
      return (false, 'unexpected output: ${proc.stdout}');
    }
  }

  // Windows uninstall by name — ค้น (Quiet)UninstallString จาก registry (Uninstall keys 64/32-bit)
  // ด้วยชื่อ (DisplayName match). MSI → msiexec /x {GUID} /quiet; EXE → แยก exe+args แล้วรัน
  // (prefer QuietUninstallString ถ้ามี). ไม่ต้องดาวน์โหลด — ใช้ตัว uninstaller ที่ติดตั้งอยู่บนเครื่อง.
  Future<(bool, String)> _uninstallWindowsByName(String name) async {
    final safeName = name.replaceAll("'", "''").replaceAll('"', '');
    final script = '''
\$roots = @(
  'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
  'HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
  'HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*'
)
\$app = Get-ItemProperty \$roots -ErrorAction SilentlyContinue |
  Where-Object { \$_.DisplayName -like '*$safeName*' -and \$_.UninstallString } |
  Select-Object -First 1
if (-not \$app) { @{ code = -2; err = 'software not found: $safeName' } | ConvertTo-Json -Compress; exit }
\$q = \$app.QuietUninstallString
\$u = \$app.UninstallString
# prefer QuietUninstallString (คำสั่ง silent ที่ vendor เตรียมมา args ถูกต้อง) ถ้ามี ไม่งั้นใช้ UninstallString
\$cmd = if (\$q) { \$q } else { \$u }
try {
  if (\$cmd -match '(?i)msiexec') {
    # MSI: บังคับ /x + quiet (ไม่ว่า registry จะเป็น /I หรือ /X)
    \$guid = [regex]::Match(\$cmd, '\\{[0-9A-Fa-f\\-]+\\}').Value
    \$p = Start-Process msiexec.exe -ArgumentList @('/x', \$guid, '/quiet', '/norestart') -Verb RunAs -Wait -PassThru
  } else {
    # EXE uninstaller — UninstallString อาจเป็น "C:\\path with space\\setup.exe" /uninstall
    # ต้องแยก exe (ในเครื่องหมายคำพูด) ออกจาก arguments ที่ฝังมา ไม่งั้น Trim('"') เดิมทำ path พัง
    if (\$cmd -match '^\\s*"([^"]+)"\\s*(.*)\$') { \$exe = \$matches[1]; \$rest = \$matches[2].Trim() }
    elseif (\$cmd -match '^\\s*(\\S+)\\s*(.*)\$') { \$exe = \$matches[1]; \$rest = \$matches[2].Trim() }
    else { \$exe = \$cmd; \$rest = '' }
    \$al = @()
    if (\$rest) { \$al += \$rest }         # args เดิมจาก UninstallString (เช่น /uninstall)
    if (-not \$q) { \$al += '/S' }         # UninstallString ธรรมดา (ไม่ silent) → ลอง /S (NSIS) เป็น best-effort
    if (\$al.Count -gt 0) {
      \$p = Start-Process -FilePath \$exe -ArgumentList \$al -Verb RunAs -Wait -PassThru
    } else {
      \$p = Start-Process -FilePath \$exe -Verb RunAs -Wait -PassThru
    }
  }
  @{ code = \$p.ExitCode; name = \$app.DisplayName; us = \$cmd } | ConvertTo-Json -Compress
} catch {
  @{ code = -1; err = \$_.Exception.Message; us = \$cmd } | ConvertTo-Json -Compress
}
''';
    // ไม่ hidden — ต้องให้ UAC prompt ของ -Verb RunAs กดได้ (ดูหมายเหตุใน _runWindowsDeploy)
    final proc = await Process.run('powershell', _psArgs(script),
        stdoutEncoding: const SystemEncoding());
    try {
      final out = Map<String, dynamic>.from(jsonDecode(proc.stdout.toString().trim()) as Map);
      final code = out['code'] as int? ?? -1;
      if (code == 0 || code == 3010) return (true, 'uninstalled ${out['name'] ?? name} (exit $code)');
      final us = out['us'] != null ? ' [${out['us']}]' : '';
      return (false, (out['err'] as String? ?? 'exit code $code') + us);
    } catch (_) {
      return (false, 'unexpected output: ${proc.stdout}');
    }
  }

  // macOS: รองรับแค่ install (.pkg ผ่าน installer -pkg) — uninstall ไม่มี mechanism มาตรฐาน
  // เหมือน Windows MSI (ต้องมี uninstaller เฉพาะของแต่ละ vendor) จึงไม่รองรับใน POC นี้
  Future<(bool, String)> _runMacDeploy(String filePath, String action) async {
    if (action == 'uninstall') {
      return (false, 'macOS uninstall not supported in this POC');
    }
    try {
      final script =
          'do shell script "installer -pkg " & quoted form of "$filePath" & " -target /" with administrator privileges';
      final proc = await Process.run('osascript', ['-e', script]);
      if (proc.exitCode == 0) return (true, 'installed');
      return (false, proc.stderr.toString().trim());
    } catch (e) {
      return (false, e.toString());
    }
  }

  // ── Activity Monitor (CPU/Memory/Energy/Disk/Network) ─────
  //
  // ยิงเข้า POST /v3/api/device/metrics เหมือนกันทั้ง 2 trigger (periodic self-report ทุก
  // _metricsInterval + on-demand ตอน backend push metrics_request) — backend แยกใช้เอง:
  // เก็บเป็น "ค่าสด" ให้ viewer poll (live card) และ roll-up เข้า daily avg พร้อมกันในคราวเดียว

  void _startMetricsTimer() {
    _collectAndSendMetrics(); // ยิงทันทีรอบแรก ไม่ต้องรอครบ 5 นาทีก่อน
    _metricsTimer = Timer.periodic(_metricsInterval, (_) => _collectAndSendMetrics());
  }

  Future<void> _collectAndSendMetrics() async {
    try {
      Map<String, dynamic> data;
      if (Platform.isMacOS) {
        final raw = await _metricsChannel.invokeMethod('collect');
        data = Map<String, dynamic>.from(raw as Map);
        try {
          // timeout กันเคส user ยังไม่กด Allow/Deny บน system prompt ครั้งแรก — ไม่ให้ metrics
          // round นี้ค้างรอ user ตัดสินใจ (รอบถัดไปจะลองใหม่เอง ถ้า permission ตัดสินใจแล้วจะเร็วปกติ)
          final loc = await _metricsChannel
              .invokeMethod('location')
              .timeout(const Duration(seconds: 5));
          if (loc != null) {
            final m = Map<String, dynamic>.from(loc as Map);
            data['lat'] = m['lat'];
            data['lng'] = m['lng'];
            data['geoSource'] = 'wifi'; // CoreLocation (WiFi-based) — แม่นกว่า IP
          }
        } catch (_) {
          // ไม่ได้รับอนุญาต/ยังไม่ตัดสินใจ location permission/timeout — ข้าม ไม่ block metrics round อื่น
        }
      } else if (Platform.isWindows) {
        data = await _collectWindowsMetrics();
        if (data['lat'] != null && data['lng'] != null) {
          data['geoSource'] = 'wifi'; // WinRT Geolocator สำเร็จ
        }
      } else {
        return;
      }
      // IP-based geo fallback — ถ้า native geo คืน null (Location Services ปิด / WinRT unpackaged null)
      // ตำแหน่งระดับเมือง/ISP (public IP) พอสำหรับ approximate location; ทำงานทุกเครื่องไม่ต้องขอ permission
      if (data['lat'] == null || data['lng'] == null) {
        final ip = await _ipBasedGeo();
        if (ip != null) {
          data['lat'] = ip['lat'];
          data['lng'] = ip['lng'];
          data['geoSource'] = 'ip'; // ตำแหน่งหยาบ (public IP) — approximate
        }
      }
      await NetworkManager.instance.postV3('/v3/api/device/metrics', data);
    } catch (_) {
      // วัด/ส่งไม่สำเร็จรอบนี้ (เช่น agent เพิ่งเปิด ยังไม่ auth เสร็จ) — ข้าม รอรอบถัดไป
    }
  }

  // IP-based geolocation fallback — query จาก public IP (ipinfo.io, ฟรี ไม่ต้อง key)
  // ตำแหน่ง = public IP ของเครื่อง (office/ISP gateway) → ระดับเมือง ไม่ใช่ตำแหน่งจริงของเครื่อง
  // ใช้เมื่อ native geo (CoreLocation/WinRT) คืน null — ทำงานทุกเครื่องไม่ต้องขอ Location permission
  // cache ผลไว้ 1 ชม. (IP ไม่เปลี่ยนบ่อย) กันยิง API ทุก 5 นาที
  Map<String, dynamic>? _ipGeoCache;
  DateTime? _ipGeoCachedAt;
  Future<Map<String, dynamic>?> _ipBasedGeo() async {
    // ใช้ cache ถ้ายังไม่เกิน 1 ชม.
    if (_ipGeoCache != null && _ipGeoCachedAt != null &&
        DateTime.now().difference(_ipGeoCachedAt!) < const Duration(hours: 1)) {
      return _ipGeoCache;
    }
    try {
      final d = dio_pkg.Dio(dio_pkg.BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final resp = await d.get('https://ipinfo.io/json');
      // ipinfo.io คืน loc: "13.7563,100.5018" (lat,lng)
      final loc = (resp.data is Map ? resp.data['loc'] : null) as String?;
      if (loc != null && loc.contains(',')) {
        final parts = loc.split(',');
        final lat = double.tryParse(parts[0]);
        final lng = double.tryParse(parts[1]);
        if (lat != null && lng != null) {
          _ipGeoCache = {'lat': lat, 'lng': lng};
          _ipGeoCachedAt = DateTime.now();
          return _ipGeoCache;
        }
      }
    } catch (_) {
      // เน็ตล่ม / API block / parse fail — ข้าม (geo optional)
    }
    return null;
  }

  // Windows: PowerShell (Get-Counter/CIM/System.Windows.Forms) → JSON → parse ใน Dart
  // ไม่ต้อง delta-sample เองแบบ macOS เพราะ Get-Counter คืน rate/sec ให้ตรงๆ อยู่แล้ว
  // "Time on AC" ไม่มี API ตรงๆ เหมือนกับฝั่ง macOS — track เอง in-process ด้วย _winAcConnectedSince
  DateTime? _winAcConnectedSince;

  Future<Map<String, dynamic>> _collectWindowsMetrics() async {
    const script = r'''
Add-Type -AssemblyName System.Windows.Forms
$cpu = Get-Counter '\Processor(_Total)\% User Time','\Processor(_Total)\% Privileged Time','\Processor(_Total)\% Idle Time' -ErrorAction SilentlyContinue
$cpuUser = 0; $cpuSys = 0; $cpuIdle = 0
if ($cpu) {
  foreach ($s in $cpu.CounterSamples) {
    if ($s.Path -like '*User Time*') { $cpuUser = [math]::Round($s.CookedValue,1) }
    elseif ($s.Path -like '*Privileged Time*') { $cpuSys = [math]::Round($s.CookedValue,1) }
    elseif ($s.Path -like '*Idle Time*') { $cpuIdle = [math]::Round($s.CookedValue,1) }
  }
}
$os = Get-CimInstance Win32_OperatingSystem
$totalMemGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$freeMemGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$usedMemGB = [math]::Round($totalMemGB - $freeMemGB, 2)
$cacheSample = Get-Counter '\Memory\Cache Bytes' -ErrorAction SilentlyContinue
$cachedGB = if ($cacheSample) { [math]::Round($cacheSample.CounterSamples[0].CookedValue / 1GB, 2) } else { 0 }
$pageFile = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
$swapUsedGB = if ($pageFile) { [math]::Round((($pageFile | Measure-Object -Property CurrentUsage -Sum).Sum) / 1024, 2) } else { 0 }

$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$diskTotalGB = [math]::Round($disk.Size / 1GB, 2)
$diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
$diskUsedGB = [math]::Round($diskTotalGB - $diskFreeGB, 2)

$net = Get-Counter '\Network Interface(*)\Bytes Received/sec','\Network Interface(*)\Bytes Sent/sec' -ErrorAction SilentlyContinue
$rxKBs = 0.0; $txKBs = 0.0
if ($net) {
  foreach ($s in $net.CounterSamples) {
    if ($s.InstanceName -notlike '*isatap*' -and $s.InstanceName -notlike '*loopback*') {
      if ($s.Path -like '*Received*') { $rxKBs += $s.CookedValue / 1024 }
      elseif ($s.Path -like '*Sent*') { $txKBs += $s.CookedValue / 1024 }
    }
  }
}

# Location (POC) — WiFi-based via WinRT Geolocator (ไม่ใช่ GPS จริง), best-effort:
# ต้องเปิด Location Services ระดับ Windows (Settings > Privacy > Location) ไม่งั้น task จะ fault
# แล้ว catch ไปเงียบๆ — เหมือน pattern อื่นที่ Windows ไม่มี API ตรงๆ ให้ documented เป็น gap
#
# ⚠️ ห้ามใช้ $task.Wait() ตรงๆ — deadlock เสมอ (verified บนเครื่องจริง 2026-07-17):
# PowerShell 5.1 รัน STA เป็นค่า default, AsTask() ของ WinRT IAsyncOperation ต้อง pump
# message queue ของ thread เดียวกันถึงจะ complete ได้ แต่ .Wait() บล็อก thread นั้นเอง
# → ติด deadlock จนครบ timeout ทุกครั้ง (ไม่ fault, ไม่ throw — แค่ไม่มีวัน complete)
# แก้ด้วย poll ผ่าน DoEvents() แทน (ให้ message pump ทำงานต่อระหว่างรอ)
$lat = $null; $lng = $null
try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  [Windows.Devices.Geolocation.Geolocator,Windows.Devices.Geolocation,ContentType=WindowsRuntime] | Out-Null
  $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
  $geolocator = New-Object Windows.Devices.Geolocation.Geolocator
  $op = $geolocator.GetGeopositionAsync()
  $asTaskSpecific = $asTaskGeneric.MakeGenericMethod([Windows.Devices.Geolocation.Geoposition])
  $task = $asTaskSpecific.Invoke($null, @($op))
  $geoDeadline = (Get-Date).AddSeconds(10)
  while (-not $task.IsCompleted -and (Get-Date) -lt $geoDeadline) {
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 100
  }
  if ($task.IsCompleted -and -not $task.IsFaulted) {
    $pos = $task.Result
    $lat = [math]::Round($pos.Coordinate.Point.Position.Latitude, 6)
    $lng = [math]::Round($pos.Coordinate.Point.Position.Longitude, 6)
  }
} catch { $lat = $null; $lng = $null }

$power = [System.Windows.Forms.SystemInformation]::PowerStatus
$hasBattery = -not ([int]$power.BatteryChargeStatus -band 128)   # 128 = NoSystemBattery
$batteryPct = if ($power.BatteryLifePercent -le 1.0) { [math]::Round($power.BatteryLifePercent * 100, 0) } else { 0 }
$onAC = $power.PowerLineStatus -eq 'Online'
$charged = ($batteryPct -ge 99)   # Windows ไม่มี "IsCharged" flag ตรงๆ เหมือน macOS — ใช้ % ใกล้เต็มแทน

# Processes/Threads — Get-Process เข้าถึงได้โดยไม่ต้อง admin (ต่าง macOS ที่ proc_listpids ถูก sandbox บล็อก)
$procs = Get-Process -ErrorAction SilentlyContinue
$processCount = if ($procs) { $procs.Count } else { 0 }
$threadCount = if ($procs) { ($procs | ForEach-Object { $_.Threads.Count } | Measure-Object -Sum).Sum } else { 0 }

# Memory breakdown — Windows ไม่มี concept "wired/compressed" แบบ macOS ตรงๆ, ใช้ proxy:
# Wired ~ kernel non-paged pool (memory ที่ page ออกไม่ได้ ใกล้เคียงความหมาย wired ที่สุด)
# Compressed ไม่มี counter มาตรฐานให้ query ง่ายๆ บน Windows — รายงาน 0 (documented gap)
$memPerf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
$wiredGB = if ($memPerf) { [math]::Round($memPerf.PoolNonpagedBytes / 1GB, 2) } else { 0 }
$compressedGB = 0
$appGB = [math]::Round([math]::Max(0, $usedMemGB - $wiredGB - $compressedGB), 2)

# Disk IOPS — raw class = cumulative counter (ตั้งแต่ boot), formatted class = rate/sec จริง
$diskRaw = Get-CimInstance Win32_PerfRawData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction SilentlyContinue
$diskReadsCount = if ($diskRaw) { $diskRaw.DiskReadsPersec } else { 0 }
$diskWritesCount = if ($diskRaw) { $diskRaw.DiskWritesPersec } else { 0 }
$diskDataReadGB = if ($diskRaw) { [math]::Round($diskRaw.DiskReadBytesPersec / 1GB, 2) } else { 0 }
$diskDataWrittenGB = if ($diskRaw) { [math]::Round($diskRaw.DiskWriteBytesPersec / 1GB, 2) } else { 0 }
$diskFmt = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction SilentlyContinue
$diskReadsPerSec = if ($diskFmt) { $diskFmt.DiskReadsPersec } else { 0 }
$diskWritesPerSec = if ($diskFmt) { $diskFmt.DiskWritesPersec } else { 0 }
$diskReadKBs = if ($diskFmt) { [math]::Round($diskFmt.DiskReadBytesPersec / 1024, 2) } else { 0 }
$diskWriteKBs = if ($diskFmt) { [math]::Round($diskFmt.DiskWriteBytesPersec / 1024, 2) } else { 0 }

# Network packets/cumulative — เหมือน disk (raw=cumulative, formatted=rate), ข้าม isatap/loopback
$netRaw = Get-CimInstance Win32_PerfRawData_Tcpip_NetworkInterface -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notlike '*isatap*' -and $_.Name -notlike '*Loopback*' }
$netPacketsIn = if ($netRaw) { ($netRaw | Measure-Object -Property PacketsReceivedPersec -Sum).Sum } else { 0 }
$netPacketsOut = if ($netRaw) { ($netRaw | Measure-Object -Property PacketsSentPersec -Sum).Sum } else { 0 }
$netDataReceivedGB = if ($netRaw) { [math]::Round((($netRaw | Measure-Object -Property BytesReceivedPersec -Sum).Sum) / 1GB, 2) } else { 0 }
$netDataSentGB = if ($netRaw) { [math]::Round((($netRaw | Measure-Object -Property BytesSentPersec -Sum).Sum) / 1GB, 2) } else { 0 }
$netFmt = Get-Counter '\Network Interface(*)\Packets Received/sec','\Network Interface(*)\Packets Sent/sec' -ErrorAction SilentlyContinue
$pInSec = 0.0; $pOutSec = 0.0
if ($netFmt) {
  foreach ($s in $netFmt.CounterSamples) {
    if ($s.InstanceName -notlike '*isatap*' -and $s.InstanceName -notlike '*loopback*') {
      if ($s.Path -like '*Received*') { $pInSec += $s.CookedValue }
      elseif ($s.Path -like '*Sent*') { $pOutSec += $s.CookedValue }
    }
  }
}

$result = @{
  cpuUserPct = $cpuUser; cpuSystemPct = $cpuSys; cpuIdlePct = $cpuIdle
  cpuProcesses = $processCount; cpuThreads = $threadCount
  memPhysicalGB = $totalMemGB; memUsedGB = $usedMemGB; memCachedGB = $cachedGB; memSwapUsedGB = $swapUsedGB
  memAppGB = $appGB; memWiredGB = $wiredGB; memCompressedGB = $compressedGB
  diskFreeGB = $diskFreeGB; diskUsedGB = $diskUsedGB; diskTotalGB = $diskTotalGB
  diskReadsCount = $diskReadsCount; diskWritesCount = $diskWritesCount
  diskReadsPerSec = $diskReadsPerSec; diskWritesPerSec = $diskWritesPerSec
  diskDataReadGB = $diskDataReadGB; diskDataWrittenGB = $diskDataWrittenGB
  diskReadKBs = $diskReadKBs; diskWriteKBs = $diskWriteKBs
  netRxKBs = [math]::Round($rxKBs,2); netTxKBs = [math]::Round($txKBs,2)
  netPacketsIn = $netPacketsIn; netPacketsOut = $netPacketsOut
  netPacketsInPerSec = [math]::Round($pInSec,2); netPacketsOutPerSec = [math]::Round($pOutSec,2)
  netDataReceivedGB = $netDataReceivedGB; netDataSentGB = $netDataSentGB
  hasBattery = $hasBattery; batteryPct = $batteryPct; batteryCharged = $charged; onAC = $onAC
  energyImpactPct = [math]::Round($cpuSys + $cpuUser, 1)
}
if ($lat -ne $null -and $lng -ne $null) { $result.lat = $lat; $result.lng = $lng }
$result | ConvertTo-Json -Compress
''';
    final proc = await Process.run('powershell', _psArgs(script, hidden: true),
        stdoutEncoding: const SystemEncoding());
    final out = proc.stdout.toString().trim();
    final parsed = Map<String, dynamic>.from(jsonDecode(out) as Map);
    final onAC = parsed.remove('onAC') == true;
    if (onAC) {
      _winAcConnectedSince ??= DateTime.now();
    } else {
      _winAcConnectedSince = null;
    }
    parsed['timeOnACMinutes'] = _winAcConnectedSince == null
        ? 0.0
        : DateTime.now().difference(_winAcConnectedSince!).inSeconds / 60.0;
    return parsed;
  }

  // ── Remote Desktop capture loop ───────────────────────────
  //
  // admin เปิด Remote → backend push remote_start → เริ่ม capture หน้าจอส่ง backend เป็นระยะ
  // POST /v3/api/device/screenshot คืน {active:false} เมื่อไม่มีคนดูแล้ว → หยุด capture เอง
  // (กันกรณี remote_stop ตกหล่นตอน stream หลุด — self-healing)

  // admin เปิด Remote → ขอ consent ก่อน (ผู้ใช้ต้องกดอนุญาต) → ค่อยเริ่ม capture + แสดง indicator
  Future<void> _onRemoteStart(String sessionId, String viewer) async {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    if (_remoteCaptureTimer != null) return; // มี session active อยู่แล้ว
    // กัน consent popup ซ้ำ: ถ้ากำลังถาม consent ค้างอยู่ (ยังไม่กดตอบ) แล้ว backend push
    // remote_start ซ้ำ (replay ตอน stream reconnect / session ค้าง) — ไม่เด้ง dialog อันที่สอง
    if (_remoteConsentPending) return;
    _remoteConsentPending = true;
    final bool accept;
    try {
      accept = await _requestRemoteConsent(viewer);
    } finally {
      _remoteConsentPending = false;
    }
    // แจ้งผลกลับ backend เสมอ (ทั้ง accept/deny) — viewer จะได้เห็นสถานะถูกต้อง
    try {
      await NetworkManager.instance.postV3(
          '/v3/api/device/remote/consent', {'sessionId': sessionId, 'accept': accept});
    } catch (_) {}
    if (!accept) return; // ปฏิเสธ → ไม่ capture
    _remoteSessionId = sessionId;
    await _showRemoteIndicator(viewer);
    // macOS: เริ่ม SCStream (ทำให้ system indicator ผูกกับ session — หยุดแล้ว indicator หายทันที)
    if (Platform.isMacOS) {
      try {
        // maxWidth 1920, quality 1.0 (สูงสุด — user ขอตรงๆ "1.00 เลย" หลัง +50% ครั้งแรก, 2026-07-17)
        await _remoteChannel.invokeMethod('startCapture', {'maxWidth': 1920, 'quality': 1.0});
      } catch (_) {}
    }
    _remoteCaptureTimer = Timer.periodic(_remoteFrameInterval, (_) => _captureAndUpload());
  }

  void _stopRemoteCapture() {
    _remoteCaptureTimer?.cancel();
    _remoteCaptureTimer = null;
    _remoteSessionId = '';
    _hideRemoteIndicator();
    _stopWebrtc();
    // macOS: หยุด SCStream → macOS ปิด screen-recording indicator (ไอคอนม่วง) ทันที
    if (Platform.isMacOS) {
      _remoteChannel.invokeMethod('stopCapture').catchError((_) => null);
    }
  }

  // ── WebRTC (low-latency upgrade — vanilla ICE) ────────────
  //
  // viewer วาง SDP offer → backend push SSE remote_offer → agent capture หน้าจอเป็น
  // video track (getDisplayMedia) → ตอบ answer → media ไหล P2P (ผ่าน STUN, ไม่มี TURN).
  // HTTP frame upload เดิมยังรันเป็น fallback — WebRTC ต่อติดแล้วลดเหลือทุก 3s (keep-alive)

  // ── Remote Control (POC 2026-08-04) ────────────────────────────────────────
  RTCDataChannel? _remoteInputDc;
  // ผู้ใช้ที่เครื่องนี้กดยินยอมให้ "ควบคุม" แล้วหรือยัง — คนละตัวกับ consent การ "ดู" หน้าจอ
  // ยินยอมให้ดู ≠ ยินยอมให้สั่งงาน จึงต้องถามแยกและเก็บ flag แยก
  bool _remoteControlGranted = false;

  /// viewer ขอสิทธิ์ควบคุม (SSE ) → ถามผู้ใช้ที่เครื่องนี้
  Future<void> _onRemoteControlRequest(String sessionId, String viewer) async {
    if (sessionId.isEmpty || _remoteSessionId != sessionId) return;
    bool accept = false;
    try {
      accept = await _requestControlConsent(viewer);
    } catch (_) {
      accept = false;
    }
    _remoteControlGranted = accept;
    if (accept) {
      _showRemoteIndicator(viewer, controlling: true);
      // สิทธิ์ Accessibility เป็นคนละตัวกับ Screen Recording — ถ้ายังไม่ได้ให้ เด้ง prompt
      // พาไป System Settings (สั่งเปิดด้วยโค้ดไม่ได้ ผู้ใช้ต้องกดสวิตช์เอง)
      // ⚠️ ยินยอมแล้วแต่ไม่มีสิทธิ์นี้ = คลิก/พิมพ์จะไม่มีผลใด ๆ แบบเงียบ ๆ
      if (Platform.isMacOS) {
        try {
          final ok = await _remoteChannel
                  .invokeMethod<bool>('inputTrusted', {'prompt': true}) ??
              false;
          if (!ok) {
            debugPrint('[MYARAP-RC] ยังไม่มีสิทธิ์ Accessibility — input จะไม่มีผลจนกว่าจะเปิดใน System Settings');
          }
        } catch (_) {}
      }
    }
    await NetworkManager.instance.postV3('/v3/api/device/remote/control-consent',
        {'sessionId': sessionId, 'accept': accept});
  }

  /// viewer เลิกควบคุม หรือผู้ใช้กดหยุด → ปิดการรับ input ทันที (session ยังอยู่ ดูต่อได้)
  void _onRemoteControlRevoke() {
    _remoteControlGranted = false;
  }

  /// รับข้อความจาก data channel — **ทุกทางเข้าของ input ต้องผ่านฟังก์ชันนี้**
  void _onRemoteInput(String raw) {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final t = m['t'] as String? ?? '';
    // ขั้นทดสอบ transport — ตอบ pong ได้แม้ยังไม่ได้รับอนุญาตควบคุม
    // (ไม่ใช่การสั่งงานเครื่อง จึงไม่ต้อง gate)
    if (t == 'ping') {
      _remoteInputDc?.send(RTCDataChannelMessage(jsonEncode({
        't': 'pong',
        'at': m['at'],
        'granted': _remoteControlGranted,
      })));
      return;
    }
    // 🔴 ประตูบานเดียวของการสั่งงานจริง — ยังไม่ยินยอม = ทิ้งทุก event เงียบ ๆ
    if (!_remoteControlGranted) return;
    // ยิงแบบ fire-and-forget — ไม่ await เพราะเมาส์เลื่อนถี่มาก การรอผลจะทำให้หน่วงสะสม
    //
    // macOS  → MethodChannel → Swift CGEventPost
    // Windows → dart:ffi → user32.dll SendInput **ตรงจาก Dart**
    //   (ไม่ผ่าน MethodChannel เพราะ Windows runner เป็น C++ ที่ยังไม่มี plugin ของเรา
    //    และ FFI เร็วกว่าเพราะไม่ต้องข้าม platform channel ต่อ event)
    final x = (m['x'] as num?)?.toDouble() ?? 0;
    final y = (m['y'] as num?)?.toDouble() ?? 0;
    final btn = (m['b'] as num?)?.toInt() ?? 0;
    final dy = (m['dy'] as num?)?.toInt() ?? 0;
    final dx = (m['dx'] as num?)?.toInt() ?? 0;
    try {
      if (Platform.isMacOS) {
        switch (t) {
          case 'm':
            _remoteChannel.invokeMethod('mouseMove', {'x': x, 'y': y});
            break;
          case 'md':
            _remoteChannel.invokeMethod('mouseDown', {'b': btn});
            break;
          case 'mu':
            _remoteChannel.invokeMethod('mouseUp', {'b': btn});
            break;
          case 'w':
            _remoteChannel.invokeMethod('scroll', {'dy': dy, 'dx': dx});
            break;
          case 'kd':
          case 'ku':
            final mod = (m['mod'] as Map?) ?? const {};
            _remoteChannel.invokeMethod('key', {
              'c': m['c'] as String? ?? '',
              'down': t == 'kd',
              's': mod['s'] == true,
              'ctrl': mod['c'] == true,
              'alt': mod['a'] == true,
              'meta': mod['m'] == true,
            });
            break;
        }
      } else if (Platform.isWindows) {
        switch (t) {
          case 'm':
            RemoteInputWindows.mouseMove(x, y);
            break;
          case 'md':
            RemoteInputWindows.mouseDown(btn);
            break;
          case 'mu':
            RemoteInputWindows.mouseUp(btn);
            break;
          case 'w':
            RemoteInputWindows.scroll(dy, dx);
            break;
          case 'kd':
          case 'ku':
            // Windows ไม่มี flag modifier รวมแบบ macOS — ต้องกดค้าง/ปล่อยเองรอบปุ่มหลัก
            final mod = (m['mod'] as Map?) ?? const {};
            final sh = mod['s'] == true, ct = mod['c'] == true, al = mod['a'] == true;
            final code = m['c'] as String? ?? '';
            if (t == 'kd') {
              RemoteInputWindows.modifiers(shift: sh, ctrl: ct, alt: al, down: true);
              RemoteInputWindows.keyByCode(code, down: true);
            } else {
              RemoteInputWindows.keyByCode(code, down: false);
              RemoteInputWindows.modifiers(shift: sh, ctrl: ct, alt: al, down: false);
            }
            break;
        }
      }
    } catch (_) {
      // ยิงไม่สำเร็จ = ทิ้ง event นั้นไป ไม่ล้ม session (event ถัดไปมาทับอยู่แล้ว)
    }
  }

  /// สร้าง constraints ของ getDisplayMedia — **ต่างกันคนละแบบระหว่าง macOS กับ Windows**
  ///
  /// 🔴 Windows **ต้องระบุ `deviceId.exact`** ไม่งั้นล้มเหลว:
  ///    `flutter_screen_capture.cc` วน `sources_` หา source ที่ id ตรงกับที่ส่งมา
  ///    (default `"0"`) — แต่ `sources_` ว่างจนกว่าจะเรียก `getDesktopSources` ก่อน
  ///    → คืน error "source not found!" → getDisplayMedia throw → **agent ไม่ตอบ SDP
  ///    answer → WebRTC ไม่ติด → data channel ไม่เปิด → ควบคุมไม่ได้**
  ///    (อาการนี้เงียบสนิท ไม่มี log ฝั่ง backend นอกจาก "offer แล้วไม่มี answer")
  ///
  /// macOS ไม่ต้อง: ไม่ส่ง deviceId → `useDefaultScreen = YES` → ใช้ ScreenCaptureKit ตรง
  ///
  /// ⚠️ ทั้งสองแพลตฟอร์มอ่านจาก constraints แค่ `mandatory.frameRate` ตัวเดียว —
  /// width/height ไม่มีผล (เคยใส่แล้วทำ Windows พัง) ความคมมาจาก _tuneVideoSender()
  Future<Map<String, dynamic>> _displayMediaConstraints() async {
    final video = <String, dynamic>{
      'mandatory': {'frameRate': 15.0},
    };
    if (Platform.isWindows) {
      try {
        final sources =
            await desktopCapturer.getSources(types: [SourceType.Screen]);
        if (sources.isNotEmpty) {
          // จอแรก = จอหลัก (POC ยังไม่รองรับหลายจอ)
          video['deviceId'] = {'exact': sources.first.id};
        } else {
          _remoteDiag(_remoteSessionId, 'getSources_empty', 'ไม่พบจอเลย');
        }
      } catch (e) {
        // หา source ไม่ได้ = ปล่อยให้ getDisplayMedia ล้มเองแล้วตกไป HTTP polling
        _remoteDiag(_remoteSessionId, 'getSources_failed', e);
      }
    }
    return {'video': video, 'audio': false};
  }

  /// ตั้งค่า encoder ของ video sender ให้เน้น "ความคมชัด" มากกว่า "ความลื่น"
  /// เรียกหลัง addTrack และก่อน createAnswer — ต้องมี sender แล้วจึงตั้งได้
  Future<void> _tuneVideoSender(RTCPeerConnection pc) async {
    try {
      final senders = await pc.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind != 'video') continue;
        final params = sender.parameters;
        params.degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
        final encodings = params.encodings;
        if (encodings == null || encodings.isEmpty) {
          params.encodings = [RTCRtpEncoding(maxBitrate: 8000000, maxFramerate: 15)];
        } else {
          for (final e in encodings) {
            e.maxBitrate = 8000000; // 8 Mbps
            e.maxFramerate = 15;
            e.scaleResolutionDownBy = 1.0; // ห้ามย่อ — ค่า default บางแพลตฟอร์มย่อ 2 เท่า
          }
        }
        await sender.setParameters(params);
      }
    } catch (_) {
      // ตั้งไม่สำเร็จ = ใช้ค่า default ต่อ (ภาพเบลอกว่าแต่ยังใช้งานได้) ไม่ควรล้ม session
    }
  }

  /// รายงานว่า WebRTC ล้มที่ขั้นไหนกลับ backend
  ///
  /// จำเป็นเพราะดู log ฝั่ง agent จากระยะไกลไม่ได้เลย — เดิมเวลา getDisplayMedia
  /// หรือ createAnswer ล้ม จะเงียบสนิท ฝั่ง server เห็นแค่ "offer แล้วไม่มี answer"
  /// ซึ่งแยกไม่ออกว่าติด permission / capturer / SDP / เครือข่าย
  void _remoteDiag(String sessionId, String stage, Object? err) {
    try {
      NetworkManager.instance.postV3('/v3/api/device/remote/diag',
          {'sessionId': sessionId, 'stage': stage, 'error': err?.toString() ?? ''});
    } catch (_) {}
  }

  Future<void> _onRemoteOffer(String sessionId, String offerSdp) async {
    if (sessionId.isEmpty || offerSdp.isEmpty) return;
    if (_remoteSessionId != sessionId) {
      // session ไม่ตรง = offer มาก่อน consent เสร็จ หรือเป็น session ที่ถูกทิ้งไปแล้ว
      _remoteDiag(sessionId, 'session_mismatch', 'current=$_remoteSessionId');
      return;
    }
    await _stopWebrtc(); // ทิ้ง pc เก่าถ้ามี (offer ใหม่ทับ)
    try {
      final pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });
      _remotePc = pc;
      // capture หน้าจอหลักเป็น video track (flutter_webrtc desktop รองรับ getDisplayMedia)
      // ── คุณภาพภาพ ────────────────────────────────────────────────────────
      //
      // ⚠️ **width/height ใน constraints ไม่มีผลเลยทั้ง macOS และ Windows** — ตรวจซอร์ส
      // flutter_webrtc 1.5.2 แล้วทั้งสองอ่านแค่ `mandatory.frameRate` ตัวเดียว
      //   macOS   : common/darwin/Classes/FlutterRTCDesktopCapturer.m
      //   Windows : common/cpp/src/flutter_screen_capture.cc
      // resolution ถูกกำหนดโดย OS capturer เอง (macOS = logical resolution ของจอ)
      //
      // เคยลองใส่ width/height + minFrameRate/maxFrameRate แล้ว **ทำให้ Windows
      // ตอบ SDP answer ไม่ได้เลย** (WebRTC ต่อไม่ติด → data channel ไม่เปิด →
      // ควบคุมไม่ได้) — ต้องส่งเฉพาะ key ที่ปลายทางอ่านจริงเท่านั้น
      //
      // ตัวที่ทำให้ภาพคมจริงคือ degradationPreference + maxBitrate ใน _tuneVideoSender()
      final constraints = await _displayMediaConstraints();
      _remoteDiag(sessionId, 'constraints', constraints.toString());
      final stream =
          await navigator.mediaDevices.getDisplayMedia(constraints);
      _remoteScreenStream = stream;
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
      // 🔴 จุดที่ทำให้ภาพเบลอที่สุด — ไม่ใช่ resolution แต่เป็น degradationPreference
      //
      // WebRTC default = `balanced`/`maintain-framerate` แปลว่าเมื่อ bandwidth ตึง
      // จะ **ลดความคมชัดเพื่อรักษา fps** ซึ่งตรงข้ามกับสิ่งที่ remote desktop ต้องการ:
      // ดูหน้าจอคนอื่นต้องการ "ตัวหนังสืออ่านออก" มากกว่า "ลื่นไหล"
      // → maintain-resolution = ยอมให้ fps ตกแทน แต่ภาพยังคม
      //
      // maxBitrate 8 Mbps: พอสำหรับข้อความคมชัดที่ 2560px · ในวง LAN ไม่มีปัญหา
      // เน็ตช้าจะเห็นเป็น "กระตุก" แทน "เบลอ" ซึ่งเป็นการแลกที่ตั้งใจ
      await _tuneVideoSender(pc);
      // ── Remote Control (POC) — viewer สร้าง data channel 'input' มากับ offer ──
      // 🔴 **จุดบังคับจริงเพียงจุดเดียวของทั้งระบบ** — input วิ่ง P2P ตรง backend มองไม่เห็น
      // และบล็อกไม่ได้ · agent จึงต้องไม่รับ input จนกว่าผู้ใช้ที่เครื่องนี้จะกดยินยอมเอง
      // ( ตั้งเป็น true ที่ _onRemoteControlRequest เท่านั้น)
      pc.onDataChannel = (channel) {
        if (channel.label != 'input') return;
        _remoteInputDc = channel;
        channel.onMessage = (msg) => _onRemoteInput(msg.text);
      };
      pc.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          // media ไหล P2P แล้ว — ลด HTTP upload เหลือ keep-alive (ประหยัด bandwidth/CPU)
          _remoteCaptureTimer?.cancel();
          _remoteCaptureTimer =
              Timer.periodic(_remoteFrameIntervalSlow, (_) => _captureAndUpload());
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          // WebRTC หลุด — กลับ HTTP polling เต็มความถี่ (ถ้า session ยัง active)
          if (_remoteSessionId.isNotEmpty) {
            _remoteCaptureTimer?.cancel();
            _remoteCaptureTimer =
                Timer.periodic(_remoteFrameInterval, (_) => _captureAndUpload());
          }
        }
      };
      await pc.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await _waitIceComplete(pc);
      final local = await pc.getLocalDescription();
      final sdp = local?.sdp;
      if (sdp == null || sdp.isEmpty) return;
      await NetworkManager.instance.postV3(
          '/v3/api/device/remote/answer', {'sessionId': sessionId, 'sdp': sdp});
      _remoteDiag(sessionId, 'answer_sent', 'sdp ${sdp.length} bytes');
    } catch (e) {
      _remoteDiag(sessionId, 'webrtc_failed', e);
      // WebRTC ใช้ไม่ได้ (permission/แพลตฟอร์ม/เครือข่าย) — ทิ้งเงียบ, HTTP polling ทำงานต่อ
      await _stopWebrtc();
    }
  }

  // vanilla ICE: รอ gathering ครบ (สูงสุด 3s) ก่อนส่ง SDP — candidate ฝังใน SDP แล้ว
  Future<void> _waitIceComplete(RTCPeerConnection pc) async {
    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final done = Completer<void>();
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !done.isCompleted) {
        done.complete();
      }
    };
    await done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
  }

  Future<void> _stopWebrtc() async {
    try {
      for (final t in _remoteScreenStream?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _remoteScreenStream?.dispose();
    } catch (_) {}
    _remoteScreenStream = null;
    try {
      await _remotePc?.close();
    } catch (_) {}
    _remotePc = null;
  }

  // ── consent / indicator / capture — branch ตาม platform ──

  // สร้าง args สำหรับ powershell แบบ -EncodedCommand (base64 UTF-16LE)
  // เลี่ยงปัญหา encoding ภาษาไทย + quote ที่ผ่าน -Command args บน Windows ไม่ได้ (ทำ MessageBox
  // ไม่โผล่/parse พัง). `-STA` = WinForms ต้องการ; hidden = ซ่อน console window (กัน flash)
  List<String> _psArgs(String script, {bool hidden = false}) {
    final bytes = <int>[];
    for (final cu in script.codeUnits) {
      bytes.add(cu & 0xFF);
      bytes.add((cu >> 8) & 0xFF);
    }
    final args = ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass'];
    if (hidden) args.addAll(['-WindowStyle', 'Hidden']);
    args.addAll(['-EncodedCommand', base64.encode(bytes)]);
    return args;
  }

  /// consent สำหรับ **การควบคุม** — แยกจาก _requestRemoteConsent (ที่เป็นการยินยอมให้ "ดู")
  /// เพราะยินยอมให้ดูหน้าจอ ไม่ได้แปลว่ายินยอมให้คนอื่นสั่งเมาส์/คีย์บอร์ดเครื่องตัวเอง
  Future<bool> _requestControlConsent(String viewer) async {
    if (Platform.isMacOS) {
      try {
        return await _remoteChannel
                .invokeMethod<bool>('requestControlConsent', {'viewer': viewer}) ??
            false;
      } catch (_) {
        return false;
      }
    }
    if (Platform.isWindows) {
      // MessageBox แบบ blocking บน owner form TopMost — รูปแบบเดียวกับ consent การ "ดู"
      // ⚠️ ต้องใช้ _psArgs (-EncodedCommand) ไม่ใช่ -Command เพราะภาษาไทย + quote
      //    ทำ encoding พังจน dialog ไม่โผล่ (เจอจริงตอนทำ consent การดู)
      final safeViewer = viewer.replaceAll("'", "''");
      final script = '''
Add-Type -AssemblyName System.Windows.Forms
\$owner = New-Object System.Windows.Forms.Form
\$owner.TopMost = \$true
\$msg = "ผู้ดูแลระบบ '$safeViewer' ขอควบคุมเมาส์และคีย์บอร์ดของเครื่องนี้`n`n" +
  "ต่างจากการดูหน้าจอ - เมื่ออนุญาตแล้วเขาจะคลิกและพิมพ์บนเครื่องคุณได้จริง`n`n" +
  "อนุญาตหรือไม่?"
\$r = [System.Windows.Forms.MessageBox]::Show(\$owner, \$msg, "คำขอควบคุมเครื่องของคุณ",
  [System.Windows.Forms.MessageBoxButtons]::YesNo,
  [System.Windows.Forms.MessageBoxIcon]::Warning)
if (\$r -eq [System.Windows.Forms.DialogResult]::Yes) { Write-Output "ACCEPT" } else { Write-Output "DENY" }
''';
      try {
        final r = await Process.run('powershell', _psArgs(script));
        return (r.stdout as String).contains('ACCEPT');
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  Future<bool> _requestRemoteConsent(String viewer) async {
    if (Platform.isMacOS) {
      try {
        return await _remoteChannel.invokeMethod<bool>('requestConsent', {'viewer': viewer}) ?? false;
      } catch (_) {
        return false;
      }
    }
    if (Platform.isWindows) {
      // PowerShell MessageBox (blocking, topmost) — คืน ACCEPT/DENY ทาง stdout
      // ใช้ owner form TopMost เพื่อให้ dialog โผล่หน้าสุด (ไม่งั้นอาจซ่อนหลังหน้าต่างอื่น)
      final safeViewer = viewer.replaceAll("'", "''"); // กัน single-quote ทำ PS string พัง
      final script = '''
Add-Type -AssemblyName System.Windows.Forms
\$owner = New-Object System.Windows.Forms.Form
\$owner.TopMost = \$true
\$msg = "ผู้ดูแลระบบ '$safeViewer' ขอเข้าดูหน้าจอของคุณ (ดูอย่างเดียว ควบคุมไม่ได้)`n`nอนุญาตหรือไม่?"
\$r = [System.Windows.Forms.MessageBox]::Show(\$owner, \$msg, "คำขอเข้าดูหน้าจอ", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
if (\$r -eq [System.Windows.Forms.DialogResult]::Yes) { 'ACCEPT' } else { 'DENY' }
''';
      try {
        final proc = await Process.run('powershell', _psArgs(script, hidden: true),
            stdoutEncoding: const SystemEncoding());
        return proc.stdout.toString().trim() == 'ACCEPT';
      } catch (_) {
        return false;
      }
    }
    return false;
  }

    /// controlling=true → เปลี่ยนข้อความ indicator เป็น "กำลังถูกควบคุม"
  /// ผู้ใช้ต้องแยกออกว่าตอนนี้ถูกดูเฉย ๆ หรือถูกสั่งงานเมาส์/คีย์บอร์ดจริง
  Future<void> _showRemoteIndicator(String viewer, {bool controlling = false}) async {
    if (Platform.isMacOS) {
      try {
        await _remoteChannel.invokeMethod('showIndicator', {'viewer': viewer, 'controlling': controlling});
      } catch (_) {}
      return;
    }
    if (Platform.isWindows) {
      // topmost banner form แบบ detached — แสดง "🔴 กำลังถูกดู" จนกว่าจะ kill process ตอน stop
      // ⚠️ ไม่มีปุ่มหยุดโต้ตอบกลับ Dart (PowerShell form call กลับ Dart ไม่ได้) — Disconnect
      //    ฝั่ง Windows agent = future; ปัจจุบันตัดได้จากฝั่ง admin เท่านั้น
      final safeViewer = viewer.replaceAll('"', '');
      // ผู้ใช้ต้องแยกออกว่า "ถูกดู" กับ "ถูกควบคุม" ต่างกัน — ไม่งั้นไม่รู้ว่ามีคนสั่ง
      // เมาส์/คีย์บอร์ดอยู่ · ข้อความ+สีต่างกันชัด (แดง = ดู, ส้มเข้ม = ควบคุม)
      final bannerText = controlling
          ? "  * $safeViewer กำลังควบคุมเมาส์และคีย์บอร์ดเครื่องนี้"
          : "  * หน้าจอกำลังถูกดูโดย $safeViewer";
      final bannerRgb = controlling ? "196, 88, 0" : "217, 31, 64";
      // form มีปุ่ม "หยุด" — คลิกแล้ว form ปิด → process exit (Dart ฟัง exitCode → disconnect)
      final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# ⚠️ ต้องใช้ฟอร์มที่ **ไม่ขโมย focus** ไม่งั้นผู้ใช้ต้องกดปุ่มหยุด 2 ครั้ง:
#    คลิกแรกถูกกินไปกับการ activate หน้าต่าง คลิกที่สองปุ่มถึงได้รับ event
#    WS_EX_NOACTIVATE (0x08000000) = รับคลิกได้โดยไม่ต้อง activate ก่อน
#    (พฤติกรรมเดียวกับ banner ฝั่ง macOS ที่ใช้ NSWindow level=.statusBar)
Add-Type @"
using System;
using System.Windows.Forms;
public class MyarapBanner : Form {
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override CreateParams CreateParams {
    get {
      CreateParams cp = base.CreateParams;
      cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
      cp.ExStyle |= 0x00000008; // WS_EX_TOPMOST
      return cp;
    }
  }
}
"@ -ReferencedAssemblies System.Windows.Forms,System.Drawing
\$f = New-Object MyarapBanner
\$f.Text = "MYARAP Remote"
\$f.FormBorderStyle = 'None'
\$f.TopMost = \$true
\$f.ShowInTaskbar = \$false
\$f.StartPosition = 'Manual'
\$sw = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
\$f.Size = New-Object System.Drawing.Size(440, 40)
\$f.Location = New-Object System.Drawing.Point([int](\$sw/2 - 220), 6)
\$f.BackColor = [System.Drawing.Color]::FromArgb($bannerRgb)
\$lbl = New-Object System.Windows.Forms.Label
\$lbl.Text = "$bannerText"
\$lbl.ForeColor = 'White'
\$lbl.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
\$lbl.Location = New-Object System.Drawing.Point(0, 0)
\$lbl.Size = New-Object System.Drawing.Size(330, 40)
\$lbl.TextAlign = 'MiddleLeft'
\$f.Controls.Add(\$lbl)
\$btn = New-Object System.Windows.Forms.Button
\$btn.Text = "หยุด"
\$btn.Size = New-Object System.Drawing.Size(90, 28)
\$btn.Location = New-Object System.Drawing.Point(340, 6)
\$btn.FlatStyle = 'Flat'
\$btn.BackColor = [System.Drawing.Color]::White
\$btn.ForeColor = [System.Drawing.Color]::FromArgb($bannerRgb)
\$btn.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
# MouseDown ไม่ใช่ Click — ยิงทันทีที่กดเมาส์ลง เป็นชั้นกันพลาดชั้นที่สอง
\$btn.Add_MouseDown({ \$f.Close() })
\$f.Controls.Add(\$btn)
[System.Windows.Forms.Application]::Run(\$f)
''';
      try {
        _winIndicatorStopByUs = false;
        // ไม่ await — form.Run บล็อกจนกว่า process ถูก kill หรือ user กดปุ่มหยุด
        final proc = await Process.start('powershell', _psArgs(script, hidden: true));
        _winIndicatorProc = proc;
        // ฟัง exit: ถ้า process จบเองโดยเราไม่ได้ kill = user กดปุ่มหยุด → disconnect
        proc.exitCode.then((_) => _onWindowsIndicatorClosed());
      } catch (_) {}
      return;
    }
  }

  // Windows: indicator form ปิด (user กดปุ่มหยุด) → หยุด capture + แจ้ง backend จบ session
  void _onWindowsIndicatorClosed() {
    if (_winIndicatorStopByUs) return; // เรา kill เอง (normal stop) — ไม่ใช่ user กด
    _winIndicatorProc = null;
    final sid = _remoteSessionId;
    _remoteCaptureTimer?.cancel();
    _remoteCaptureTimer = null;
    _remoteSessionId = '';
    if (sid.isNotEmpty) {
      NetworkManager.instance
          .postV3('/v3/api/device/remote/stop', {'sessionId': sid})
          .catchError((_) => <String, dynamic>{});
    }
  }

  void _hideRemoteIndicator() {
    if (Platform.isMacOS) {
      _remoteChannel.invokeMethod('hideIndicator').catchError((_) => null);
    } else if (Platform.isWindows) {
      _winIndicatorStopByUs = true; // บอก exitCode handler ว่านี่คือ normal stop ไม่ใช่ user กดปุ่ม
      _winIndicatorProc?.kill();
      _winIndicatorProc = null;
    }
  }

  // ผู้ใช้ปลายทางกด "หยุด" บน indicator → หยุด capture + แจ้ง backend จบ session (viewer จะเห็นว่าจบ)
  void _listenRemoteEvents() {
    _remoteEventSub = _remoteEventChannel.receiveBroadcastStream().listen((event) async {
      final map = event as Map;
      if (map['event'] == 'disconnect') {
        final sid = _remoteSessionId;
        _stopRemoteCapture();
        if (sid.isNotEmpty) {
          try {
            await NetworkManager.instance
                .postV3('/v3/api/device/remote/stop', {'sessionId': sid});
          } catch (_) {}
        }
      }
    }, onError: (_) {});
  }

  Future<void> _captureAndUpload() async {
    if (_remoteCapturing) return; // กัน overlap ถ้าเฟรมก่อนยังส่งไม่เสร็จ
    _remoteCapturing = true;
    try {
      final frame = await _captureScreenFrame();
      if (frame == null || frame.isEmpty) return;
      final resp = await NetworkManager.instance
          .postV3('/v3/api/device/screenshot', {'frame': frame});
      // backend บอกว่าไม่มี session แล้ว → หยุด capture (remote_stop อาจตกหล่น)
      if (resp['active'] == false) _stopRemoteCapture();
    } catch (_) {
      // capture ล้มเหลว (เช่น ยังไม่ได้อนุญาต Screen Recording) — ข้ามเฟรมนี้ ลองใหม่รอบหน้า
    } finally {
      _remoteCapturing = false;
    }
  }

  // คืน JPEG data URL ของหน้าจอหลัก — macOS ผ่าน native, Windows ผ่าน PowerShell CopyFromScreen
  // maxWidth 1920, quality 1.0/100 (สูงสุด — user ขอตรงๆ "1.00 เลย" หลัง +50% ครั้งแรก, 2026-07-17)
  Future<String?> _captureScreenFrame() async {
    if (Platform.isMacOS) {
      return _remoteChannel.invokeMethod<String>('captureScreen', {'maxWidth': 1920, 'quality': 1.0});
    }
    if (Platform.isWindows) {
      // CopyFromScreen → ย่อ maxWidth 1920 → JPEG q=100 → base64 (stdout)
      const script = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$maxW = 1920
if ($b.Width -gt $maxW) {
  $nw = $maxW; $nh = [int]($b.Height * $maxW / $b.Width)
  $rs = New-Object System.Drawing.Bitmap $nw, $nh
  $rg = [System.Drawing.Graphics]::FromImage($rs)
  $rg.DrawImage($bmp, 0, 0, $nw, $nh)
  $rg.Dispose(); $g.Dispose(); $bmp.Dispose(); $bmp = $rs
}
$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]100)
$ms = New-Object System.IO.MemoryStream
$bmp.Save($ms, $enc, $ep)
[Convert]::ToBase64String($ms.ToArray())
''';
      try {
        // encoded + hidden — กัน console window flash ทุกเฟรม (400ms)
        final proc = await Process.run('powershell', _psArgs(script, hidden: true),
            stdoutEncoding: const SystemEncoding());
        final b64 = proc.stdout.toString().trim();
        if (b64.isEmpty) return null;
        return 'data:image/jpeg;base64,$b64';
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Map<String, dynamic> _buildDevicePayload(DeviceDetail d) {
    final isMac = Platform.isMacOS;
    final isWindows = Platform.isWindows;

    // ram_gb: parse จาก "16 GB" → 16.0
    double? ramGb;
    final memMatch = RegExp(r'([\d.]+)\s*GB', caseSensitive: false).firstMatch(d.memory);
    if (memMatch != null) ramGb = double.tryParse(memMatch.group(1) ?? '');

    // cpuSpeed: Hz → "X.XX GHz" (Apple Silicon = ว่าง เพราะไม่มี fixed freq)
    String cpuSpeed = '';
    final hz = int.tryParse(d.cpuFrequencyMax);
    if (hz != null && hz > 0) cpuSpeed = '${(hz / 1e9).toStringAsFixed(2)} GHz';

    // gpuVendor: derive จากชื่อ GPU
    String gpuVendor = '';
    final gpuLow = d.gpu.toLowerCase();
    if (gpuLow.contains('apple')) gpuVendor = 'Apple';
    else if (gpuLow.contains('amd') || gpuLow.contains('radeon')) gpuVendor = 'AMD';
    else if (gpuLow.contains('nvidia') || gpuLow.contains('geforce')) gpuVendor = 'NVIDIA';
    else if (gpuLow.contains('intel')) gpuVendor = 'Intel';

    // osVersion = ส่วนตัวเลขล้วน "26.5.1" (ถอด prefix macOS / Windows ออก)
    final osVersionNum = d.osVersion
        .replaceFirst(RegExp(r'^macOS\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^Windows\s*', caseSensitive: false), '');

    final brand = isMac ? 'Apple' : (d.vendor.isNotEmpty ? d.vendor : 'Unknown');
    final cpuVendor = d.vendor.isNotEmpty ? d.vendor : (isMac ? 'Apple' : '');

    return {
      // identity / model
      'hostname':     d.computerName,
      'serialNumber': d.serialNumber,
      'serial':       d.serialNumber,   // alias ตรงกับ frontend field `serial`
      'uuid':         d.hardwareUUID,
      'model':        d.modelIdentifier,
      'brand':        brand,
      // OS
      'os':           d.osVersion,      // "macOS 26.5.1" → OS.Name
      'platform':     isMac ? 'macOS' : (isWindows ? 'Windows' : 'Unknown'),
      'osVersion':    osVersionNum,     // "26.5.1" → OS.Version
      'arch':         d.cpuArchitecture, // "arm64" / "x64"
      // CPU
      'cpu':          d.processorDisplay, // "Apple M4"
      'cpuVendor':    cpuVendor,
      'cpuCores':     d.totalCores,      // "10"
      'cpuSpeed':     cpuSpeed,          // "3.50 GHz" หรือ "" สำหรับ Apple Silicon
      // Memory
      'ram':          d.memory,          // "16 GB" (backward compat)
      'ram_gb':       ramGb,             // 16.0 (number)
      'ramType':      d.memoryType,      // "LPDDR5"
      // Storage
      'diskName':     d.storageName,     // "Macintosh HD"
      'diskType':     d.storageType,     // "SSD" / "HDD"
      'diskSize':     d.storageTotal,    // "512.0 GB"
      // GPU
      'gpu':          d.gpu,             // "Apple M4"
      'gpuVendor':    gpuVendor,         // "Apple"
      // Displays — array of {name, resolutionX, resolutionY, builtin}
      'displays': d.displaysDetail.map((disp) => {
        'name':        disp.name,
        'resolutionX': disp.resolutionX,
        'resolutionY': disp.resolutionY,
        'builtin':     disp.builtin,
      }).toList(),
      // agent
      'agentVersion': AppConfig.agentVersion, // single source — bump ที่ app_config.dart ที่เดียว
      // active app (macOS EventChannel; ว่างบน Windows)
      if (d.frontmostApp.isNotEmpty) 'lastApp': d.frontmostApp,
    };
  }

  Future<void> refresh() async {
    isLoading = true;
    notifyListeners();
    await _loadDeviceInfo();
    await _authenticate();
    _startPolicyStream(); // ต่อ stream ใหม่ด้วย token ล่าสุด (cancel ตัวเดิมให้เองข้างใน)
    isLoading = false;
    notifyListeners();
  }
}
