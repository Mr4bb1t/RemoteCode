/// RDC — Armazenamento seguro (JWT, URL do agente, configurações de IA)
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedModel {
  final String id;
  final String name;
  final String provider;
  final String logoAsset;
  final String colorHex;
  final String keyUrl;
  final String keyHint;
  final String category;
  final String apiKey;

  SavedModel({
    required this.id,
    required this.name,
    required this.provider,
    required this.logoAsset,
    required this.colorHex,
    required this.keyUrl,
    required this.keyHint,
    required this.category,
    required this.apiKey,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'provider': provider, 'logoAsset': logoAsset,
    'colorHex': colorHex, 'keyUrl': keyUrl, 'keyHint': keyHint,
    'category': category, 'apiKey': apiKey,
  };

  factory SavedModel.fromJson(Map<String, dynamic> j) => SavedModel(
    id: j['id'] ?? '', name: j['name'] ?? '', provider: j['provider'] ?? '',
    logoAsset: j['logoAsset'] ?? '🤖', colorHex: j['colorHex'] ?? '#10A37F',
    keyUrl: j['keyUrl'] ?? '', keyHint: j['keyHint'] ?? '',
    category: j['category'] ?? 'api', apiKey: j['apiKey'] ?? '',
  );
}

class SecureStorage {
  SecureStorage._();

  static late FlutterSecureStorage _storage;

  static const _keyAccessToken  = 'rdc_access_token';
  static const _keyRefreshToken = 'rdc_refresh_token';
  static const _keyAgentUrl     = 'rdc_agent_url';
  static const _keyAiModel      = 'rdc_ai_model';
  static const _keyAiApiKey     = 'rdc_ai_api_key';
  static const _keySavedModels  = 'rdc_saved_models';

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

  // Saved Models (modelos com API key configurada)
  static Future<List<SavedModel>> getSavedModels() async {
    final raw = await _storage.read(key: _keySavedModels);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => SavedModel.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveModelConfig(SavedModel model) async {
    final list = await getSavedModels();
    list.removeWhere((m) => m.id == model.id);
    list.add(model);
    await _storage.write(key: _keySavedModels, value: jsonEncode(list.map((m) => m.toJson()).toList()));
  }

  static Future<void> removeSavedModel(String modelId) async {
    final list = await getSavedModels();
    list.removeWhere((m) => m.id == modelId);
    await _storage.write(key: _keySavedModels, value: jsonEncode(list.map((m) => m.toJson()).toList()));
  }

  static Future<SavedModel?> getSavedModel(String modelId) async {
    final list = await getSavedModels();
    try {
      return list.firstWhere((m) => m.id == modelId);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> hasSavedModel(String modelId) async {
    final m = await getSavedModel(modelId);
    return m != null && m.apiKey.isNotEmpty;
  }

  // Limpar tudo (logout) — preserva URL e configurações de IA
  static Future<void> clearAll() async {
    final url    = await getAgentUrl();
    final model  = await getAiModel();
    final apiKey = await getAiApiKey();
    final saved  = await _storage.read(key: _keySavedModels);
    await _storage.deleteAll();
    if (url    != null) await setAgentUrl(url);
    if (model  != null) await setAiModel(model);
    if (apiKey != null) await setAiApiKey(apiKey);
    if (saved  != null) await _storage.write(key: _keySavedModels, value: saved);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
