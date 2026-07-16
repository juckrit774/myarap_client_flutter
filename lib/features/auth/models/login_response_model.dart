/// V3 device auth response — จาก POST /v3/api/auth
class DeviceAuthResponse {
  final String accessToken;
  final String refreshToken;
  final String fingerprint;
  final String assetTag;
  final String assetId;

  const DeviceAuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.fingerprint,
    required this.assetTag,
    required this.assetId,
  });

  factory DeviceAuthResponse.fromJson(Map<String, dynamic> json) =>
      DeviceAuthResponse(
        accessToken: json['accessToken'] as String? ?? '',
        refreshToken: json['refreshToken'] as String? ?? '',
        fingerprint: json['fingerprint'] as String? ?? '',
        assetTag: json['assetTag'] as String? ?? '',
        assetId: json['assetId'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'fingerprint': fingerprint,
        'assetTag': assetTag,
        'assetId': assetId,
      };
}

class WebService {
  final String key;
  final String url;

  const WebService({required this.key, required this.url});

  factory WebService.fromJson(Map<String, dynamic> json) => WebService(
        key: json['key'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'key': key, 'url': url};
}

class UserConfig {
  final int imageReportLimit;

  const UserConfig({required this.imageReportLimit});

  factory UserConfig.fromJson(Map<String, dynamic> json) =>
      UserConfig(imageReportLimit: json['imageReportLimit'] as int? ?? 5);

  Map<String, dynamic> toJson() => {'imageReportLimit': imageReportLimit};
}

class LoginUser {
  final String imageURL;
  final String fullName;
  final String role;
  final UserConfig config;

  const LoginUser({
    required this.imageURL,
    required this.fullName,
    required this.role,
    required this.config,
  });

  factory LoginUser.fromJson(Map<String, dynamic> json) => LoginUser(
        imageURL: json['imageURL'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        role: json['role'] as String? ?? '',
        config: UserConfig.fromJson(json['config'] as Map<String, dynamic>? ?? {}),
      );

  Map<String, dynamic> toJson() => {
        'imageURL': imageURL,
        'fullName': fullName,
        'role': role,
        'config': config.toJson(),
      };
}

class LoginResponseModel {
  final String assetNo;
  final String computerName;
  final LoginUser user;
  final List<WebService> webService;
  final String token;
  final DateTime? lastUpdated;

  const LoginResponseModel({
    required this.assetNo,
    required this.computerName,
    required this.user,
    required this.webService,
    required this.token,
    this.lastUpdated,
  });

  // Convenience getters used by the view model
  String get fullName => user.fullName;
  String? get profileImageUrl => user.imageURL.isNotEmpty ? user.imageURL : null;

  String? getWebServiceUrl(String key) {
    try {
      return webService.firstWhere((ws) => ws.key == key).url;
    } catch (_) {
      return null;
    }
  }

  factory LoginResponseModel.fromJson(Map<String, dynamic> json) =>
      LoginResponseModel(
        assetNo: json['assetNo'] as String? ?? '',
        computerName: json['computerName'] as String? ?? '',
        user: LoginUser.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
        webService: (json['webService'] as List<dynamic>? ?? [])
            .map((e) => WebService.fromJson(e as Map<String, dynamic>))
            .toList(),
        token: json['token'] as String? ?? '',
        lastUpdated: json['lastUpdated'] != null
            ? DateTime.tryParse(json['lastUpdated'].toString())
            : null,
      );

  Map<String, dynamic> toJson() => {
        'assetNo': assetNo,
        'computerName': computerName,
        'user': user.toJson(),
        'webService': webService.map((ws) => ws.toJson()).toList(),
        'token': token,
        'lastUpdated': lastUpdated?.toIso8601String(),
      };

  LoginResponseModel copyWith({DateTime? lastUpdated}) => LoginResponseModel(
        assetNo: assetNo,
        computerName: computerName,
        user: user,
        webService: webService,
        token: token,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
}
