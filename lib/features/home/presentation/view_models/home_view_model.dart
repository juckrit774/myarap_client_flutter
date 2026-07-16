import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/device_model.dart';
import '../../../auth/models/login_response_model.dart';
import '../../../../core/services/network_manager.dart';
import '../../../../core/storage/cache_manager.dart';

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
  String _remoteSessionId = ''; // session ที่กำลัง active (ใช้ตอนผู้ใช้กด Disconnect เอง)
  Process? _winIndicatorProc;   // Windows: process ของ topmost banner form (kill ตอน stop)
  bool _winIndicatorStopByUs = false; // true = เรา kill เอง (normal stop); false = user กดปุ่มหยุด
  // interval ระหว่างเฟรม (~2.5 fps) — สมดุลระหว่าง smoothness กับ bandwidth/CPU
  static const _remoteFrameInterval = Duration(milliseconds: 400);

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
    _windowsAppTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      const script = r'''
$sig = '[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();'
      + '[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);'
Add-Type -MemberDefinition $sig -Name Win32 -Namespace WinHelper -ErrorAction SilentlyContinue
$hwnd = [WinHelper.Win32]::GetForegroundWindow()
$pid = [uint32]0
[WinHelper.Win32]::GetWindowThreadProcessId($hwnd, [ref]$pid) | Out-Null
(Get-Process -Id $pid -ErrorAction SilentlyContinue).MainWindowTitle
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

  // Windows USB policy — block = Disable-PnpDevice (device หายจาก Explorer แต่ reversible),
  // unblock = Enable-PnpDevice (mount กลับทันทีโดย software ไม่ต้องถอด-เสียบ).
  //
  // ⚠️ เลิกใช้ Shell "Eject" verb (Safely Remove Hardware) แล้ว — user ทดสอบจริงพบว่ามันเป็น
  //    hardware-level removal → Windows มองว่า device ถูกถอดจริง → pnputil /scan-devices ไม่
  //    re-mount ให้ (ต้อง physical replug เหมือน macOS diskutil eject). Disable/Enable-PnpDevice
  //    เป็น software-level toggle ที่ reversible — Disable = หายจาก Explorer, Enable = กลับมาเลย.
  // ⚠️ ต้องการสิทธิ์ Administrator — ไม่ elevated = เงียบ (Process non-zero, catch ทิ้ง)
  Future<void> _applyWindowsUsbPolicy(bool block) async {
    if (block) {
      await _disableWindowsUsbDrives();
    } else {
      await _enableWindowsUsbDrives();
    }
  }

  // Disable USB mass-storage disk ทุกตัวที่เสียบอยู่ (present + status OK) → หายจาก Explorer.
  // คืน FriendlyName ของแต่ละตัวที่ disable → report เป็น block event. reversible ด้วย Enable.
  Future<void> _disableWindowsUsbDrives() async {
    const script = r'''
$ErrorActionPreference = 'SilentlyContinue'
Get-PnpDevice -Class DiskDrive -PresentOnly | Where-Object { $_.InstanceId -like 'USBSTOR\*' -and $_.Status -eq 'OK' } | ForEach-Object {
  Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false
  $_.FriendlyName
}
''';
    try {
      final proc = await Process.run('powershell', _psArgs(script, hidden: true),
          stdoutEncoding: const SystemEncoding());
      final names = proc.stdout.toString().split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
      for (final name in names) {
        await _reportUsbBlock(name);
      }
    } catch (_) {}
  }

  // Enable USB mass-storage disk ที่ถูก disable ไว้ (status != OK) → mount กลับทันที
  Future<void> _enableWindowsUsbDrives() async {
    const script = r'''
