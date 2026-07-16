import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/base_request_model.dart';
import '../models/base_response_model.dart';
import '../storage/cache_manager.dart';

class NetworkManager {
  static final NetworkManager _instance = NetworkManager._();
  static NetworkManager get instance => _instance;

  /// Called when auth fails and token refresh is impossible — clear state and go home.
  static void Function()? onUnauthorized;

  NetworkManager._() {
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    };
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (o) => debugPrint('[NET] $o'),
    ));

    (_dioV3.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    };
    _dioV3.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (o) => debugPrint('[NET-V3] $o'),
    ));
  }

  // ── V2 Dio (envelope) ─────────────────────────────────────
  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  ));

  // ── V3 Dio (REST + Bearer JWT) ────────────────────────────
  final Dio _dioV3 = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  ));

  String? _accessToken;
  bool _refreshing = false;

  Future<void> updateBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('server_url') ?? AppConfig.baseUrl;
    _dio.options.baseUrl = url;
    _dioV3.options.baseUrl = url;
  }

  void setAccessToken(String token) {
    _accessToken = token;
  }

  // ── V2 envelope API (legacy — ไม่แตะ) ─────────────────────
  Future<BaseResponseModel<T>> request<T>({
    required BaseRequestModel request,
    required T? Function(dynamic json) parseEntries,
    String? url,
  }) async {
    final endpoint = url ?? '/v2/api/AssetAuthen';
    final response = await _dio.post(endpoint, data: request.toJson());
    final result = BaseResponseModel.fromJson(
      response.data as Map<String, dynamic>,
      parseEntries,
    );
    return result;
  }

  Future<BaseResponseModel<T>> uploadMultipart<T>({
    required Map<String, dynamic> fields,
    required List<MultipartFile> files,
    required T? Function(dynamic json) parseEntries,
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData.fromMap({...fields, 'files': files});
    final response = await _dio.post(
      '/v2/api/Upload',
      data: formData,
      onSendProgress: onProgress,
    );
    return BaseResponseModel.fromJson(
      response.data as Map<String, dynamic>,
      parseEntries,
    );
  }

  // ── V3 REST API (Bearer JWT) ──────────────────────────────

  /// POST public endpoint (ไม่ต้อง JWT — ใช้สำหรับ auth/refresh)
  Future<Map<String, dynamic>> postV3Public(String path, Map<String, dynamic> body) async {
    final response = await _dioV3.post(path, data: body);
    return response.data as Map<String, dynamic>;
  }

  /// GET ด้วย Bearer JWT (auto-refresh 401)
  Future<Map<String, dynamic>> getV3(String path) async {
    return _requestV3('GET', path, null);
  }

  /// PUT ด้วย Bearer JWT (auto-refresh 401)
  Future<Map<String, dynamic>> putV3(String path, Map<String, dynamic> body) async {
    return _requestV3('PUT', path, body);
  }

  /// POST ด้วย Bearer JWT (auto-refresh 401)
  Future<Map<String, dynamic>> postV3(String path, Map<String, dynamic> body) async {
    return _requestV3('POST', path, body);
  }

  Future<Map<String, dynamic>> _requestV3(String method, String path, Map<String, dynamic>? body) async {
    final token = _accessToken ?? await CacheManager.getAccessToken();
    final options = Options(headers: {'Authorization': 'Bearer $token'});

    try {
      final resp = await _doV3(method, path, body, options);
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // ลอง refresh
        final refreshed = await _tryRefresh();
        if (refreshed) {
          final newToken = _accessToken ?? await CacheManager.getAccessToken();
          final retryOpts = Options(headers: {'Authorization': 'Bearer $newToken'});
          final resp = await _doV3(method, path, body, retryOpts);
          return resp.data as Map<String, dynamic>;
        }
        onUnauthorized?.call();
        throw Exception('unauthorized');
      }
      rethrow;
    }
  }

  Future<Response> _doV3(String method, String path, Map<String, dynamic>? body, Options options) {
    switch (method) {
      case 'GET':
        return _dioV3.get(path, options: options);
      case 'PUT':
        return _dioV3.put(path, data: body, options: options);
      case 'POST':
        return _dioV3.post(path, data: body, options: options);
      default:
        throw UnsupportedError('method $method not supported');
    }
  }

  /// เปิด SSE stream ด้วย Bearer JWT (long-lived connection — 401 จะลอง refresh หนึ่งครั้ง)
  /// receiveTimeout ต้องเป็น Duration.zero (= ไม่จำกัด) เพราะ default 15s จะตัด connection
  /// ที่เงียบระหว่างรอ event — server ส่ง keepalive comment ทุก 30s ซึ่งนานกว่า default
  Future<ResponseBody> openV3Stream(String path) async {
    Future<ResponseBody> connect(String token) async {
      final resp = await _dioV3.get<ResponseBody>(
        path,
        options: Options(
          headers: {'Authorization': 'Bearer $token', 'Accept': 'text/event-stream'},
          responseType: ResponseType.stream,
          receiveTimeout: Duration.zero,
        ),
      );
      return resp.data!;
    }

    final token = _accessToken ?? await CacheManager.getAccessToken();
    try {
      return await connect(token ?? '');
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        final refreshed = await _tryRefresh();
        if (refreshed) {
          final newToken = _accessToken ?? await CacheManager.getAccessToken();
          return connect(newToken ?? '');
        }
        onUnauthorized?.call();
      }
      rethrow;
    }
  }

  /// refresh device token — เรียก POST /v3/api/auth/refresh แล้วอัปเดต cache
  Future<bool> _tryRefresh() async {
    if (_refreshing) return false;
    _refreshing = true;
    try {
      final refreshToken = await CacheManager.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) return false;

      final resp = await _dioV3.post('/v3/api/auth/refresh', data: {'refreshToken': refreshToken});
      final data = resp.data as Map<String, dynamic>;
      final newAccess = data['accessToken'] as String?;
      final newRefresh = data['refreshToken'] as String?;
      if (newAccess == null || newAccess.isEmpty) return false;

      _accessToken = newAccess;
      await CacheManager.saveAccessToken(newAccess);
      if (newRefresh != null) await CacheManager.saveRefreshToken(newRefresh);
      return true;
    } catch (_) {
      return false;
    } finally {
      _refreshing = false;
    }
  }
}
