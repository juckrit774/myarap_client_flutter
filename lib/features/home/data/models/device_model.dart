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
    return DeviceDetail(
      computerName: info['computerName'] ?? '',
      localizedName: info['computerName'] ?? '',
      hostName: info['computerName'] ?? '',
      fullUserName: '',
      serialNumber: '',
      hardwareUUID: '',
      modelName: info['productName'] ?? '',
      modelIdentifier: info['productName'] ?? '',
      chip: '',
      processor: '${info['cores'] ?? ''} cores',
      vendor: '',
      totalCores: info['cores'] ?? '',
      cpuFrequency: '',
      cpuFrequencyMin: '',
      cpuFrequencyMax: '',
      cpuArchitecture: '',
      memory: info['memory'] ?? '',
      memoryType: '',
      memoryManufacturer: '',
      storageName: '',
      storageType: '',
      storageCapacityBytes: 0,
      storageAvailableBytes: 0,
      gpu: '',
      osVersion: info['osVersion'] ?? '',
      systemVersion: info['osVersion'] ?? '',
      kernelVersion: '',
      bootVolume: '',
      bootMode: '',
      timeSinceBoot: '',
      firmwareVersion: '',
      ipAddress: '',
      displaysDetail: const [DisplayInfo(name: 'Primary Display', resolutionX: 0, resolutionY: 0, builtin: false)],
      applications: const [],
    );
  }

  static Future<Map<String, String>> _windowsInfo() async {
    try {
      final r = await Process.run('wmic', ['computersystem', 'get', 'Name,TotalPhysicalMemory'], runInShell: true);
      final lines = r.stdout.toString().split('\n');
      if (lines.length > 1) {
        final parts = lines[1].trim().split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          final memMB = int.tryParse(parts[1]) ?? 0;
          return {
            'computerName': parts[0],
            'memory': '${memMB ~/ (1024 * 1024 * 1024)} GB',
          };
        }
      }
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
