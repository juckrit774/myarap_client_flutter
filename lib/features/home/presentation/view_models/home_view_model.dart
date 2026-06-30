import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/models/device_model.dart';
import '../../../auth/models/login_response_model.dart';
import '../../../../core/services/network_manager.dart';
import '../../../../core/storage/cache_manager.dart';

// heartbeat interval เมื่อ V3 ไม่ส่ง dueDateTime กลับมา
const _kHeartbeatInterval = Duration(minutes: 10);

class HomeViewModel extends ChangeNotifier {
  bool isLoading = true;
  String? errorMessage;
  String? assetUpdatedAt;

  // V3 auth result
  DeviceAuthResponse? _deviceAuth;
  DeviceDetail? deviceDetail;

  Timer? _heartbeatTimer;

  String get userName => deviceDetail?.computerName ?? _deviceAuth?.assetTag ?? 'MYARAP User';
  String get assetNo => _deviceAuth?.assetTag ?? '-';
  String? get profileImageUrl => null;
  DateTime? get lastUpdated => null;
  String? get accessToken => _deviceAuth?.accessToken;

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
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

    await _authenticate();

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
      await NetworkManager.instance.putV3('/v3/api/device', _buildDevicePayload(d));

      final now = DateTime.now();
      assetUpdatedAt =
          '${now.month}/${now.day}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')} '
          '${now.hour >= 12 ? 'PM' : 'AM'}';
      notifyListeners();

      // รายงาน installed software (opt-in)
      await _reportSoftware(d);

      // ตั้ง heartbeat ถัดไปด้วย fixed interval (V3 ไม่ส่ง dueDateTime กลับมา)
      _scheduleHeartbeat();
    } catch (_) {
      // server unreachable — heartbeat จะลองใหม่ตาม schedule
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

  Map<String, dynamic> _buildDevicePayload(DeviceDetail d) {
    final isWindows = Platform.isWindows;
    return {
      'hostname': d.computerName,
      'os': d.osVersion,
      'serialNumber': d.serialNumber,
      'model': d.modelIdentifier,
      'brand': isWindows ? (d.vendor.isNotEmpty ? d.vendor : 'Microsoft') : 'Apple',
      'cpu': d.processorDisplay,
      'ram': d.memory,
      'agentVersion': '3.0.0',
    };
  }

  Future<void> refresh() async {
    isLoading = true;
    notifyListeners();
    await _loadDeviceInfo();
    await _authenticate();
    isLoading = false;
    notifyListeners();
  }
}
