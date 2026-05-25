import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/models/device_model.dart';
import '../../../auth/models/login_response_model.dart';
import '../../../../core/models/base_request_model.dart';
import '../../../../core/services/network_manager.dart';
import '../../../../core/storage/cache_manager.dart';

class UpdateDeviceResponse {
  final double dueDateTime;
  final int? logId;

  const UpdateDeviceResponse({required this.dueDateTime, this.logId});

  factory UpdateDeviceResponse.fromJson(Map<String, dynamic> json) =>
      UpdateDeviceResponse(
        dueDateTime: (json['dueDateTime'] as num?)?.toDouble() ?? 0,
        logId: json['logId'] as int?,
      );
}

class HomeViewModel extends ChangeNotifier {
  bool isLoading = true;
  String? errorMessage;
  String? assetUpdatedAt;

  LoginResponseModel? loginResponse;
  DeviceDetail? deviceDetail;

  Timer? _heartbeatTimer;

  String get userName => loginResponse?.fullName ?? 'MYARAP User';
  String get assetNo => loginResponse?.assetNo ?? '-';
  String? get profileImageUrl => loginResponse?.profileImageUrl;
  DateTime? get lastUpdated => loginResponse?.lastUpdated;
  String? get token => loginResponse?.token;

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
      _loadCachedLogin(),
      _loadDeviceInfo(),
    ]);

    await _authenticate();

    isLoading = false;
    notifyListeners();
  }

  Future<void> _loadCachedLogin() async {
    loginResponse = await CacheManager.getLoginResponse();
  }

  Future<void> _loadDeviceInfo() async {
    deviceDetail = await DeviceDetail.collect();
  }

  Future<void> _authenticate() async {
    final d = deviceDetail;
    if (d == null) return;

    try {
      final response = await NetworkManager.instance.request<LoginResponseModel>(
        request: BaseRequestModel(
          module: 'Authentication',
          target: 'LoginWithClient',
          token: null,
          data: _buildLoginPayload(d),
        ),
        parseEntries: (json) => json != null
            ? LoginResponseModel.fromJson(json as Map<String, dynamic>)
            : null,
      );

      if (response.isSuccess && response.entries != null) {
        loginResponse = response.entries!.copyWith(lastUpdated: DateTime.now());
        await CacheManager.saveLoginResponse(loginResponse!);

        // Notify server device is online — same flow as native app
        await _updateDeviceInfo();
      }
    } catch (_) {
      if (loginResponse == null) {
        loginResponse = LoginResponseModel(
          assetNo: 'AST-00000',
          computerName: d.computerName,
          user: const LoginUser(
            imageURL: '',
            fullName: 'MYARAP User',
            role: '',
            config: UserConfig(imageReportLimit: 5),
          ),
          webService: const [],
          token: '',
          lastUpdated: DateTime.now(),
        );
      }
    }
  }

  Future<void> _updateDeviceInfo() async {
    final d = deviceDetail;
    final lr = loginResponse;
    if (d == null || lr == null) return;

    final updateUrl = lr.getWebServiceUrl('UPDATE');
    if (updateUrl == null || updateUrl.isEmpty) return;

    try {
      final response = await NetworkManager.instance.request<UpdateDeviceResponse>(
        request: BaseRequestModel(
          module: 'Asset',
          target: 'UpdateDeviceInfo',
          token: lr.token,
          data: _buildUpdatePayload(d, lr),
        ),
        parseEntries: (json) => json != null
            ? UpdateDeviceResponse.fromJson(json as Map<String, dynamic>)
            : null,
        url: updateUrl,
      );

      if (response.isSuccess && response.entries != null) {
        final now = DateTime.now();
        assetUpdatedAt =
            '${now.month}/${now.day}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')} '
            '${now.hour >= 12 ? 'PM' : 'AM'}';
        notifyListeners();

        _scheduleNextUpdate(response.entries!.dueDateTime);
      }
    } catch (_) {
      // Server unreachable — skip heartbeat
    }
  }

  // Mirror of native app's scheduleNextUpdate
  void _scheduleNextUpdate(double dueDateTime) {
    _heartbeatTimer?.cancel();
    final delaySeconds = dueDateTime - (DateTime.now().millisecondsSinceEpoch / 1000);
    if (delaySeconds <= 0) {
      _updateDeviceInfo();
      return;
    }
    _heartbeatTimer = Timer(Duration(seconds: delaySeconds.toInt()), () {
      _updateDeviceInfo();
    });
  }

  // Replicates Swift's String.capitalized: uppercases first char of each word
  // (words split by hyphen, space, underscore), lowercases the rest.
  // Native app applies this to fullDeviceName via Host.current().name.capitalized.
  String _capitalized(String s) {
    if (s.isEmpty) return s;
    final sb = StringBuffer();
    bool newWord = true;
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '-' || ch == ' ' || ch == '_') {
        sb.write(ch);
        newWord = true;
      } else if (newWord) {
        sb.write(ch.toUpperCase());
        newWord = false;
      } else {
        sb.write(ch.toLowerCase());
      }
    }
    return sb.toString();
  }

  Map<String, dynamic> _buildLoginPayload(DeviceDetail d) {
    final osVer = d.osVersion.replaceAll('macOS ', '');
    final cores = int.tryParse(d.totalCores.split(' ').first) ?? 0;
    final memGB = int.tryParse(
            d.memory.replaceAll(' GB', '').replaceAll('GB', '').trim()) ??
        0;

    return {
      'userLogOn': d.fullUserName,
      'assetNumber': d.localizedName.isNotEmpty ? d.localizedName : d.computerName,
      'deviceInfo': _deviceInfoPayload(d, osVer, cores, memGB),
      'network': {
        'publicIP': d.ipAddress,
        'privateIP': [],
        'uniqueId': 0,
        'active': false,
      },
      'location': null,
      'fullDeviceName': _capitalized(d.hostName.replaceAll('.local', '')),
      'uniqueId': 0,
      'active': false,
    };
  }

  Map<String, dynamic> _buildUpdatePayload(DeviceDetail d, LoginResponseModel lr) {
    final osVer = d.osVersion.replaceAll('macOS ', '');
    final cores = int.tryParse(d.totalCores.split(' ').first) ?? 0;
    final memGB = int.tryParse(
            d.memory.replaceAll(' GB', '').replaceAll('GB', '').trim()) ??
        0;

    return {
      'deviceInfo': _deviceInfoPayload(d, osVer, cores, memGB),
      'network': {
        'publicIP': d.ipAddress,
        'privateIP': [],
        'uniqueId': 0,
        'active': false,
      },
      'location': null,
      'applications': d.applications
          .map((app) => {
                'vendor': '',
                'name': app.name,
                'size': app.size,
                'version': app.version,
                'installDate': 0,
                'uniqueId': 0,
                'active': false,
              })
          .toList(),
      'curerntUserLogOn': lr.user.fullName,
      'computerName': d.modelName,
      'fullDeviceName': _capitalized(d.hostName.replaceAll('.local', '')),
      'uniqueId': 0,
      'active': false,
    };
  }

  Map<String, dynamic> _deviceInfoPayload(
      DeviceDetail d, String osVer, int cores, int memGB) {
    return {
      'model': d.modelIdentifier,
      'manufacturer': 'APPLE',
      'serialNumber': d.serialNumber,
      'uuid': d.hardwareUUID,
      'sku': '',
      'board': {
        'manufacturer': '',
        'model': '',
        'version': '',
        'serialNumber': '',
        'uniqueId': 0,
        'active': false,
      },
      'os': {
        'manufacturer': '',
        'platform': 'macOS',
        'name': 'macOS',
        'version': osVer,
        'arch': d.cpuArchitecture,
        'serial': '',
        'installDate': 0,
        'productType': '',
        'uniqueId': 0,
        'active': false,
      },
      'cpu': {
        'manufacturer': '',
        'brand': d.processorDisplay,
        'vendor': d.vendor,
        'model': 0,
        'stepping': 0,
        'speed': double.tryParse(d.cpuFrequency) ?? 0.0,
        'speedmin': int.tryParse(d.cpuFrequencyMin) ?? 0,
        'speedmax': double.tryParse(d.cpuFrequencyMax) ?? 0.0,
        'governor': '',
        'cores': cores,
        'physicalCores': cores,
        'processors': 0,
        'socket': '',
        'uniqueId': 0,
        'active': false,
      },
      'graphics': {
        'controllers': [
          {
            'infSection': '',
            'deviceID': '',
            'vendor': '',
            'model': d.gpu,
            'bus': '',
            'vram': 0,
            'vramDynamic': false,
            'driverDate': 0,
            'driverVersion': '',
            'uniqueId': 0,
            'active': false,
          }
        ],
        'displays': d.displaysDetail
            .map((disp) => {
                  'deviceID': disp.name,
                  'vendor': '',
                  'model': disp.name,
                  'main': false,
                  'builtin': disp.builtin,
                  'connection': '',
                  'pixeldepth': 0,
                  'resolutionx': disp.resolutionX,
                  'resolutiony': disp.resolutionY,
                  'currentResX': 0,
                  'currentResY': 0,
                  'uniqueId': 0,
                  'active': false,
                })
            .toList(),
        'uniqueId': 0,
        'active': false,
      },
      'memory': [
        {
          'manufacturer': d.memoryManufacturer,
          'bank': '',
          'type': d.memoryType,
          'size': memGB * 1024 * 1024 * 1024,
          'clockSpeed': 0,
          'partNum': '',
          'serialNumber': '',
          'uniqueId': 0,
          'active': false,
        }
      ],
      'storage': [
        {
          'vendor': '',
          'name': d.storageName,
          'type': d.storageType,
          'size': d.storageCapacityBytes,
          'serialNumber': '',
          'uniqueId': 0,
          'active': false,
        }
      ],
      'uniqueId': 0,
      'active': false,
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
