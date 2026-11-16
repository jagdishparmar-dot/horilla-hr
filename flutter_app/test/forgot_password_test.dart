import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/core/api/api_exception.dart';
import 'package:horilla_employee/core/api/dio_client.dart';
import 'package:horilla_employee/core/config.dart';
import 'package:horilla_employee/core/server_url_provider.dart';
import 'package:horilla_employee/core/storage/token_storage.dart';
import 'package:horilla_employee/features/auth/auth_repository.dart';
import 'package:horilla_employee/features/auth/forgot_password_screen.dart';
import 'package:horilla_employee/features/auth/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppConfig.clear();
    AppConfig.apply('https://example.test/api/v1');
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(AppConfig.clear);

  test(
    'requestPasswordReset posts the identifier and returns the message',
    () async {
      late RequestOptions captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
      dio.httpClientAdapter = _ScriptAdapter((options) async {
        captured = options;
        return ResponseBody.fromString(
          '{"message":"Password reset link sent to f***@test.horilla"}',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });

      final repo = AuthRepository(
        dio: Dio(),
        storage: TokenStorage(),
        logoutDio: dio,
      );
      final message = await repo.requestPasswordReset('forgot_me');
      expect(message, contains('f***@test.horilla'));
      expect(captured.path, '/auth/forgot-password/');
      expect(captured.data, {'email': 'forgot_me'});
    },
  );

  test('requestPasswordReset surfaces a missing-account error', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
    dio.httpClientAdapter = _ScriptAdapter((options) async {
      return ResponseBody.fromString(
        '{"error":"No account found with this username or email. Check it and try again."}',
        400,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    });
    final repo = AuthRepository(
      dio: Dio(),
      storage: TokenStorage(),
      logoutDio: dio,
    );
    expect(
      () => repo.requestPasswordReset('nobody'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('No account found'),
        ),
      ),
    );
  });

  testWidgets('login opens the forgot-password screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverUrlProvider.overrideWith((ref) {
            const url = 'https://example.test/api/v1';
            AppConfig.apply(url);
            final notifier = ServerUrlNotifier(
              ref.watch(tokenStorageProvider),
              autoload: false,
            );
            notifier.state = const ServerUrlState(
              loaded: true,
              apiBaseUrl: url,
            );
            return notifier;
          }),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, 'forgot_me');
    await tester.tap(find.byKey(const Key('forgot-password')));
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text('forgot_me'), findsOneWidget);
  });

  testWidgets('forgot password shows the mailed-link message', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        ],
        child: const MaterialApp(
          home: ForgotPasswordScreen(initialIdentifier: 'forgot_me'),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('forgot-password-send')));
    await tester.pumpAndSettle();

    expect(
      find.text('Password reset link sent to f***@test.horilla'),
      findsOneWidget,
    );
    expect(find.text('Link sent'), findsOneWidget);
  });
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(dio: Dio(), storage: TokenStorage());

  @override
  Future<String> requestPasswordReset(String identifier) async {
    return 'Password reset link sent to f***@test.horilla';
  }
}

class _ScriptAdapter implements HttpClientAdapter {
  _ScriptAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }
}
