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

class ApplicationInfo {
  final String name;
  final String version;
  final int size;

  const ApplicationInfo({
    required this.name,
    required this.version,
    required this.size,
  });
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
    );
  }

  static Future<DeviceDetail> _collectWindows() async {
    final info = await _windowsInfo();
    final memGB = int.tryParse(info['memoryGB'] ?? '0') ?? 0;
    return DeviceDetail(
      computerName: info['computerName'] ?? '',
      localizedName: info['computerName'] ?? '',
      hostName: info['computerName'] ?? '',
      fullUserName: info['userName'] ?? '',
      serialNumber: info['serialNumber'] ?? '',
      hardwareUUID: info['uuid'] ?? '',
      modelName: info['model'] ?? '',
      modelIdentifier: info['model'] ?? '',
      chip: '',
      processor: info['processor'] ?? '',
      vendor: info['manufacturer'] ?? '',
      totalCores: info['cores'] ?? '',
      cpuFrequency: '',
      cpuFrequencyMin: '',
      cpuFrequencyMax: '',
      cpuArchitecture: info['arch'] ?? '',
      memory: memGB > 0 ? '$memGB GB' : (info['memory'] ?? ''),
      memoryType: '',
      memoryManufacturer: '',
      storageName: info['storageName'] ?? '',
      storageType: 'HDD',
      storageCapacityBytes: int.tryParse(info['storageBytes'] ?? '0') ?? 0,
      storageAvailableBytes: int.tryParse(info['storageFreeBytes'] ?? '0') ?? 0,
      gpu: info['gpu'] ?? '',
      osVersion: info['osVersion'] ?? '',
      systemVersion: info['osVersion'] ?? '',
      kernelVersion: '',
      bootVolume: '',
      bootMode: '',
      timeSinceBoot: '',
      firmwareVersion: '',
      ipAddress: info['ipAddress'] ?? '',
      displaysDetail: const [DisplayInfo(name: 'Primary Display', resolutionX: 0, resolutionY: 0, builtin: false)],
      applications: const [],
    );
  }

  static Future<Map<String, String>> _windowsInfo() async {
    const script = r'''
$ErrorActionPreference = "SilentlyContinue"
$bios   = Get-CimInstance Win32_BIOS
$cs     = Get-CimInstance Win32_ComputerSystem
$cpu    = Get-CimInstance Win32_Processor | Select-Object -First 1
$os     = Get-CimInstance Win32_OperatingSystem
$prod   = Get-CimInstance Win32_ComputerSystemProduct
$gpu    = Get-CimInstance Win32_VideoController | Select-Object -First 1
$disk   = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$ip     = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
            $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*'
          } | Select-Object -First 1).IPAddress
$arch   = if ($cpu.Architecture -eq 9) { 'x64' } elseif ($cpu.Architecture -eq 0) { 'x86' } else { $cpu.Architecture.ToString() }
$memGB  = [math]::Floor($cs.TotalPhysicalMemory / 1GB)
$user   = $cs.UserName; if ($user -like '*\*') { $user = $user.Split('\')[-1] }
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
  osVersion       = "$($os.Caption) $($os.Version)".Trim()
  uuid            = $prod.UUID
  gpu             = $gpu.Name
  storageBytes    = $disk.Size.ToString()
  storageFreeBytes= $disk.FreeSpace.ToString()
  storageName     = $disk.VolumeName
  ipAddress       = $ip
} | ConvertTo-Json
''';

    final result = <String, String>{};
    try {
      final proc = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: false,
      );
      final json = proc.stdout.toString().trim();
      if (json.isEmpty) return result;

      // Simple JSON key-value parse (avoids dart:convert import)
      final re = RegExp(r'"(\w+)"\s*:\s*"([^"]*)"');
      for (final m in re.allMatches(json)) {
        result[m.group(1)!] = m.group(2)!;
      }
    } catch (_) {}
    return result;
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
