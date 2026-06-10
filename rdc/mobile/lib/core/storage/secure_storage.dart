/// RDC — Armazenamento seguro (JWT, URL do agente)
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  SecureStorage._();

  static late FlutterSecureStorage _storage;

  static const _keyAccessToken = 'rdc_access_token';
  static const _keyRefreshToken = 'rdc_refresh_token';
  static const _keyAgentUrl = 'rdc_agent_url';

  static Future<void> init() async {
    _storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
  }

  // Access Token
  static Future<String?> getAccessToken() => _storage.read(key: _keyAccessToken);
  static Future<void> setAccessToken(String token) => _storage.write(key: _keyAccessToken, value: token);
  static Future<void> clearAccessToken() => _storage.delete(key: _keyAccessToken);

  // Refresh Token
  static Future<String?> getRefreshToken() => _storage.read(key: _keyRefreshToken);
  static Future<void> setRefreshToken(String token) => _storage.write(key: _keyRefreshToken, value: token);
  static Future<void> clearRefreshToken() => _storage.delete(key: _keyRefreshToken);

  // Agent URL
  static Future<String?> getAgentUrl() => _storage.read(key: _keyAgentUrl);
  static Future<void> setAgentUrl(String url) => _storage.write(key: _keyAgentUrl, value: url);

  // Limpar tudo (logout)
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
