import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

class DisplayInfo {
  final String name;
  final int resolutionX;
  final int resolutionY;
  final bool builtin;

  const DisplayInfo({
    required this.name,
    required this.resolutionX,
    required this.resolutionY,
    required this.builtin,
  });

  String get label {
    final res = resolutionX > 0 ? ' (${resolutionX}×$resolutionY)' : '';
    return '$name$res';
  }
}

/// 1 พาร์ทิชัน/volume ที่ mount อยู่ — เครื่องหนึ่งมีได้หลายลูก
/// (Windows: C:, D: … · macOS: /, /Volumes/…)
/// การ์ดเครือข่าย 1 ใบ — IMPL-16 Phase 1
///
/// 🔴 **เก็บเป็น list ต่อใบ ไม่ใช่ค่าเดียวต่อเครื่อง** — `DeviceDetail.ipAddress` เดิมเป็น
/// "ใบไหนก็ไม่รู้ที่เจอเป็นตัวสุดท้าย" เครื่องที่มีทั้งสาย LAN และ Wi-Fi จึงรายงานค่าไม่แน่นอน
///
/// ⚠️ **field ที่ได้ไม่เท่ากันสองแพลตฟอร์ม** — Windows ได้ครบ (gateway/dhcp/dns จาก PowerShell)
/// ส่วน macOS ได้ name/ipv4/prefix/mac เท่านั้น เพราะแอปรันใน sandbox เรียก `ipconfig`/`scutil` ไม่ได้
/// (gateway ของใบหลักได้จาก SystemConfiguration) · **ค่าว่างจึงแปลว่า "แพลตฟอร์มนี้ไม่มีให้" ไม่ใช่ "ผิดปกติ"**
class NetworkInterfaceInfo {
  final String name;
  /// ชนิดการ์ด: `lan` | `wifi` | `other`
  ///
  /// 🔴 **ต้องมาจากระบบปฏิบัติการ ห้ามเดาจากชื่อ** — บน macOS ชื่อเป็น `en0`/`en1` ซึ่งเป็น
  /// Wi-Fi บนเครื่องหนึ่งและเป็นสายบนอีกเครื่องหนึ่ง · MYARAP ใช้ค่านี้เลือกว่าเบอร์ไหนคือ
  /// "IP ของเครื่อง" เวลาต้องแสดงเบอร์เดียว (สายมาก่อน Wi-Fi)
  final String kind;
  final String ipv4;
  final int prefix;      // 24 = /24 · 0 = อ่านไม่ได้
  final String mac;      // รูปแบบดิบตามแพลตฟอร์ม — ฝั่ง server normalize เอง
  final String gateway;  // ว่างได้ (macOS ได้เฉพาะใบหลัก)
  final bool dhcp;       // Windows เท่านั้น · macOS = false เสมอ (แยกไม่ได้โดยไม่ spawn process)
  final List<String> dns;
  final bool primary;    // ใบที่มี default route

  const NetworkInterfaceInfo({
    required this.name, required this.ipv4, this.kind = 'other', this.prefix = 0, this.mac = '',
    this.gateway = '', this.dhcp = false, this.dns = const [], this.primary = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (kind.isNotEmpty) 'kind': kind,
        'ipv4': ipv4,
        if (prefix > 0) 'prefix': prefix,
        if (mac.isNotEmpty) 'mac': mac,
        if (gateway.isNotEmpty) 'gateway': gateway,
        if (dhcp) 'dhcp': true,
        if (dns.isNotEmpty) 'dns': dns,
        if (primary) 'primary': true,
      };
}

class VolumeInfo {
  final String mount;   // "C:" หรือ "/Volumes/Data"
  final String name;    // ชื่อที่ผู้ใช้ตั้ง
  final String fs;      // NTFS / APFS
  final int totalBytes;
  final int freeBytes;
  final bool boot;      // ไดรฟ์ที่ OS ติดตั้งอยู่
  final bool removable; // ดิสก์นอก — ฝั่ง UI ใช้แยกออกจากพาร์ทิชันในเครื่อง

