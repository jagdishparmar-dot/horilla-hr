import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/features/requests/allocation_edit_screen.dart';
import 'package:horilla_employee/features/requests/models.dart';
import 'package:horilla_employee/features/requests/request_details_sheet.dart';
import 'package:horilla_employee/features/requests/requests_provider.dart';
import 'package:horilla_employee/features/requests/requests_repository.dart';

LeaveRequestItem _allocation({required String status}) {
  return mapAllocationRequest({
    'id': 12,
    'status': status,
    'requested_days': 1.5,
    'description': 'Worked Saturday',
    'requested_date': '2026-11-01',
    'leave_type_id': {'id': 5, 'name': 'Compensatory'},
  });
}

void main() {
  test('a pending allocation can be edited and an approved one cannot', () {
    final pending = _allocation(status: 'requested');
    expect(pending.canEdit, isTrue);
    expect(pending.leaveTypeId, 5);
    expect(pending.title, 'Compensatory');
    expect(pending.requestedDays, 1.5);
    expect(pending.reason, 'Worked Saturday');
    expect(pending.categoryLabel, 'Extra leave');
    expect(pending.source, RequestSource.allocation);
    expect(pending.startDate, DateTime(2026, 11, 1));

    expect(_allocation(status: 'approved').canEdit, isFalse);
    expect(_allocation(status: 'rejected').canEdit, isFalse);
  });

  test('allocation update sends the days, leave type and description', () {
    expect(
      allocationUpdateBody(
        leaveTypeId: 5,
        days: 3,
        description: 'Worked Saturday',
      ),
      {
        'leave_type_id': 5,
        'requested_days': 3,
        'description': 'Worked Saturday',
      },
    );
  });

  testWidgets('editing a pending allocation saves the new day count', (
    tester,
  ) async {
    late Map<String, dynamic> saved;
    final item = _allocation(status: 'requested');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          leaveBalancesProvider.overrideWith((ref) async => const []),
          allocationEditorProvider.overrideWith(
            (ref) =>
                ({
                  required int id,
                  required int leaveTypeId,
                  required num days,
                  required String description,
                }) async {
                  saved = allocationUpdateBody(
                    leaveTypeId: leaveTypeId,
                    days: days,
                    description: description,
                  );
                  saved['id'] = id;
                },
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showRequestDetailsSheet(context, item: item),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Edit'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AllocationEditScreen), findsOneWidget);
    await tester.enterText(find.byKey(const Key('allocation-days')), '3');
    await tester.tap(find.text('Submit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(saved['id'], 12);
    expect(saved['leave_type_id'], 5);
    expect(saved['requested_days'], 3);
    expect(saved['description'], 'Worked Saturday');
  });
}
