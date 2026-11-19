import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/features/attendance/attendance_provider.dart';
import 'package:horilla_employee/features/attendance/attendance_screen.dart';
import 'package:horilla_employee/features/attendance/models.dart';
import 'package:horilla_employee/features/home/home_provider.dart';
import 'package:horilla_employee/features/home/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('summary and shift swipe, and the controls are easy to tap', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileHomeProvider.overrideWith((ref) async => _home()),
          attendanceWeekDaysProvider.overrideWith(
            (ref) => const AsyncData(<AttendanceDay>[]),
          ),
          attendanceShiftDaysProvider.overrideWith(
            (ref) => const AsyncData(<AttendanceDay>[]),
          ),
        ],
        child: const MaterialApp(home: AttendanceScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester.getSize(find.byKey(const Key('attendance-summary-tab'))).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.byTooltip('Previous period')).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.byKey(const Key('attendance-view-switch'))).shortestSide,
      greaterThanOrEqualTo(44),
    );

    expect(find.text('Total worked'), findsOneWidget);
    final before = _visibleRange(tester);

    await tester.tap(find.byTooltip('Next period'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_visibleRange(tester), isNot(before));

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Total worked'), findsNothing);

    await tester.tap(find.byKey(const Key('attendance-summary-tab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Total worked'), findsOneWidget);
  });
}

String _visibleRange(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? '')
      .firstWhere((value) => value.contains('–'));
}

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
  );
}
