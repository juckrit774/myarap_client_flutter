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

  const ApplicationInfo({
    required this.name,
    required this.version,
    required this.size,
    this.publisher = '',
    this.source = '',
  });
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
  Get-ItemProperty $path -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' } |
    ForEach-Object {
      $name = $_.DisplayName.Trim()
      if (-not $seen[$name]) {
        $seen[$name] = $true
        # SystemComponent=1 or ParentKeyName set = runtime/redistributable hidden from
        # Add/Remove Programs (VC++ Redist, .NET runtime) -> classify as system
        $isSys = ($_.SystemComponent -eq 1) -or ($_.ParentKeyName -ne $null)
        @{
          name      = $name
          version   = if ($_.DisplayVersion) { $_.DisplayVersion } else { '' }
          size      = [long]($_.EstimatedSize) * 1024
          publisher = if ($_.Publisher) { $_.Publisher.Trim() } else { '' }
          source    = if ($isSys) { 'system' } else { 'user' }
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
        name      = $dn
        version   = $_.Version.ToString()
        size      = 0
        publisher = if ($_.Publisher) { ($_.Publisher -replace '^CN=([^,]+).*$', '$1').Trim() } else { '' }
        # SignatureKind is Windows' own classification - System = shipped with the OS.
        # Store / Developer / Enterprise = someone chose to install it.
        # Do NOT guess from the package name or publisher: preinstalled apps such as
        # Microsoft.BingNews carry publisher "Microsoft Corporation" exactly like
        # user-installed ones (MSTeams), so the name/publisher tells us nothing.
        source    = if ($_.SignatureKind -eq 'System') { 'system' } else { 'store' }
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
