/// RDC — Armazenamento seguro (JWT, URL do agente, configurações de IA)
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  SecureStorage._();

  static late FlutterSecureStorage _storage;

  static const _keyAccessToken  = 'rdc_access_token';
  static const _keyRefreshToken = 'rdc_refresh_token';
  static const _keyAgentUrl     = 'rdc_agent_url';
  static const _keyAiModel      = 'rdc_ai_model';
  static const _keyAiApiKey     = 'rdc_ai_api_key';

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

  // AI Model
  static Future<String?> getAiModel() => _storage.read(key: _keyAiModel);
  static Future<void> setAiModel(String model) => _storage.write(key: _keyAiModel, value: model);

  // AI API Key
  static Future<String?> getAiApiKey() => _storage.read(key: _keyAiApiKey);
  static Future<void> setAiApiKey(String key) => _storage.write(key: _keyAiApiKey, value: key);

  // Limpar tudo (logout) — preserva URL e configurações de IA
  static Future<void> clearAll() async {
    final url    = await getAgentUrl();
    final model  = await getAiModel();
    final apiKey = await getAiApiKey();
    await _storage.deleteAll();
    if (url    != null) await setAgentUrl(url);
    if (model  != null) await setAiModel(model);
    if (apiKey != null) await setAiApiKey(apiKey);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
