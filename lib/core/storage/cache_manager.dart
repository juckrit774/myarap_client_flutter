import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/models/login_response_model.dart';

class CacheManager {
  static const _tokenKey = 'token';
  static const _loginResponseKey = 'responseLogin';
  static const _mProblemKey = 'MProblem';

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

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
