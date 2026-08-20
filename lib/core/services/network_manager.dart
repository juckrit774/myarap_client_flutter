import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../config/managed_config.dart';
import '../models/base_request_model.dart';
import '../models/base_response_model.dart';
import '../storage/cache_manager.dart';

class NetworkManager {
  static final NetworkManager _instance = NetworkManager._();
  static NetworkManager get instance => _instance;

  /// Called when auth fails and token refresh is impossible — clear state and go home.
  static void Function()? onUnauthorized;

  NetworkManager._() {
    _dio.interceptors.add(_traceInterceptor('NET'));
    _dioV3.interceptors.add(_traceInterceptor('NET-V3'));
  }

  // ── การตรวจใบรับรอง TLS ──────────────────────────────────────────────────
  //
  // 🔴 **ห้ามใส่ `badCertificateCallback` กลับมาอีก** (ลบออก 2026-08-20)
  //
  // ของเดิมเป็น `(cert, host, port) => true` ทั้ง dio V2 และ V3 = **ยอมรับใบรับรองทุกใบ**
  // ใครที่อยู่กลางทาง (Wi-Fi องค์กร · ARP spoof · DNS ปลอม) อ่านและแก้ทุกอย่างที่ agent
  // รับส่งได้ · จุดที่ทำให้ร้ายแรงกว่าปกติคือ **ช่อง SSE เป็นช่องสั่งงาน** — ผู้ที่แทรกกลางทางได้
  // ยิง event `deploy` ของตัวเองเข้ามาได้ = **สั่งรันโปรแกรมอะไรก็ได้บนทุกเครื่องที่ลง agent**
  // และ **การตรวจ checksum กันไม่ได้เลย เพราะ checksum มากับ event เดียวกัน**
  // (ดู `docs/05-testing/agent-security-assessment.md` AG-SEC-06 / BUG-118 ของ MYARAP-NEW)
  //
  // ⚠️ **ถ้าใช้ CA ภายในองค์กร**: Dart ไม่ได้อ่าน trust store ของ OS เสมอไป — ต้องแจก root CA
  // แล้วให้ระบบเชื่อถือจริง ๆ ถ้าเชื่อมไม่ได้จะเห็น `HandshakeException` ใน trace ด้านล่าง
  // ซึ่งเป็นข้อความที่ตั้งใจให้แยกออกจาก "เน็ตไม่ถึง" ได้ทันที
  //
  // ⚠️ deployment ปัจจุบันวิ่ง **HTTP** (`http://<ip>:8088`) ซึ่งไม่แตะ TLS เลย
  // การลบนี้จึงไม่กระทบของที่ใช้อยู่ — แต่บังคับให้ตอนขึ้น HTTPS ต้องมี cert ที่ถูกต้องจริง

  // ── Trace log ────────────────────────────────────────────────────────────
  //
  // 🔴 **ห้าม log body หรือ header** (เปลี่ยนจาก LogInterceptor 2026-08-20)
  //
  // ของเดิมเป็น `LogInterceptor(requestBody: true, responseBody: true)` และ `debugPrint`
  // **ไม่ได้ถูกตัดออกใน release build** → access token · refresh token · เนื้อหา ticket ทั้งหมด
  // ไหลไปที่ log ของเครื่องผู้ใช้ · ใครอ่าน log เครื่องนั้นได้ = ได้ token ไปใช้ต่อทันที
  // (AG-SEC-07 / BUG-119)
  //
  // ที่เหลือไว้คือ method + path + status + เวลา ซึ่งพอสำหรับตอบคำถามภาคสนามว่า
  // "ยิงไปถึงไหม / ตอบอะไรกลับมา / ช้าที่ตรงไหน" โดยไม่มีอะไรที่เป็นความลับเลย
  Interceptor _traceInterceptor(String tag) {
    return InterceptorsWrapper(
      onRequest: (options, handler) {
        options.extra['_t0'] = DateTime.now().millisecondsSinceEpoch;
        handler.next(options);
      },
      onResponse: (r, handler) {
        debugPrint('[$tag] ${r.requestOptions.method} ${r.requestOptions.path}'
            ' → ${r.statusCode} ${_took(r.requestOptions)}');
        handler.next(r);
      },
      onError: (e, handler) {
        // แยก "ใบรับรองไม่ผ่าน" ออกจาก "เน็ตไม่ถึง" ให้ชัด — สองอย่างนี้อาการเหมือนกัน
        // ตรงที่ request ไม่สำเร็จ แต่คนละสาเหตุและคนละวิธีแก้โดยสิ้นเชิง
        final cert = e.error is HandshakeException || e.error is CertificateException;
        debugPrint('[$tag] ${e.requestOptions.method} ${e.requestOptions.path}'
            ' → ${e.response?.statusCode ?? (cert ? 'TLS ปฏิเสธใบรับรองของเซิร์ฟเวอร์' : e.type.name)}'
            ' ${_took(e.requestOptions)}');
        handler.next(e);
      },
    );
  }

  String _took(RequestOptions o) {
    final t0 = o.extra['_t0'];
    if (t0 is! int) return '';
    return '(${DateTime.now().millisecondsSinceEpoch - t0}ms)';
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
    // ค่าที่ผู้ดูแลตั้งไว้ระดับเครื่อง **ชนะเสมอ** — ผู้ใช้ทั่วไปแก้ไม่ได้ (AG-SEC-08)
    final managed = await ManagedConfig.serverUrl();
    final url = managed ?? prefs.getString('server_url') ?? AppConfig.baseUrl;
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