$ErrorActionPreference = 'SilentlyContinue'
Get-PnpDevice -Class DiskDrive | Where-Object { $_.InstanceId -like 'USBSTOR\*' -and $_.Status -ne 'OK' } | ForEach-Object {
  Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false
}
''';
    try {
      await Process.run('powershell', _psArgs(script, hidden: true));
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
        // มี USB drive ใหม่โผล่ระหว่าง blocked → Disable-PnpDevice ครอบทุก USB storage ที่เสียบ
        // (Disable-PnpDevice ทำงานที่ device level ไม่ใช่ drive letter จึงเรียกครั้งเดียวพอ;
        //  helper คืน+report FriendlyName ของ device ที่ disable เอง)
        if (!_allowUsb && newLetters.isNotEmpty) {
          await _disableWindowsUsbDrives();
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
      case 'remote_stop':
        _stopRemoteCapture();
        break;
    }
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
    final accept = await _requestRemoteConsent(viewer);
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
        await _remoteChannel.invokeMethod('startCapture', {'maxWidth': 1280, 'quality': 0.5});
      } catch (_) {}
    }
    _remoteCaptureTimer = Timer.periodic(_remoteFrameInterval, (_) => _captureAndUpload());
  }

  void _stopRemoteCapture() {
    _remoteCaptureTimer?.cancel();
    _remoteCaptureTimer = null;
    _remoteSessionId = '';
    _hideRemoteIndicator();
    // macOS: หยุด SCStream → macOS ปิด screen-recording indicator (ไอคอนม่วง) ทันที
    if (Platform.isMacOS) {
      _remoteChannel.invokeMethod('stopCapture').catchError((_) => null);
    }
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

  Future<void> _showRemoteIndicator(String viewer) async {
    if (Platform.isMacOS) {
      try {
        await _remoteChannel.invokeMethod('showIndicator', {'viewer': viewer});
      } catch (_) {}
      return;
    }
    if (Platform.isWindows) {
      // topmost banner form แบบ detached — แสดง "🔴 กำลังถูกดู" จนกว่าจะ kill process ตอน stop
      // ⚠️ ไม่มีปุ่มหยุดโต้ตอบกลับ Dart (PowerShell form call กลับ Dart ไม่ได้) — Disconnect
      //    ฝั่ง Windows agent = future; ปัจจุบันตัดได้จากฝั่ง admin เท่านั้น
      final safeViewer = viewer.replaceAll('"', '');
      // form มีปุ่ม "หยุด" — คลิกแล้ว form ปิด → process exit (Dart ฟัง exitCode → disconnect)
      final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$f = New-Object System.Windows.Forms.Form
\$f.Text = "MYARAP Remote"
\$f.FormBorderStyle = 'None'
\$f.TopMost = \$true
\$f.ShowInTaskbar = \$false
\$f.StartPosition = 'Manual'
\$sw = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
\$f.Size = New-Object System.Drawing.Size(440, 40)
\$f.Location = New-Object System.Drawing.Point([int](\$sw/2 - 220), 6)
\$f.BackColor = [System.Drawing.Color]::FromArgb(217, 31, 64)
\$lbl = New-Object System.Windows.Forms.Label
\$lbl.Text = "  * หน้าจอกำลังถูกดูโดย $safeViewer"
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
\$btn.ForeColor = [System.Drawing.Color]::FromArgb(217, 31, 64)
\$btn.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
\$btn.Add_Click({ \$f.Close() })
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
  Future<String?> _captureScreenFrame() async {
    if (Platform.isMacOS) {
      return _remoteChannel.invokeMethod<String>('captureScreen', {'maxWidth': 1280, 'quality': 0.5});
    }
    if (Platform.isWindows) {
      // CopyFromScreen → ย่อ maxWidth 1280 → JPEG q=50 → base64 (stdout)
      const script = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$maxW = 1280
if ($b.Width -gt $maxW) {
  $nw = $maxW; $nh = [int]($b.Height * $maxW / $b.Width)
  $rs = New-Object System.Drawing.Bitmap $nw, $nh
  $rg = [System.Drawing.Graphics]::FromImage($rs)
  $rg.DrawImage($bmp, 0, 0, $nw, $nh)
  $rg.Dispose(); $g.Dispose(); $bmp.Dispose(); $bmp = $rs
}
$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]50)
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
      'agentVersion': '3.0.0',
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
