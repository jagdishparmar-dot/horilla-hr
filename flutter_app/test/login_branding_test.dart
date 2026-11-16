import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/core/config.dart';
import 'package:horilla_employee/core/server_url_provider.dart';
import 'package:horilla_employee/core/storage/token_storage.dart';
import 'package:horilla_employee/features/auth/login_screen.dart';
import 'package:horilla_employee/features/auth/splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppConfig.clear();
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('login shows ClockMe branding and sign-in form', (tester) async {
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

    expect(find.text('Sign in to ClockMe'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('USERNAME'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('splash shows ClockMe while session is loading', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.text('ClockMe'), findsOneWidget);
    expect(find.text('Employee attendance'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
