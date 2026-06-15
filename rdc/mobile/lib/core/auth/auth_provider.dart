/// RDC — Provider de autenticação (Riverpod)
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../storage/secure_storage.dart';

enum AuthState { unknown, loggedIn, loggedOut }

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final url = await SecureStorage.getAgentUrl();
    final loggedIn = await SecureStorage.isLoggedIn();

    if (url != null && loggedIn) {
      ApiClient.init(url);
      return AuthState.loggedIn;
    }
    return AuthState.loggedOut;
  }

  Future<void> login(String agentUrl, String password) async {
    state = const AsyncLoading();
    try {
      ApiClient.init(agentUrl);
      final res = await ApiClient.instance.post(
        '/auth/login',
        data: {'password': password, 'device_info': 'RDC Mobile'},
      );

      if (res.statusCode == 200) {
        await SecureStorage.setAgentUrl(agentUrl);
        await SecureStorage.setAccessToken(res.data['access_token']);
        await SecureStorage.setRefreshToken(res.data['refresh_token']);
        state = const AsyncData(AuthState.loggedIn);
      } else {
        throw Exception(res.data['detail'] ?? 'Senha incorreta');
      }
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      final refreshToken = await SecureStorage.getRefreshToken();
      if (refreshToken != null) {
        await ApiClient.instance.post(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
        );
      }
    } catch (_) {}
    await SecureStorage.clearAll();
    state = const AsyncData(AuthState.loggedOut);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