  const VolumeInfo({
    required this.mount, required this.name, required this.fs,
    required this.totalBytes, required this.freeBytes,
    this.boot = false, this.removable = false,
  });
}

class ApplicationInfo {
  final String name;
  final String version;
  final int size;
  /// ผู้พัฒนา — Windows: registry `Publisher` · macOS: common name จาก code signature
  final String publisher;
  /// ที่มา: user (คนลงเอง) | system (มากับ OS/runtime) | store (Store/App Store)
  /// ว่าง = ยังไม่รู้ → ฝั่ง backend จะถือเป็น user เพื่อไม่ให้พฤติกรรมเดิมเปลี่ยน
  final String source;

  // ---- IMPL-15 Phase 3 — field ตามสเปก SOFTWARE INSTALLATION SYNC ----
  // ทั้ง 4 ตัวเป็น **optional** ทั้งฝั่ง agent และ backend: agent รุ่นเก่าไม่ส่ง = ค่าว่าง
  // ห้ามทำให้ contract เดิมพัง (กฎข้อ 1 ของโปรเจกต์)

  /// วันที่ติดตั้ง `yyyy-MM-dd` — Windows: registry `InstallDate` (บางตัวไม่เขียนไว้)
  /// ⚠️ **macOS ไม่มีข้อมูลนี้** และจงใจไม่ใช้เวลาแก้ไขไฟล์แทน เพราะมันเปลี่ยนทุกครั้ง
  /// ที่แอปอัปเดต — จะกลายเป็น "วันที่อัปเดตล่าสุด" ไม่ใช่ "วันที่ติดตั้ง"
  final String installDate;

  /// path ที่ติดตั้ง — Windows: registry `InstallLocation` · macOS: path ของ .app
  final String installLocation;

  /// x86 | x64 | arm64 | … — Windows: อนุมานจาก registry hive ที่เจอ (Wow6432Node = x86)
  /// · Appx: property `Architecture` · macOS: `Bundle.executableArchitectures`
  final String architecture;

  /// ตัวระบุแพ็กเกจ — Windows MSI: ProductCode GUID (ชื่อ subkey) · Appx: PackageFullName
  /// · macOS: `CFBundleIdentifier`
  final String packageId;

  /// สัญญาณดิบของ Appx (Windows เท่านั้น) — ใช้ประกอบการตัดสินฝั่ง server ว่าอันไหน
  /// "ติดมากับเครื่อง" · ยังไม่มีผลกับ `source` จนกว่าจะเห็นข้อมูลจริงจากหลายเครื่อง
  final bool nonRemovable;
  final String signatureKind;

  const ApplicationInfo({
    required this.name,
    required this.version,
    required this.size,
    this.publisher = '',
    this.source = '',
    this.installDate = '',
    this.installLocation = '',
    this.architecture = '',
    this.packageId = '',
    this.nonRemovable = false,
    this.signatureKind = '',
  });
}

/// แปลงผลดิบจาก native → NetworkInterfaceInfo
///
/// ⚠️ **ทิ้งใบที่ไม่มี IPv4** — ใบที่เสียบสายไว้แต่ยังไม่ได้ที่อยู่ไม่ได้ให้ข้อมูลอะไรกับทะเบียนไอพี
List<NetworkInterfaceInfo> _parseInterfaces(dynamic raw) {
  if (raw is! List) return const [];
  final out = <NetworkInterfaceInfo>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final m = e.cast<String, dynamic>();
    final ip = (m['ipv4'] as String? ?? '').trim();
    if (ip.isEmpty) continue;
    final rawDns = m['dns'];
    out.add(NetworkInterfaceInfo(
      name: m['name'] as String? ?? '',
      ipv4: ip,
      kind: (m['kind'] as String? ?? 'other').trim(),
      prefix: (m['prefix'] as num?)?.toInt() ?? 0,
      mac: (m['mac'] as String? ?? '').trim(),
      gateway: (m['gateway'] as String? ?? '').trim(),
      dhcp: m['dhcp'] == true,
      dns: rawDns is List ? rawDns.whereType<String>().where((d) => d.isNotEmpty).toList() : const [],
      primary: m['primary'] == true,
    ));
  }
  return out;
}

List<VolumeInfo> _parseVolumes(dynamic raw) {
  if (raw is! List) return const [];
  final out = <VolumeInfo>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final m = e.cast<String, dynamic>();
    final total = (m['total'] as num?)?.toInt() ?? 0;
    if (total <= 0) continue; // volume ที่อ่านความจุไม่ได้ = ไม่ต้องโชว์
    out.add(VolumeInfo(
      mount: m['mount'] as String? ?? '',
      name: m['name'] as String? ?? '',
      fs: m['fs'] as String? ?? '',
      totalBytes: total,
      freeBytes: (m['free'] as num?)?.toInt() ?? 0,
      boot: m['boot'] == true,
      removable: m['removable'] == true,
    ));
  }
  return out;
}

