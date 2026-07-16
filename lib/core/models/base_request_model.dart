import '../config/app_config.dart';

class BaseRequestModel {
  final String? token;
  final Map<String, dynamic> data;

  const BaseRequestModel({
    this.token,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
        'token': token,
        'data': data,
        'APIVersion': AppConfig.apiVersion,
      };
}
