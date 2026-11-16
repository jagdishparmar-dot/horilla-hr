import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/app.dart';
import 'package:horilla_employee/core/api/dio_client.dart';
import 'package:horilla_employee/core/config.dart';
import 'package:horilla_employee/core/server_url_probe.dart';
import 'package:horilla_employee/core/server_url_provider.dart';
import 'package:horilla_employee/core/storage/token_storage.dart';
import 'package:horilla_employee/features/auth/login_screen.dart';
import 'package:horilla_employee/features/auth/server_url_screen.dart';
import 'package:horilla_employee/features/auth/splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppConfig.clear();
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(AppConfig.clear);

  group('ServerUrl.normalize', () {
    test('trims whitespace and trailing slashes', () {
      expect(
        ServerUrl.normalize('  https://Hr.Example.com/  '),
        'https://hr.example.com/api/v1',
      );
    });

    test('adds https when the scheme is missing', () {
      expect(
        ServerUrl.normalize('hr.example.com'),
        'https://hr.example.com/api/v1',
      );
    });

    test('keeps http and port for a LAN host', () {
      expect(
        ServerUrl.normalize('http://10.0.0.5:8000'),
        'http://10.0.0.5:8000/api/v1',
      );
    });

    test('does not duplicate /api/v1', () {
      expect(
        ServerUrl.normalize('https://hr.example.com/api/v1/'),
        'https://hr.example.com/api/v1',
      );
    });

    test('preserves a reverse-proxy prefix', () {
      expect(
        ServerUrl.normalize('https://hr.example.com/horilla'),
        'https://hr.example.com/horilla/api/v1',
      );
    });

    test('rejects an empty value', () {
      expect(
        () => ServerUrl.normalize('   '),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Enter your server address.',
          ),
        ),
      );
    });

    test('rejects a non-http scheme', () {
      expect(
        () => ServerUrl.normalize('ftp://hr.example.com'),
        throwsA(isA<FormatException>()),
      );
    });

    test('mediaOrigin strips /api/v1', () {
      expect(
        ServerUrl.mediaOrigin('https://hr.example.com/api/v1'),
        'https://hr.example.com',
      );
    });

    test('display hides /api/v1 for the settings field', () {
      expect(
        ServerUrl.display('https://hr.example.com/api/v1'),
        'https://hr.example.com',
      );
      expect(
        ServerUrl.display('https://hr.example.com/horilla/api/v1'),
        'https://hr.example.com/horilla',
      );
    });
  });

  group('persistence', () {
    test('saves a normalized URL and reloads it', () async {
      final storage = TokenStorage();
      final first = ServerUrlNotifier(storage);
      await first.ready;
      expect(first.state.isReady, isFalse);

      expect(await first.save(' https://hr.example.com/ '), isTrue);
      expect(first.state.apiBaseUrl, 'https://hr.example.com/api/v1');
      expect(AppConfig.apiBaseUrl, 'https://hr.example.com/api/v1');

      final stored = await storage.readServerUrl();
      expect(stored, 'https://hr.example.com/api/v1');

      final second = ServerUrlNotifier(storage);
      await second.ready;
      expect(second.state.isReady, isTrue);
      expect(second.state.apiBaseUrl, 'https://hr.example.com/api/v1');
    });

    test('does not persist an invalid URL', () async {
      final storage = TokenStorage();
      final notifier = ServerUrlNotifier(storage);
      await notifier.ready;
      expect(await notifier.save('ftp://nope'), isFalse);
      expect(notifier.state.isReady, isFalse);
      expect(await storage.readServerUrl(), isNull);
    });

    test('surfaces a storage read error', () async {
      final notifier = ServerUrlNotifier(_BoomStorage(failRead: true));
      await notifier.ready;
      expect(notifier.state.loaded, isTrue);
      expect(notifier.state.storageError, isTrue);
      expect(notifier.state.isReady, isFalse);
      expect(notifier.state.error, contains('Could not read'));
    });

    test('surfaces a storage write error', () async {
      final notifier = ServerUrlNotifier(_BoomStorage(failWrite: true));
      await notifier.ready;
      expect(await notifier.save('https://hr.example.com'), isFalse);
      expect(notifier.state.storageError, isTrue);
      expect(notifier.state.error, contains('Could not save'));
      expect(AppConfig.isConfigured, isFalse);
    });

    test('changing the URL clears stored tokens', () async {
      final storage = TokenStorage();
      await storage.saveTokens(access: 'a', refresh: 'r');
      await storage.writeServerUrl('https://old.example.com/api/v1');

      final notifier = ServerUrlNotifier(storage, probe: _okProbe);
      await notifier.ready;
      expect(await notifier.save('https://new.example.com'), isTrue);
      expect(await storage.readAccess(), isNull);
      expect(await storage.readRefresh(), isNull);
      expect(await storage.readServerUrl(), 'https://new.example.com/api/v1');
    });

    test('save probes the host before persisting', () async {
      var probed = '';
      final storage = TokenStorage();
      final notifier = ServerUrlNotifier(
        storage,
        probe: (url) async => probed = url,
      );
      await notifier.ready;
      expect(await notifier.save('https://hr.example.com'), isTrue);
      expect(probed, 'https://hr.example.com/api/v1');
      expect(await storage.readServerUrl(), 'https://hr.example.com/api/v1');
    });

    test('does not persist when the host cannot be reached', () async {
      final storage = TokenStorage();
      final notifier = ServerUrlNotifier(
        storage,
        probe: (_) async {
          throw const FormatException(
            'Cannot reach that server. Check the address and try again.',
          );
        },
      );
      await notifier.ready;
      expect(await notifier.save('https://nope.example.com'), isFalse);
      expect(await storage.readServerUrl(), isNull);
      expect(notifier.state.isReady, isFalse);
      expect(notifier.state.error, contains('Cannot reach'));
    });
  });

  group('probeClockMeServer', () {
    test('accepts a ClockMe /health/ body', () async {
      final dio = _stubDio(
        statusCode: 200,
        data: const {'status': 'ok', 'product': 'clockme', 'api': 1},
      );
      await probeClockMeServer('https://hr.example.com/api/v1', dio: dio);
    });

    test('rejects a host that is not ClockMe', () async {
      final dio = _stubDio(statusCode: 200, data: '<html>ok</html>');
      expect(
        () => probeClockMeServer('https://example.com/api/v1', dio: dio),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'That address is not a ClockMe server.',
          ),
        ),
      );
    });

    test('rejects an unreachable host', () async {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://hr.example.com',
          validateStatus: (_) => true,
        ),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
          },
        ),
      );
      expect(
        () => probeClockMeServer('https://hr.example.com/api/v1', dio: dio),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Cannot reach'),
          ),
        ),
      );
    });
  });

  group('API client', () {
    test('dio uses the saved URL', () {
      final container = ProviderContainer(
        overrides: [
          serverUrlProvider.overrideWith(
            (ref) => _ReadyNotifier('https://hr.example.com/api/v1'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final dio = container.read(dioProvider);
      expect(dio.options.baseUrl, 'https://hr.example.com/api/v1');
    });

    test('changing the URL rebuilds Dio', () async {
      final storage = TokenStorage();
      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          serverUrlProbeProvider.overrideWithValue(_okProbe),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(serverUrlProvider.notifier);
      await notifier.ready;
      expect(await notifier.save('https://one.example.com'), isTrue);
      final first = container.read(dioProvider);
      expect(first.options.baseUrl, 'https://one.example.com/api/v1');

      expect(await notifier.save('https://two.example.com'), isTrue);
      final second = container.read(dioProvider);
      expect(second.options.baseUrl, 'https://two.example.com/api/v1');
      expect(identical(first, second), isFalse);
    });

    test('dio is not created before a URL is saved', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(() => container.read(dioProvider), throwsStateError);
    });
  });

  group('startup UI', () {
    testWidgets('asks for a server URL when none is stored', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(ServerUrlScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('Your server'), findsOneWidget);
    });

    testWidgets('shows splash until storage has loaded', (tester) async {
      final notifier = _HangingNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [serverUrlProvider.overrideWith((ref) => notifier)],
          child: const HorillaApp(),
        ),
      );
      await tester.pump();
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(ServerUrlScreen), findsNothing);
    });

    testWidgets('skips setup when a valid URL is stored', (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        TokenStorage.serverUrlKey: 'https://hr.example.com/api/v1',
      });
      await tester.pumpWidget(_app());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(ServerUrlScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('saving a URL on the setup screen reaches login', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(
        find.byKey(const Key('server-url-field')),
        'https://hr.example.com',
      );
      await tester.tap(find.byKey(const Key('server-url-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(AppConfig.apiBaseUrl, 'https://hr.example.com/api/v1');
    });

    testWidgets('keeps setup visible when save validation fails', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(
        find.byKey(const Key('server-url-field')),
        'ftp://x',
      );
      await tester.tap(find.byKey(const Key('server-url-save')));
      await tester.pump();

      expect(find.byType(ServerUrlScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('keeps setup visible when the host cannot be reached', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          probe: (_) async {
            throw const FormatException(
              'Cannot reach that server. Check the address and try again.',
            );
          },
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(
        find.byKey(const Key('server-url-field')),
        'https://hr.example.com',
      );
      await tester.tap(find.byKey(const Key('server-url-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(ServerUrlScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.textContaining('Cannot reach'), findsOneWidget);
    });

    testWidgets('editing screen hides /api/v1', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverUrlProvider.overrideWith(
              (ref) => _ReadyNotifier('https://hr.example.com/api/v1'),
            ),
          ],
          child: const MaterialApp(home: ServerUrlScreen(editing: true)),
        ),
      );
      await tester.pump();

      expect(find.text('https://hr.example.com'), findsOneWidget);
      expect(find.textContaining('/api/v1'), findsNothing);
    });
  });
}

Future<void> _okProbe(String _) async {}

Widget _app({Future<void> Function(String apiBaseUrl)? probe}) {
  return ProviderScope(
    overrides: [serverUrlProbeProvider.overrideWithValue(probe ?? _okProbe)],
    child: const HorillaApp(),
  );
}

Dio _stubDio({required int statusCode, required Object data}) {
  final dio = Dio(
    BaseOptions(baseUrl: 'https://hr.example.com', validateStatus: (_) => true),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: statusCode,
            data: data,
          ),
        );
      },
    ),
  );
  return dio;
}

class _BoomStorage extends TokenStorage {
  _BoomStorage({this.failRead = false, this.failWrite = false});

  final bool failRead;
  final bool failWrite;

  @override
  Future<String?> readServerUrl() async {
    if (failRead) throw StateError('read failed');
    return super.readServerUrl();
  }

  @override
  Future<void> writeServerUrl(String url) async {
    if (failWrite) throw StateError('write failed');
    await super.writeServerUrl(url);
  }
}

class _ReadyNotifier extends ServerUrlNotifier {
  _ReadyNotifier(String url) : super(TokenStorage(), autoload: false) {
    AppConfig.apply(url);
    state = ServerUrlState(loaded: true, apiBaseUrl: url);
  }
}

class _HangingNotifier extends ServerUrlNotifier {
  _HangingNotifier() : super(TokenStorage(), autoload: false);
}
