import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/features/auth/login_screen.dart';
import 'package:horilla_employee/features/auth/splash_screen.dart';

void main() {
  testWidgets('login shows ClockMe branding and sign-in form', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.text('ClockMe'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('splash shows ClockMe while session is loading', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.text('ClockMe'), findsOneWidget);
    expect(find.text('Employee attendance'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
