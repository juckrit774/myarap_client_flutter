import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/base_request_model.dart';
import '../models/base_response_model.dart';

class NetworkManager {
  static final NetworkManager _instance = NetworkManager._();
  static NetworkManager get instance => _instance;

  NetworkManager._() {
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    };
  }

  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  ));

  Future<void> updateBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('server_url') ?? AppConfig.baseUrl;
    _dio.options.baseUrl = url;
  }

  Future<BaseResponseModel<T>> request<T>({
    required BaseRequestModel request,
    required T? Function(dynamic json) parseEntries,
    String? url,
  }) async {
    final endpoint = url ?? '/v2/api/AssetAuthen';
    final response = await _dio.post(endpoint, data: request.toJson());
    return BaseResponseModel.fromJson(
      response.data as Map<String, dynamic>,
      parseEntries,
    );
  }

  Future<BaseResponseModel<T>> uploadMultipart<T>({
    required Map<String, dynamic> fields,
    required List<MultipartFile> files,
    required T? Function(dynamic json) parseEntries,
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData.fromMap({...fields, 'files': files});
    final response = await _dio.post(
      '/api/upload',
      data: formData,
      onSendProgress: onProgress,
    );
    return BaseResponseModel.fromJson(
      response.data as Map<String, dynamic>,
      parseEntries,
    );
  }
}
