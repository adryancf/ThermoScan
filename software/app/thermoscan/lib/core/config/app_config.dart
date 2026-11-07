import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppConfig {
  AppConfig._();

  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _storageKey = 'thermoscan_api_base_url';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _customBaseUrl = '';

  static String get defaultApiBaseUrl {
    if (_envBaseUrl.trim().isNotEmpty) {
      return _envBaseUrl.trim();
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'https://api-thermoscan.realan.space/api/v1';
    }
    return 'https://api-thermoscan.realan.space/api/v1';
  }

  static String get apiBaseUrl =>
      _customBaseUrl.isNotEmpty ? _customBaseUrl : defaultApiBaseUrl;

  static Future<void> init() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      if (saved != null && saved.trim().isNotEmpty) {
        _customBaseUrl = saved.trim();
      }
    } catch (_) {}
  }

  static Future<void> setBaseUrl(String url) async {
    _customBaseUrl = url.trim();
    try {
      if (_customBaseUrl.isEmpty) {
        await _storage.delete(key: _storageKey);
      } else {
        await _storage.write(key: _storageKey, value: _customBaseUrl);
      }
    } catch (_) {}
  }
}