class DeviceDetail {
  // Identity
  final String computerName;
  final String localizedName;
  final String hostName;
  final String fullUserName;
  final String serialNumber;
  final String hardwareUUID;

  // Hardware model
  final String modelName;
  final String modelIdentifier;
  final String chip;

  // CPU
  final String processor;
  final String vendor;
  final String totalCores;
  final String cpuFrequency;
  final String cpuFrequencyMin;
  final String cpuFrequencyMax;
  final String cpuArchitecture;

  // Memory
  final String memory;
  final String memoryType;
  final String memoryManufacturer;

  // Storage
  final String storageName;
  final String storageType;
  final int storageCapacityBytes;
  final int storageAvailableBytes;

  // GPU
  final String gpu;

  // OS
  final String osVersion;
  final String systemVersion;
  final String kernelVersion;
  final String bootVolume;
  final String bootMode;
  final String timeSinceBoot;
  final String firmwareVersion;

  // Network
  final String ipAddress;

  // Displays
  final List<DisplayInfo> displaysDetail;

  // Applications
  final List<ApplicationInfo> applications;
  final List<VolumeInfo> volumes;
  final List<NetworkInterfaceInfo> interfaces;

  // Active app (macOS: NSWorkspace frontmostApplication)
  final String frontmostApp;

  const DeviceDetail({
    required this.computerName,
    required this.localizedName,
    required this.hostName,
    required this.fullUserName,
    required this.serialNumber,
    required this.hardwareUUID,
    required this.modelName,
    required this.modelIdentifier,
    required this.chip,
    required this.processor,
    required this.vendor,
    required this.totalCores,
    required this.cpuFrequency,
    required this.cpuFrequencyMin,
    required this.cpuFrequencyMax,
    required this.cpuArchitecture,
    required this.memory,
    required this.memoryType,
    required this.memoryManufacturer,
    required this.storageName,
    required this.storageType,
    required this.storageCapacityBytes,
    required this.storageAvailableBytes,
    required this.gpu,
    required this.osVersion,
    required this.systemVersion,
    required this.kernelVersion,
    required this.bootVolume,
    required this.bootMode,
    required this.timeSinceBoot,
    required this.firmwareVersion,
    required this.ipAddress,
    required this.displaysDetail,
    required this.applications,
    this.volumes = const [],
    this.interfaces = const [],
    this.frontmostApp = '',
  });

