import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/features/more/claims_screen.dart';
import 'package:horilla_employee/features/more/more_models.dart';
import 'package:horilla_employee/features/more/more_providers.dart';

void main() {
  test('an expense claim parses amount, status and the receipt', () {
    final claim = ExpenseClaim.fromJson({
      'id': 4,
      'employee_id': 2,
      'title': 'Client dinner',
      'type': 'reimbursement',
      'status': 'requested',
      'amount': 1250.5,
      'allowance_on': '2026-11-02',
      'description': 'Dinner with the client team.',
      'attachment': '/media/receipts/dinner.pdf',
      'other_attachements': ['/media/receipts/bill.jpg'],
    });

    expect(claim.employeeId, 2);
    expect(claim.title, 'Client dinner');
    expect(claim.typeLabel, 'Expense');
    expect(claim.statusLabel, 'Pending');
    expect(claim.isPending, isTrue);
    expect(claim.amountLabel, '1,250.50');
    expect(claim.dateLabel, '2 Nov 2026');
    expect(claim.description, 'Dinner with the client team.');
    expect(claim.files, [
      '/media/receipts/dinner.pdf',
      '/media/receipts/bill.jpg',
    ]);
  });

  test('leave encashment shows days when no amount is sent', () {
    final claim = ExpenseClaim.fromJson({
      'id': 8,
      'employee_id': '2',
      'title': 'Annual leave encashment',
      'type': 'leave_encashment',
      'status': 'approved',
      'allowance_on': '2026-10-01',
      'leave_type_name': 'Annual',
      'ad_to_encash': 2,
      'cfd_to_encash': 0.5,
    });

    expect(claim.employeeId, 2);
    expect(claim.typeLabel, 'Leave encashment');
    expect(claim.statusLabel, 'Approved');
    expect(claim.amountLabel, isNull);
    expect(claim.leaveType, 'Annual');
    expect(claim.daysLabel, '2 available · 0.5 carry forward');
  });

  test('the claims list keeps only this employee, newest first', () {
    final items = [
      ExpenseClaim.fromJson({
        'id': 1,
        'employee_id': 2,
        'title': 'October travel',
        'type': 'reimbursement',
        'status': 'rejected',
        'amount': 100,
        'allowance_on': '2026-10-01',
      }),
      ExpenseClaim.fromJson({
        'id': 9,
        'employee_id': 4,
        'title': 'Someone else',
        'type': 'reimbursement',
        'status': 'requested',
        'amount': 1,
        'allowance_on': '2026-11-19',
      }),
      ExpenseClaim.fromJson({
        'id': 6,
        'employee_id': 2,
        'title': 'Client dinner',
        'type': 'reimbursement',
        'status': 'requested',
        'amount': 1250.5,
        'allowance_on': '2026-11-02',
      }),
    ];

    final own = claimsForEmployee(items, 2);
    expect(own.map((c) => c.title), ['Client dinner', 'October travel']);
    expect(claimsForEmployee(items, 99), isEmpty);
  });

  test('claims group by month with filed and approved totals', () {
    final groups = groupClaimsByMonth([
      _claim(
        id: 6,
        title: 'Client dinner',
        status: 'requested',
        amount: 1250.5,
        date: '2026-11-02',
      ),
      _claim(
        id: 7,
        title: 'Taxi',
        status: 'approved',
        amount: 560,
        date: '2026-11-19',
      ),
      _claim(
        id: 1,
        title: 'October travel',
        status: 'rejected',
        amount: 100,
        date: '2026-10-01',
      ),
    ]);

    expect(groups.map((g) => g.label), ['November 2026', 'October 2026']);
    expect(groups.first.claims.map((c) => c.title), ['Client dinner', 'Taxi']);
    expect(groups.first.filed, 1810.5);
    expect(groups.first.approved, 560);
    expect(groups.first.filedLabel, '1,810.50');
    expect(groups.first.approvedLabel, '560.00');
    expect(groups.last.filed, 100);
    expect(groups.last.approved, 0);
  });

  test('month and date filters narrow the expense list', () {
    final items = [
      _claim(
        id: 6,
        title: 'Client dinner',
        status: 'requested',
        amount: 10,
        date: '2026-11-02',
      ),
      _claim(
        id: 7,
        title: 'Taxi',
        status: 'approved',
        amount: 20,
        date: '2026-11-19',
      ),
      _claim(
        id: 1,
        title: 'October travel',
        status: 'approved',
        amount: 30,
        date: '2026-10-01',
      ),
    ];

    expect(filterClaims(items, month: DateTime(2026, 11)).map((c) => c.title), [
      'Client dinner',
      'Taxi',
    ]);
    expect(
      filterClaims(items, day: DateTime(2026, 11, 2)).map((c) => c.title),
      ['Client dinner'],
    );
    expect(
      filterClaims(
        items,
        month: DateTime(2026, 11),
        day: DateTime(2026, 10, 1),
      ),
      isEmpty,
    );
  });

  testWidgets('expense claims open the claim detail', (tester) async {
    final claim = ExpenseClaim.fromJson({
      'id': 4,
      'employee_id': 2,
      'title': 'Client dinner',
      'type': 'reimbursement',
      'status': 'requested',
      'amount': 1250.5,
      'allowance_on': '2026-11-02',
      'description': 'Dinner with the client team.',
      'attachment': '/media/receipts/dinner.pdf',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseClaimsProvider.overrideWith((ref) async => [claim]),
        ],
        child: const MaterialApp(home: ExpenseClaimsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Expense claims'), findsOneWidget);
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('Filed'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('1,250.50'), findsWidgets);
    expect(find.text('0.00'), findsOneWidget);
    expect(find.text('Client dinner'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);

    await tester.tap(find.text('Client dinner'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ClaimDetailScreen), findsOneWidget);
    expect(find.text('Dinner with the client team.'), findsOneWidget);
    expect(find.text('2 Nov 2026'), findsOneWidget);
    expect(find.text('dinner.pdf'), findsOneWidget);
  });

  testWidgets('month filter hides claims from other months', (tester) async {
    final claims = [
      _claim(
        id: 6,
        title: 'Client dinner',
        status: 'requested',
        amount: 10,
        date: '2026-11-02',
      ),
      _claim(
        id: 1,
        title: 'October travel',
        status: 'approved',
        amount: 30,
        date: '2026-10-01',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [expenseClaimsProvider.overrideWith((ref) async => claims)],
        child: const MaterialApp(home: ExpenseClaimsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Client dinner'), findsOneWidget);
    expect(find.text('October travel'), findsOneWidget);

    await tester.tap(find.text('Oct 2026'));
    await tester.pump();

    expect(find.text('October travel'), findsOneWidget);
    expect(find.text('Client dinner'), findsNothing);
    expect(find.text('October 2026'), findsOneWidget);
  });
}

ExpenseClaim _claim({
  required int id,
  required String title,
  required String status,
  required num amount,
  required String date,
}) {
  return ExpenseClaim.fromJson({
    'id': id,
    'employee_id': 2,
    'title': title,
    'type': 'reimbursement',
    'status': status,
    'amount': amount,
    'allowance_on': date,
  });
}
