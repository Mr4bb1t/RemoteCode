/// RDC — Cliente HTTP com Dio + interceptor de JWT automático
import 'package:dio/dio.dart';
import '../storage/secure_storage.dart';

class ApiClient {
  ApiClient._();

  static final Dio _dio = Dio();
  static Dio get instance => _dio;

  static void init(String baseUrl) {
    _dio.options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
      validateStatus: (status) => status != null && status < 500,
    );

    // Adaptar para certificados auto-assinados
    (_dio.httpClientAdapter as dynamic).onHttpClientCreate = (client) {
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    };

    _dio.interceptors.clear();
    _dio.interceptors.add(_AuthInterceptor());
    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
    ));
  }

  static Future<void> updateBaseUrl(String url) async {
    _dio.options.baseUrl = url;
  }
}

class _AuthInterceptor extends QueuedInterceptorsWrapper {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await SecureStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      // Tentar renovar token
      final refreshToken = await SecureStorage.getRefreshToken();
      if (refreshToken != null) {
        try {
          final res = await ApiClient.instance.post(
            '/auth/refresh',
            data: {'refresh_token': refreshToken},
            options: Options(headers: {}), // sem token para evitar loop
          );
          if (res.statusCode == 200) {
            final newAccess = res.data['access_token'] as String;
            final newRefresh = res.data['refresh_token'] as String;
            await SecureStorage.setAccessToken(newAccess);
            await SecureStorage.setRefreshToken(newRefresh);

            // Repetir request original
            err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
            final retry = await ApiClient.instance.fetch(err.requestOptions);
            return handler.resolve(retry);
          }
        } catch (_) {}
      }
      // Refresh falhou — limpar sessão
      await SecureStorage.clearAll();
    }
    handler.next(err);
  }
}
