import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/core/api/api_exception.dart';
import 'package:horilla_employee/features/more/contract_screen.dart';
import 'package:horilla_employee/features/more/more_models.dart';
import 'package:horilla_employee/features/more/more_providers.dart';
import 'package:horilla_employee/features/more/payslips_screen.dart';

void main() {
  test('own contract parses wage, status and the file', () {
    final item = ContractItem.fromJson({
      'id': 8,
      'employee_id': 2,
      'contract_name': 'Raj Patel — full time',
      'contract_start_date': '2024-04-01',
      'contract_end_date': null,
      'contract_status': 'active',
      'wage_type': 'monthly',
      'pay_frequency': 'monthly',
      'wage': 44000,
      'hourly_wage': null,
      'monthly_ctc': 62000,
      'notice_period_in_days': 30,
      'department_name': 'Engineering',
      'job_position_name': 'Developer',
      'job_role_name': 'Backend',
      'shift_name': 'General',
      'work_type_name': 'Full time',
      'contract_document': '/media/contracts/raj.pdf',
      'note': 'Probation completed.',
    });

    expect(item.employeeId, 2);
    expect(item.name, 'Raj Patel — full time');
    expect(item.isActive, isTrue);
    expect(item.statusLabel, 'Active');
    expect(item.payLabel, '44,000.00 / month');
    expect(item.ctcLabel, '62,000.00');
    expect(item.dateLabel, '1 Apr 2024 · open ended');
    expect(item.noticeLabel, '30 days');
    expect(item.department, 'Engineering');
    expect(item.jobPosition, 'Developer');
    expect(item.documentUrl, '/media/contracts/raj.pdf');
    expect(item.note, 'Probation completed.');
  });

  test('hourly wage is shown per hour and a missing file stays empty', () {
    final item = ContractItem.fromJson({
      'id': 3,
      'employee_id': '2',
      'contract_name': 'Hourly support',
      'contract_start_date': '2025-01-06',
      'contract_end_date': '2025-06-30',
      'contract_status': 'expired',
      'wage_type': 'hourly',
      'wage': 100,
      'hourly_wage': 250,
      'notice_period_in_days': 0,
    });

    expect(item.employeeId, 2);
    expect(item.isActive, isFalse);
    expect(item.statusLabel, 'Expired');
    expect(item.payLabel, '250.00 / hour');
    expect(item.dateLabel, '6 Jan 2025 – 30 Jun 2025');
    expect(item.noticeLabel, isNull);
    expect(item.documentUrl, isNull);
    expect(item.ctcLabel, isNull);
  });

  test('the active contract is the one shown for this employee', () {
    final items = [
      ContractItem.fromJson({
        'id': 1,
        'employee_id': 2,
        'contract_name': 'Old',
        'contract_start_date': '2020-01-01',
        'contract_end_date': '2023-12-31',
        'contract_status': 'expired',
        'wage': 10000,
      }),
      ContractItem.fromJson({
        'id': 9,
        'employee_id': 4,
        'contract_name': 'Someone else',
        'contract_start_date': '2026-01-01',
        'contract_status': 'active',
        'wage': 1,
      }),
      ContractItem.fromJson({
        'id': 8,
        'employee_id': 2,
        'contract_name': 'Current',
        'contract_start_date': '2024-04-01',
        'contract_status': 'active',
        'wage': 44000,
      }),
    ];

    final own = contractsForEmployee(items, 2);
    expect(own.map((c) => c.name), ['Current', 'Old']);
    expect(preferredContract(own)?.name, 'Current');
    expect(contractsForEmployee(items, 99), isEmpty);
    expect(preferredContract(const []), isNull);
  });

  test('payslip download uses pdf, and html when the server sends a page', () {
    expect(
      payslipFileKind(statusCode: 200, contentType: 'application/pdf'),
      PayslipFileKind.pdf,
    );
    expect(
      payslipFileKind(statusCode: 200, contentType: 'text/html; charset=utf-8'),
      PayslipFileKind.html,
    );
    expect(
      payslipFileKind(statusCode: 503, contentType: 'application/json'),
      isNull,
    );
    expect(payslipFileName(4, PayslipFileKind.pdf), 'payslip-4.pdf');
    expect(payslipFileName(4, PayslipFileKind.html), 'payslip-4.html');
  });

  testWidgets('payslip detail can download the file', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          payslipDownloaderProvider.overrideWith(
            (ref) =>
                (_) async => throw ApiException('PDF unavailable'),
          ),
        ],
        child: MaterialApp(
          home: PayslipDetailScreen(
            item: PayslipItem.fromJson({
              'id': 4,
              'start_date': '2026-10-01',
              'end_date': '2026-10-31',
              'status': 'paid',
              'basic_pay': 100,
              'gross_pay': 100,
              'deduction': 0,
              'net_pay': 100,
              'pay_head_data': <String, dynamic>{},
            }),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Download payslip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('PDF unavailable'), findsOneWidget);
  });

  testWidgets('contract screen shows this employee contract', (tester) async {
    final item = ContractItem.fromJson({
      'id': 8,
      'employee_id': 2,
      'contract_name': 'Raj Patel — full time',
      'contract_start_date': '2024-04-01',
      'contract_status': 'active',
      'wage_type': 'monthly',
      'wage': 44000,
      'department_name': 'Engineering',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contractsProvider.overrideWith((ref) async => [item]),
        ],
        child: const MaterialApp(home: ContractScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Pay'), findsOneWidget);
    expect(find.text('Raj Patel — full time'), findsOneWidget);
    expect(find.text('44,000.00 / month'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);

    await tester.tap(find.text('Raj Patel — full time'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Engineering'), findsOneWidget);
    expect(find.text('1 Apr 2024 · open ended'), findsOneWidget);
  });
}