  // Backward-compat helpers used by existing code
  String get modelIdentifierDisplay => modelName.isNotEmpty ? modelName : modelIdentifier;
  String get processorDisplay => processor.isNotEmpty ? processor : chip;
  List<String> get displays => displaysDetail.map((d) => d.label).toList();
  String get storageAvailable => _formatBytes(storageAvailableBytes);
  String get storageTotal => _formatBytes(storageCapacityBytes);

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return 'N/A';
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(0)} MB';
    return '$bytes B';
  }

  static const _channel = MethodChannel('com.myarap/device_info');

  static Future<DeviceDetail> collect() async {
    try {
      if (Platform.isMacOS) return await _collectMacOS();
      if (Platform.isWindows) return await _collectWindows();
    } catch (_) {}
    return _fallback();
  }

  static Future<DeviceDetail> _collectMacOS() async {
    final Map<Object?, Object?> raw =
        await _channel.invokeMethod('getDeviceInfo');
    final m = raw.cast<String, dynamic>();

    String s(String key) {
      final v = m[key];
      return (v is String && v.isNotEmpty) ? v : '';
    }

    int i(String key) {
      final v = m[key];
      if (v is int) return v;
      if (v is double) return v.toInt();
      return 0;
    }

    final major = i('osVersionMajor');
    final minor = i('osVersionMinor');
    final patch = i('osVersionPatch');
    final osVersion = 'macOS $major.$minor.$patch';

    final rawDisplays = m['displays'];
    final displays = <DisplayInfo>[];
    if (rawDisplays is List) {
      for (final item in rawDisplays) {
        if (item is Map) {
          final dm = item.cast<String, dynamic>();
          displays.add(DisplayInfo(
            name: dm['name'] as String? ?? '',
            resolutionX: dm['resolutionX'] as int? ?? 0,
            resolutionY: dm['resolutionY'] as int? ?? 0,
            builtin: dm['builtin'] as bool? ?? false,
          ));
        }
      }
    }

    final rawApps = m['applications'];
    final apps = <ApplicationInfo>[];
    if (rawApps is List) {
      for (final item in rawApps) {
        if (item is Map) {
          final am = item.cast<String, dynamic>();
          final name = am['name'] as String? ?? '';
          if (name.isNotEmpty) {
            apps.add(ApplicationInfo(
              name: name,
              version: am['version'] as String? ?? '',
              size: am['size'] as int? ?? 0,
              publisher: am['publisher'] as String? ?? '',
              source: am['source'] as String? ?? '',
              installDate: am['installDate'] as String? ?? '',
              installLocation: am['installLocation'] as String? ?? '',
              architecture: am['architecture'] as String? ?? '',
              packageId: am['packageId'] as String? ?? '',
            ));
          }
        }
      }
    }

    return DeviceDetail(
      computerName: s('localizedName').isNotEmpty ? s('localizedName') : s('computerName'),
      localizedName: s('localizedName'),
      hostName: s('hostName'),
      fullUserName: s('fullUserName'),
      serialNumber: s('serialNumber'),
      hardwareUUID: s('hardwareUUID'),
      modelName: s('modelName'),
      modelIdentifier: s('modelIdentifier'),
      chip: s('chip'),
      processor: s('processor'),
      vendor: s('vendor'),
      totalCores: s('totalCores'),
      cpuFrequency: s('cpuFrequency'),
      cpuFrequencyMin: s('cpuFrequencyMin'),
      cpuFrequencyMax: s('cpuFrequencyMax'),
      cpuArchitecture: s('cpuArchitecture'),
      memory: s('memory'),
      memoryType: s('memoryType'),
      memoryManufacturer: s('memoryManufacturer'),
      storageName: s('storageName'),
      storageType: s('storageType'),
      storageCapacityBytes: i('storageCapacity'),
      storageAvailableBytes: i('storageAvailable'),
      gpu: s('gpu'),
      osVersion: osVersion,
      systemVersion: s('systemVersion'),
      kernelVersion: s('kernelVersion'),
      bootVolume: s('bootVolume'),
      bootMode: s('bootMode'),
      timeSinceBoot: s('timeSinceBoot'),
      firmwareVersion: s('firmwareVersion'),
      ipAddress: s('ipAddress'),
      displaysDetail: displays,
      applications: apps,
      volumes: _parseVolumes(m['volumes']),
      interfaces: _parseInterfaces(m['interfaces']),
      frontmostApp: s('frontmostApp'),
    );
  }

  static Future<DeviceDetail> _collectWindows() async {
    final info = await _windowsInfo();
    final memGB = int.tryParse(info['memoryGB'] as String? ?? '0') ?? 0;
    final cpuMHz = int.tryParse(info['cpuMaxSpeedMHz'] as String? ?? '0') ?? 0;

    // Parse displays
    final rawDisplays = info['displays'];
    final displays = <DisplayInfo>[];
    if (rawDisplays is List) {
      for (final item in rawDisplays) {
        if (item is Map) {
          displays.add(DisplayInfo(
            name: item['name'] as String? ?? 'Display',
            resolutionX: (item['resolutionX'] as num?)?.toInt() ?? 0,
            resolutionY: (item['resolutionY'] as num?)?.toInt() ?? 0,
            builtin: item['builtin'] as bool? ?? false,
          ));
        }
      }
    }
    if (displays.isEmpty) {
      displays.add(const DisplayInfo(name: 'Primary Display', resolutionX: 0, resolutionY: 0, builtin: false));
    }

    // Parse applications
    final rawApps = info['applications'];
    final applications = <ApplicationInfo>[];
    if (rawApps is List) {
      for (final item in rawApps) {
        if (item is Map) {
          final name = item['name'] as String? ?? '';
          if (name.isNotEmpty) {
            applications.add(ApplicationInfo(
              name: name,
              version: item['version'] as String? ?? '',
              size: (item['size'] as num?)?.toInt() ?? 0,
              publisher: item['publisher'] as String? ?? '',
              source: item['source'] as String? ?? '',
              installDate: item['installDate'] as String? ?? '',
              installLocation: item['installLocation'] as String? ?? '',
              architecture: item['architecture'] as String? ?? '',
              packageId: item['packageId'] as String? ?? '',
              nonRemovable: item['nonRemovable'] as bool? ?? false,
              signatureKind: item['signatureKind'] as String? ?? '',
            ));
          }
        }
      }
    }

    String s(String key) => info[key] as String? ?? '';

    return DeviceDetail(
      computerName: s('computerName'),
      localizedName: s('computerName'),
      hostName: s('computerName'),
      fullUserName: s('userName'),
      serialNumber: s('serialNumber'),
      hardwareUUID: s('uuid'),
      modelName: s('model'),
      modelIdentifier: s('model'),
      chip: '',
      processor: s('processor'),
      vendor: s('manufacturer'),
      totalCores: s('cores'),
      cpuFrequency: cpuMHz > 0 ? '${cpuMHz * 1000000}' : '',
      cpuFrequencyMin: '',
      cpuFrequencyMax: cpuMHz > 0 ? '${cpuMHz * 1000000}' : '',
      cpuArchitecture: s('arch'),
      memory: memGB > 0 ? '$memGB GB' : '',
      memoryType: '',
      memoryManufacturer: '',
      storageName: s('storageName'),
      storageType: s('storageType').isNotEmpty ? s('storageType') : 'Unknown',
      storageCapacityBytes: int.tryParse(s('storageBytes')) ?? 0,
      storageAvailableBytes: int.tryParse(s('storageFreeBytes')) ?? 0,
      gpu: s('gpu'),
      osVersion: s('osVersion'),
      systemVersion: s('osVersion'),
      kernelVersion: s('kernelVersion'),
      bootVolume: 'C:',
      bootMode: '',
      timeSinceBoot: s('timeSinceBoot'),
      firmwareVersion: s('firmwareVersion'),
      ipAddress: s('ipAddress'),
      displaysDetail: displays,
      applications: applications,
      volumes: _parseVolumes(info['volumes']),
      interfaces: _parseInterfaces(info['interfaces']),
    );
  }

  static Future<Map<String, dynamic>> _windowsInfo() async {
    // ⚠️ สคริปต์นี้ถูกส่งเป็น argument ของ powershell -Command → **เก็บเป็น ASCII ล้วน**
    // (คอมเมนต์ภาษาไทยอยู่ฝั่ง Dart เท่านั้น)
    //
    // volumes: ทุกไดรฟ์ที่เป็น local fixed disk (DriveType=3) — ไม่เอา USB/ออปติคัล/network drive
    // เดิมอ่านแค่ไดรฟ์ระบบตัวเดียว เครื่องที่แบ่ง partition (C: + D:) จึงเห็นแค่ลูกเดียวใน MYARAP
    //
    // applications: 3 ที่มา — registry Uninstall (HKLM/Wow6432Node/HKCU) + Get-AppxPackage
    // แต่ละรายการติด `source` = user | system | store เพื่อให้ backend แยกของที่มากับ OS
    // ออกจากของที่คนลงเอง (ไม่งั้นยอด Unclassified บวมด้วย VC++ Redist/Windows components)
    // และติด `publisher` จาก registry Publisher (มีมาแต่เดิมแต่ agent ไม่เคยส่ง)
    //
    // ⚠️ **Appx ใช้ `SignatureKind` ตัดสิน ห้ามเดาจากชื่อ/publisher** (แก้ 2026-08-06)
    // ของเดิมเดาจากชื่อ (`Microsoft.Windows*` / `Microsoft.UI*` / …) ซึ่งพลาดเยอะมาก —
    // `Microsoft.BingNews` ที่ preinstall มามี publisher เป็น "Microsoft Corporation"
    // เหมือน MSTeams ที่คนลงเองเป๊ะ แยกไม่ออก · ผลคือ Appx ที่มากับ Windows ~60 ตัว
    // หลุดไปเป็น `store` แล้วไปโผล่ในยอด Unclassified
    // `SignatureKind` เป็นการจำแนกของ Windows เอง: System = มากับ OS · Store/Developer/
    // Enterprise = คนลงเอง
    const script = r'''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "SilentlyContinue"
$bios     = Get-CimInstance Win32_BIOS
$cs       = Get-CimInstance Win32_ComputerSystem
$cpu      = Get-CimInstance Win32_Processor | Select-Object -First 1
$os       = Get-CimInstance Win32_OperatingSystem
$prod     = Get-CimInstance Win32_ComputerSystemProduct
$disk     = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
$physDisk = Get-PhysicalDisk | Sort-Object Size -Descending | Select-Object -First 1
$ip       = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
              $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*'
            } | Select-Object -First 1).IPAddress

$arch = if ($cpu.Architecture -eq 9) { 'x64' } elseif ($cpu.Architecture -eq 0) { 'x86' } else { $cpu.Architecture.ToString() }
$memGB = [math]::Floor($cs.TotalPhysicalMemory / 1GB)
$user = $cs.UserName; if ($user -like '*\*') { $user = $user.Split('\')[-1] }

$storageType = switch ($physDisk.MediaType) {
  'SSD'         { 'SSD' }
  'HDD'         { 'HDD' }
  default       { 'Unknown' }
}

# every local fixed disk (DriveType=3) - excludes USB / optical / network drives
$vols = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
  Sort-Object DeviceID | ForEach-Object {
    @{
      mount = $_.DeviceID
      name  = if ($_.VolumeName) { $_.VolumeName } else { '' }
      fs    = if ($_.FileSystem) { $_.FileSystem } else { '' }
      total = [long]($_.Size)
      free  = [long]($_.FreeSpace)
      boot  = ($_.DeviceID -eq $env:SystemDrive)
    }
  })

# ── การ์ดเครือข่ายทุกใบที่ใช้งานอยู่ (IMPL-16 Phase 1) ──
# 🔴 เป็น list ต่อ interface ไม่ใช่ค่าเดียว — $ip ด้านบนเอา "ใบแรกที่เจอ" ซึ่งไม่แน่นอนว่าเป็น
# สาย LAN หรือ Wi-Fi บนเครื่องที่มีทั้งสองอย่าง (บทเรียนเดียวกับ $vols ที่เดิมส่งไดรฟ์เดียว)
# ⚠️ ต้องกรอง 127.* และ 169.254.* ออก — link-local คือที่อยู่ที่เครื่องตั้งเองตอนหา DHCP ไม่เจอ
$ifs = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
  ForEach-Object {
    $ipRow = $_
    $ad = Get-NetAdapter -InterfaceIndex $ipRow.InterfaceIndex -ErrorAction SilentlyContinue
    # gateway ของ interface ใบนั้นโดยเฉพาะ (ไม่ใช่ default route ของทั้งเครื่อง)
    $gw = (Get-NetRoute -InterfaceIndex $ipRow.InterfaceIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
           Select-Object -First 1).NextHop
    $dns = @(Get-DnsClientServerAddress -InterfaceIndex $ipRow.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Select-Object -ExpandProperty ServerAddresses)
    @{
      name     = if ($ad) { $ad.Name } else { $ipRow.InterfaceAlias }
      # ชนิดการ์ดจาก PhysicalMediaType ของ Windows เอง — ไม่เดาจากชื่อ
      # ("Native 802.11"/"Wireless WAN" = ไร้สาย · "802.3" = สาย)
      kind     = if ($ad -and $ad.PhysicalMediaType -match '802\.11|Wireless') { 'wifi' }
                 elseif ($ad -and $ad.PhysicalMediaType -match '802\.3') { 'lan' }
                 else { 'other' }
      ipv4     = $ipRow.IPAddress
      prefix   = [int]$ipRow.PrefixLength
      mac      = if ($ad -and $ad.MacAddress) { $ad.MacAddress } else { '' }
      gateway  = if ($gw) { $gw } else { '' }
      # PrefixOrigin = Dhcp เมื่อที่อยู่มาจาก DHCP · Manual = ตั้งเอง (static)
      dhcp     = ($ipRow.PrefixOrigin -eq 'Dhcp')
      dns      = $dns
      # ใบที่มี default route = ใบหลักที่ใช้ออกอินเทอร์เน็ตจริง
      primary  = [bool]$gw
    }
  } | Sort-Object { -[int]$_.primary })

$bootTime = $os.LastBootUpTime
$uptime = (Get-Date) - $bootTime
$uptimeStr = "$([math]::Floor($uptime.TotalDays))d $($uptime.Hours)h $($uptime.Minutes)m"

$displays = @(Get-CimInstance Win32_VideoController |
  Where-Object { $_.CurrentHorizontalResolution -gt 0 } |
  ForEach-Object {
    @{
      name        = $_.Name
      resolutionX = [int]$_.CurrentHorizontalResolution
      resolutionY = [int]$_.CurrentVerticalResolution
      builtin     = $false
    }
  })
if ($displays.Count -eq 0) {
  $displays = @(@{ name = 'Primary Display'; resolutionX = 0; resolutionY = 0; builtin = $false })
}

$gpu = (Get-CimInstance Win32_VideoController | Select-Object -First 1).Name

$regPaths = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$seen = @{}
$apps = @(foreach ($path in $regPaths) {
  # Wow6432Node = 32-bit view of the registry -> the app itself is x86.
  # NOTE: use a distinct name, `$arch` is already the OS architecture above.
  $appArch = if ($path -like '*Wow6432Node*') { 'x86' } else { 'x64' }
  Get-ItemProperty $path -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' } |
    ForEach-Object {
      $name = $_.DisplayName.Trim()
      if (-not $seen[$name]) {
        $seen[$name] = $true
        # SystemComponent=1 or ParentKeyName set = runtime/redistributable hidden from
        # Add/Remove Programs (VC++ Redist, .NET runtime) -> classify as system
        $isSys = ($_.SystemComponent -eq 1) -or ($_.ParentKeyName -ne $null)
        # InstallDate is stored as 'yyyyMMdd' (no separators, no time). Some installers
        # write garbage or leave it out entirely -> emit '' rather than a wrong date.
        $inst = ''
        if ($_.InstallDate -and $_.InstallDate -match '^\d{8}$') {
          $inst = $_.InstallDate.Substring(0,4) + '-' + $_.InstallDate.Substring(4,2) + '-' + $_.InstallDate.Substring(6,2)
        }
        @{
          name            = $name
          version         = if ($_.DisplayVersion) { $_.DisplayVersion } else { '' }
          size            = [long]($_.EstimatedSize) * 1024
          publisher       = if ($_.Publisher) { $_.Publisher.Trim() } else { '' }
          source          = if ($isSys) { 'system' } else { 'user' }
          installDate     = $inst
          installLocation = if ($_.InstallLocation) { $_.InstallLocation.Trim() } else { '' }
          architecture    = $appArch
          # PSChildName = the Uninstall subkey name, which for MSI packages is the
          # ProductCode GUID -> doubles as both Package ID and Product ID.
          packageId       = if ($_.PSChildName) { $_.PSChildName } else { '' }
        }
      }
    }
})

# Store apps never appear under registry Uninstall - must be queried separately.
# SilentlyContinue: some machines block the Appx cmdlets by policy.
$apps += @(Get-AppxPackage -ErrorAction SilentlyContinue |
  Where-Object { -not $_.IsFramework -and $_.Name } |
  ForEach-Object {
    $dn = $_.Name
    if (-not $seen[$dn]) {
      $seen[$dn] = $true
      @{
        name            = $dn
        version         = $_.Version.ToString()
        size            = 0
        # Publisher ของ Appx เป็น DN เช่น "CN=Microsoft Corporation, O=..., C=US" -> เอา CN
        # BUT some packages carry a GUID as CN (AppUp.IntelGraphicsExperience ->
        # "CN=EB51A5DA-0E72-4863-82E4-EA21C1F8DFE3"). A GUID is not a publisher name and
        # showing it to a human is worse than showing nothing -> emit ''.
        publisher       = $(
          $cn = if ($_.Publisher) { ($_.Publisher -replace '^CN=([^,]+).*$', '$1').Trim() } else { '' }
          if ($cn -match '^\{?[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\}?$') { '' } else { $cn }
        )
        # Appx has no install date at all - leave blank rather than inventing one from
        # the folder timestamp, which changes on every app update.
        installDate     = ''
        installLocation = if ($_.InstallLocation) { $_.InstallLocation } else { '' }
        architecture    = if ($_.Architecture) { $_.Architecture.ToString().ToLower() } else { '' }
        packageId       = if ($_.PackageFullName) { $_.PackageFullName } else { '' }
        # SignatureKind is Windows' own classification - System = shipped with the OS.
        # Store / Developer / Enterprise = someone chose to install it.
        # Do NOT guess from the package name or publisher: preinstalled apps such as
        # Microsoft.BingNews carry publisher "Microsoft Corporation" exactly like
        # user-installed ones (MSTeams), so the name/publisher tells us nothing.
        source    = if ($_.SignatureKind -eq 'System') { 'system' } else { 'store' }
        # ── สัญญาณดิบสำหรับแยก "Appx ที่มากับเครื่อง" ออกจาก "ที่คนโหลดเอง" ──
        # ปัญหาที่พบจริง 2026-08-19: `SignatureKind` แยกไม่ออก — ของที่ OEM/Microsoft ใส่มากับ
        # image (Intel Graphics, BingWeather, Clipchamp) เซ็นแบบ Store เหมือนที่คนโหลดเองเป๊ะ
        # ผลคือ **61 จาก 89 รายการที่รอกำหนดนโยบายบนเครื่องหนึ่งเป็น Appx ที่ติดมากับ Windows**
        #
        # ยังไม่เปลี่ยนกติกา `source` ตรงนี้ — ส่งสัญญาณดิบขึ้นไปก่อนแล้วดูข้อมูลจริงจากหลายเครื่อง
        # ค่อยตัดสิน (หลักเดียวกับที่ ITIL ว่าไว้: discovery เก็บให้ครบ ตัดสินใจที่ server)
        # ⚠️ ทั้งสอง property ไม่มีใน Windows รุ่นเก่า -> ใช้ -ErrorAction/ternary กัน error
        nonRemovable = $(try { [bool]$_.NonRemovable } catch { $false })
        signatureKind = if ($_.SignatureKind) { $_.SignatureKind.ToString() } else { '' }
      }
    }
  })

@{
  serialNumber    = $bios.SerialNumber
  computerName    = $cs.Name
  manufacturer    = $cs.Manufacturer
  model           = $cs.Model
  cores           = $cs.NumberOfLogicalProcessors.ToString()
  userName        = $user
  memoryGB        = $memGB.ToString()
  processor       = $cpu.Name
  arch            = $arch
  cpuMaxSpeedMHz  = $cpu.MaxClockSpeed.ToString()
  osVersion       = "$($os.Caption) $($os.Version)".Trim()
  kernelVersion   = $os.Version
  uuid            = $prod.UUID
  gpu             = $gpu
  storageBytes    = $disk.Size.ToString()
  storageFreeBytes= $disk.FreeSpace.ToString()
  storageName     = $disk.VolumeName
  storageType     = $storageType
  firmwareVersion = $bios.SMBIOSBIOSVersion
  timeSinceBoot   = $uptimeStr
  ipAddress       = $ip
  displays        = $displays
  volumes         = $vols
  interfaces      = $ifs
  applications    = $apps
} | ConvertTo-Json -Depth 4
''';

    try {
      final proc = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      final output = proc.stdout.toString().trim();
      if (output.isEmpty) return {};
      final clean = output.startsWith('﻿') ? output.substring(1) : output;
      return jsonDecode(clean) as Map<String, dynamic>;
    } catch (_) {}
    return {};
  }

  static DeviceDetail _fallback() => const DeviceDetail(
        computerName: 'Unknown',
        localizedName: '',
        hostName: '',
        fullUserName: '',
        serialNumber: '',
        hardwareUUID: '',
        modelName: 'Unknown',
        modelIdentifier: '',
        chip: '',
        processor: 'Unknown',
        vendor: '',
        totalCores: '',
        cpuFrequency: '',
        cpuFrequencyMin: '',
        cpuFrequencyMax: '',
        cpuArchitecture: '',
        memory: 'Unknown',
        memoryType: '',
        memoryManufacturer: '',
        storageName: '',
        storageType: '',
        storageCapacityBytes: 0,
        storageAvailableBytes: 0,
        gpu: '',
        osVersion: 'Unknown',
        systemVersion: '',
        kernelVersion: '',
        bootVolume: '',
        bootMode: '',
        timeSinceBoot: '',
        firmwareVersion: '',
        ipAddress: '',
        displaysDetail: [DisplayInfo(name: 'Display', resolutionX: 0, resolutionY: 0, builtin: false)],
        applications: [],
      );
}
