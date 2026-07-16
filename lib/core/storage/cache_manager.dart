import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/models/login_response_model.dart';

class CacheManager {
  static const _tokenKey = 'token';
  static const _loginResponseKey = 'responseLogin';
  static const _mProblemKey = 'MProblem';
  static const _accessTokenKey = 'v3_access_token';
  static const _refreshTokenKey = 'v3_refresh_token';
  static const _deviceAuthKey = 'v3_device_auth';

  // ── V2 legacy ──────────────────────────────────────────────
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> saveLoginResponse(LoginResponseModel model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_loginResponseKey, jsonEncode(model.toJson()));
  }

  static Future<LoginResponseModel?> getLoginResponse() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_loginResponseKey);
    if (raw == null) return null;
    try {
      return LoginResponseModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ── V3 JWT tokens ─────────────────────────────────────────
  static Future<void> saveAccessToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, token);
  }

  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  static Future<void> saveRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refreshTokenKey, token);
  }

  static Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  static Future<void> saveDeviceAuth(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceAuthKey, jsonEncode(data));
  }

  static Future<Map<String, dynamic>?> getDeviceAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_deviceAuthKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
