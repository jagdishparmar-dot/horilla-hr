import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/core/api/api_exception.dart';
import 'package:horilla_employee/core/api/dio_client.dart';
import 'package:horilla_employee/core/auth/session_revocation.dart';
import 'package:horilla_employee/core/server_url_provider.dart';
import 'package:horilla_employee/core/storage/token_storage.dart';
import 'package:horilla_employee/features/auth/auth_provider.dart';
import 'package:horilla_employee/features/auth/auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const jsonHeaders = {
    Headers.contentTypeHeader: ['application/json'],
  };

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  Dio clientFor(_ScriptAdapter adapter) {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    dio.httpClientAdapter = adapter;
    return dio;
  }

  test('parallel 401s share one refresh and store the new refresh', () async {
    final storage = TokenStorage();
    await storage.saveTokens(access: 'access-old', refresh: 'refresh-old');
    final gate = Completer<void>();
    var refreshCalls = 0;
    var unauthorizedHits = 0;

    final adapter = _ScriptAdapter((options) async {
      if (options.path.contains('/auth/refresh')) {
        refreshCalls++;
        await gate.future;
        return ResponseBody.fromString(
          '{"access":"access-new","refresh":"refresh-new"}',
          200,
          headers: jsonHeaders,
        );
      }
      final auth = options.headers['Authorization']?.toString();
      if (auth == 'Bearer access-new') {
        return ResponseBody.fromString('{"ok":true}', 200, headers: jsonHeaders);
      }
      unauthorizedHits++;
      return ResponseBody.fromString(
        '{"detail":"unauthorized"}',
        401,
        headers: jsonHeaders,
      );
    });

    final dio = clientFor(adapter);
    final refreshDio = clientFor(adapter);
    installAuthInterceptor(
      dio: dio,
      storage: storage,
      onSessionRevoked: () {},
      refreshDioFactory: () => refreshDio,
    );

    final first = dio.get<dynamic>('/employee/me');
    final second = dio.get<dynamic>('/home/');
    for (var i = 0; i < 50 && (unauthorizedHits < 2 || refreshCalls < 1); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(unauthorizedHits, 2);
    expect(refreshCalls, 1);
    gate.complete();

    final results = await Future.wait([first, second]);
    expect(refreshCalls, 1);
    expect(results[0].statusCode, 200);
    expect(results[1].statusCode, 200);
    expect(await storage.readAccess(), 'access-new');
    expect(await storage.readRefresh(), 'refresh-new');
  });

  test('refresh body without a refresh token clears the session', () async {
    final storage = TokenStorage();
    await storage.saveTokens(access: 'access-old', refresh: 'refresh-old');
    var revoked = 0;
    final adapter = _ScriptAdapter((options) async {
      if (options.path.contains('/auth/refresh')) {
        return ResponseBody.fromString(
          '{"access":"access-only"}',
          200,
          headers: jsonHeaders,
        );
      }
      return ResponseBody.fromString('{}', 401, headers: jsonHeaders);
    });
    final dio = clientFor(adapter);
    installAuthInterceptor(
      dio: dio,
      storage: storage,
      onSessionRevoked: () => revoked++,
      refreshDioFactory: () => clientFor(adapter),
    );

    await expectLater(
      dio.get<dynamic>('/employee/me'),
      throwsA(isA<DioException>()),
    );
    expect(revoked, 1);
    expect(await storage.readAccess(), isNull);
    expect(await storage.readRefresh(), isNull);
  });

  test('rejected refresh clears storage and a timeout does not', () async {
    final storage = TokenStorage();
    await storage.saveTokens(access: 'access-old', refresh: 'refresh-old');
    var revoked = 0;

    Future<void> run(ResponseBody Function() refreshBody) async {
      final adapter = _ScriptAdapter((options) async {
        if (options.path.contains('/auth/refresh')) return refreshBody();
        return ResponseBody.fromString('{}', 401, headers: jsonHeaders);
      });
      final dio = clientFor(adapter);
      installAuthInterceptor(
        dio: dio,
        storage: storage,
        onSessionRevoked: () => revoked++,
        refreshDioFactory: () => clientFor(adapter),
      );
      await expectLater(
        dio.get<dynamic>('/employee/me'),
        throwsA(isA<DioException>()),
      );
    }

    await run(
      () => ResponseBody.fromString(
        '{"detail":"token not valid"}',
        401,
        headers: jsonHeaders,
      ),
    );
    expect(revoked, 1);
    expect(await storage.readRefresh(), isNull);

    FlutterSecureStorage.setMockInitialValues({});
    final kept = TokenStorage();
    await kept.saveTokens(access: 'access-old', refresh: 'refresh-old');
    revoked = 0;
    final timeoutAdapter = _ScriptAdapter((options) async {
      if (options.path.contains('/auth/refresh')) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      }
      return ResponseBody.fromString('{}', 401, headers: jsonHeaders);
    });
    final dio = clientFor(timeoutAdapter);
    installAuthInterceptor(
      dio: dio,
      storage: kept,
      onSessionRevoked: () => revoked++,
      refreshDioFactory: () => clientFor(timeoutAdapter),
    );
    await expectLater(
      dio.get<dynamic>('/employee/me'),
      throwsA(isA<DioException>()),
    );
    expect(revoked, 0);
    expect(await kept.readAccess(), 'access-old');
    expect(await kept.readRefresh(), 'refresh-old');
  });

  test('429 on refresh keeps the stored tokens', () async {
    final storage = TokenStorage();
    await storage.saveTokens(access: 'access-old', refresh: 'refresh-old');
    var revoked = 0;
    final adapter = _ScriptAdapter((options) async {
      if (options.path.contains('/auth/refresh')) {
        return ResponseBody.fromString(
          '{"detail":"throttled"}',
          429,
          headers: jsonHeaders,
        );
      }
      return ResponseBody.fromString('{}', 401, headers: jsonHeaders);
    });
    final dio = clientFor(adapter);
    installAuthInterceptor(
      dio: dio,
      storage: storage,
      onSessionRevoked: () => revoked++,
      refreshDioFactory: () => clientFor(adapter),
    );

    await expectLater(
      dio.get<dynamic>('/employee/me'),
      throwsA(isA<DioException>()),
    );
    expect(revoked, 0);
    expect(await storage.readAccess(), 'access-old');
    expect(await storage.readRefresh(), 'refresh-old');
  });

  test('revocation moves auth state to unauthenticated', () async {
    FlutterSecureStorage.setMockInitialValues({
      'horilla_access': 'access-old',
      'horilla_refresh': 'refresh-old',
      TokenStorage.serverUrlKey: 'https://example.test/api/v1',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      if (container.read(serverUrlProvider).isReady) break;
    }

    AuthStatus status = AuthStatus.unknown;
    for (var i = 0; i < 20 && status == AuthStatus.unknown; i++) {
      await Future<void>.delayed(Duration.zero);
      status = container.read(authProvider).status;
    }
    expect(status, AuthStatus.authenticated);

    container.read(sessionRevocationProvider).notify();
    expect(container.read(authProvider).status, AuthStatus.unauthenticated);
  });

  test('logout blacklists the current refresh and still clears on failure', () async {
    final storage = TokenStorage();
    await storage.saveTokens(access: 'access-old', refresh: 'refresh-current');
    var refreshCalls = 0;
    String? posted;
    String? authorization;
    final adapter = _ScriptAdapter((options) async {
      if (options.path.contains('/auth/refresh')) {
        refreshCalls++;
      }
      if (options.path.contains('/auth/logout')) {
        authorization = options.headers['Authorization']?.toString();
        final data = options.data;
        if (data is Map) posted = data['refresh']?.toString();
        return ResponseBody.fromString(
          '{"detail":"unauthorized"}',
          401,
          headers: jsonHeaders,
        );
      }
      return ResponseBody.fromString('{}', 500, headers: jsonHeaders);
    });
    final repo = AuthRepository(
      dio: clientFor(adapter),
      storage: storage,
      logoutDio: clientFor(adapter),
    );
    await repo.logout();
    expect(posted, 'refresh-current');
    expect(authorization, isNull);
    expect(refreshCalls, 0);
    expect(await storage.readAccess(), isNull);
    expect(await storage.readRefresh(), isNull);
  });

  test('hasSession is false unless both tokens are stored', () async {
    final storage = TokenStorage();
    final repo = AuthRepository(dio: Dio(), storage: storage);
    await storage.saveTokens(access: 'access-old', refresh: '');
    expect(await repo.hasSession(), isFalse);
    await storage.saveTokens(access: '', refresh: 'refresh-old');
    expect(await repo.hasSession(), isFalse);
    await storage.saveTokens(access: 'access-old', refresh: 'refresh-old');
    expect(await repo.hasSession(), isTrue);
  });

  test('login does not save a session when refresh is missing', () async {
    final storage = TokenStorage();
    final adapter = _ScriptAdapter((options) async {
      return ResponseBody.fromString(
        '{"access":"access-only","employee":{"id":1,"full_name":"A"}}',
        200,
        headers: jsonHeaders,
      );
    });
    final repo = AuthRepository(dio: clientFor(adapter), storage: storage);
    await expectLater(
      repo.login(username: 'user', password: 'secret'),
      throwsA(isA<ApiException>()),
    );
    expect(await storage.readAccess(), isNull);
    expect(await storage.readRefresh(), isNull);
  });

  test('API errors stay short and keep a plain server message', () {
    final login = DioException(
      requestOptions: RequestOptions(path: '/auth/login/'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/auth/login/'),
        statusCode: 401,
        data: {'detail': 'No active account found with the given credentials'},
      ),
    );
    expect(
      messageFromDio(login),
      'No active account found with the given credentials',
    );

    final timeout = DioException(
      requestOptions: RequestOptions(path: '/mobile/home/'),
      type: DioExceptionType.connectionTimeout,
    );
    expect(
      messageFromDio(timeout),
      'Cannot reach the server. Check your connection and try again.',
    );
    expect(messageFromDio(timeout).contains('API_BASE_URL'), isFalse);
    expect(messageFromDio(timeout).contains('runserver'), isFalse);

    final locked = DioException(
      requestOptions: RequestOptions(path: '/auth/login/'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/auth/login/'),
        statusCode: 403,
        data: {'detail': 'Account locked. Try again in 10 minutes.'},
      ),
    );
    expect(messageFromDio(locked), 'Account locked. Try again in 10 minutes.');

    final throttled = DioException(
      requestOptions: RequestOptions(path: '/mobile/home/'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/mobile/home/'),
        statusCode: 429,
        data: <String, dynamic>{},
      ),
    );
    expect(
      messageFromDio(throttled),
      'Too many attempts. Wait a moment and try again.',
    );
    expect(
      userFacingError(
        Exception('DioException [connection error]: API_BASE_URL'),
      ),
      'Cannot reach the server. Check your connection and try again.',
    );
  });
}

class _ScriptAdapter implements HttpClientAdapter {
  _ScriptAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
