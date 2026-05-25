import '../config/app_config.dart';

class BaseRequestModel {
  final String module;
  final String target;
  final String? token;
  final Map<String, dynamic> data;

  const BaseRequestModel({
    required this.module,
    required this.target,
    this.token,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
        'module': module,
        'target': target,
        'token': token,
        'data': data,
        'APIVersion': AppConfig.apiVersion,
      };
}
