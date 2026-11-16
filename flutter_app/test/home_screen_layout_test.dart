import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/features/home/home_provider.dart';
import 'package:horilla_employee/features/home/home_screen.dart';
import 'package:horilla_employee/features/home/models.dart';

MobileHome _home() {
  return MobileHome(
    employeeId: 1,
    employeeName: 'Ava Stone',
    avatarUrl: null,
    isClockedIn: false,
    clockInTime: null,
    worked: '00:00:00',
    breakTime: '00:00:00',
    overtime: '00:00:00',
    geofenceEnabled: false,
    jobPosition: 'Designer',
    department: 'Product',
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required Override override,
  double statusBar = 48,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.padding = FakeViewPadding(top: statusBar);
  tester.view.viewPadding = FakeViewPadding(top: statusBar);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [override],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('header stays below the status bar while pulling to refresh', (
    tester,
  ) async {
    var loads = 0;
    await _pumpHome(
      tester,
      override: mobileHomeProvider.overrideWith((ref) async {
        loads++;
        return _home();
      }),
    );

    final name = find.text('Ava');
    expect(name, findsOneWidget);
    final before = tester.getTopLeft(name).dy;
    expect(before, greaterThanOrEqualTo(48));

    final gesture = await tester.startGesture(const Offset(180, 520));
    await gesture.moveBy(const Offset(0, 220));
    await tester.pump();

    expect(tester.getTopLeft(name).dy, closeTo(before, 0.5));
    expect(tester.getTopLeft(name).dy, greaterThanOrEqualTo(48));

    await gesture.moveBy(const Offset(0, -220));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Check-in'), findsWidgets);
    expect(find.text('Work Schedule'), findsOneWidget);
    expect(loads, 1);
  });

  testWidgets('pull to refresh reloads home data', (tester) async {
    var loads = 0;
    await _pumpHome(
      tester,
      override: mobileHomeProvider.overrideWith((ref) async {
        loads++;
        return _home();
      }),
    );

    await tester.fling(
      find.byType(SingleChildScrollView),
      const Offset(0, 300),
      1200,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(loads, greaterThan(1));
    expect(tester.getTopLeft(find.text('Ava')).dy, greaterThanOrEqualTo(48));
  });

  testWidgets('loading indicator stays below the status bar', (tester) async {
    final gate = Completer<MobileHome>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete(_home());
    });

    await _pumpHome(
      tester,
      override: mobileHomeProvider.overrideWith((ref) => gate.future),
    );

    final spinner = find.byType(CircularProgressIndicator);
    expect(spinner, findsOneWidget);
    expect(tester.getTopLeft(spinner).dy, greaterThanOrEqualTo(48));
  });

  testWidgets('error state keeps retry below the status bar', (tester) async {
    await _pumpHome(
      tester,
      override: mobileHomeProvider.overrideWith((ref) async {
        throw Exception('Cannot reach the server');
      }),
    );

    expect(find.text('Cannot reach the server'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Retry')).dy, greaterThanOrEqualTo(48));

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Retry'), findsOneWidget);
  });
}
