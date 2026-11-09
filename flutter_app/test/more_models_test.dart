import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/features/more/more_models.dart';

// Payloads copied from the live API (`/payroll/payslip/`,
// `/employee/employees/<id>/`, `/helpdesk/...`) so the parsers are checked
// against the real response shapes.
void main() {
  test('payslip parses amounts, deductions and attendance summary', () {
    final item = PayslipItem.fromJson({
      'id': 4,
      'start_date': '2026-10-01',
      'end_date': '2026-10-31',
      'status': 'paid',
      'basic_pay': 10483.87,
      'gross_pay': 31341.94,
      'deduction': 1458.06,
      'net_pay': 29883.87,
      'pay_head_data': {
        'allowances': [
          {'title': 'HRA (40% of Basic)', 'amount': 0},
          {'title': 'Special Allowance', 'amount': 18000.0},
        ],
        'pretax_deductions': [
          {'title': 'Employee PF (12% of Basic)', 'amount': 1258.06},
          {'title': 'Professional Tax', 'amount': 200.0},
        ],
        'tax_deductions': [],
        'basic_pay_deductions': '',
        'paid_days': 13.0,
        'unpaid_days': 18.0,
        'working_days': 27,
        'loss_of_pay': 14516.13,
      },
    });
    expect(item.isIssued, isTrue);
    expect(item.isPaid, isTrue);
    expect(item.periodLabel, 'October 2026');
    expect(item.allowances.map((e) => e.title), [
      'HRA (40% of Basic)',
      'Special Allowance',
    ]);
    expect(item.deductions, hasLength(2));
    expect(item.deductions.fold<double>(0, (s, l) => s + l.amount), 1458.06);
    expect(item.workingDays, 27);
    expect(formatCount(item.paidDays!), '13');
  });

  test('draft payslips are not issued', () {
    final item = PayslipItem.fromJson({
      'id': 1,
      'start_date': '2026-09-01',
      'end_date': '2026-09-30',
      'status': 'draft',
      'pay_head_data': <String, dynamic>{},
    });
    expect(item.isIssued, isFalse);
  });

  test('profile maps ids that the API returns as strings', () {
    final profile = EmployeeProfile.fromJson({
      'id': 2,
      'employee_work_info_id': '2',
      'employee_first_name': 'Raj',
      'employee_last_name': 'Patel',
      'email': 'raj@coldverse.in',
      'phone': '9000090000',
      'address': 'Mehsana',
      'city': 'Mehsana',
      'state': 'Gujarat',
      'zip': '384002',
      'country': 'India',
      'dob': '2000-01-01',
      'gender': 'male',
      'emergency_contact': null,
    });
    expect(profile.workInfoId, 2);
    expect(profile.bankDetailsId, isNull);
    expect(profile.fullName, 'Raj Patel');
    expect(profile.fullAddress, 'Mehsana\nMehsana, Gujarat, 384002\nIndia');
    expect(profile.hasEmergencyContact, isFalse);
    expect(humanize(profile.gender), 'Male');
  });

  test('work info joins manager name and computes tenure', () {
    final work = WorkInfo.fromJson({
      'reporting_manager_first_name': 'Jagdish',
      'reporting_manager_last_name': 'Parmar',
      'company_name': 'Coldverse',
      'date_joining': null,
    });
    expect(work.managerName, 'Jagdish Parmar');
    expect(work.tenureLabel, isNull);
    final joined = DateTime.now().subtract(const Duration(days: 800));
    final tenured = WorkInfo.fromJson({
      'date_joining': joined.toIso8601String().substring(0, 10),
    });
    expect(tenured.tenureLabel, startsWith('2y'));
  });

  test('bank account is masked', () {
    expect(
      const BankInfo(accountNumber: '1234567890').maskedAccount,
      '•••• 7890',
    );
  });

  test('ticket, comment and faq parse the helpdesk shapes', () {
    final ticket = TicketItem.fromJson({
      'id': 1,
      'title': 'Missing allowance',
      'description': '<p>Looks <b>short</b>.</p>',
      'status': 'in_progress',
      'priority': 'medium',
      'created_date': '2026-11-09',
      'raised_on_display': 'HR',
      'ticket_type': {'id': 2, 'title': 'Payroll query', 'prefix': 'PAY'},
      'assigned_to': [
        {'id': 1, 'get_full_name': 'Jagdish Parmar'},
      ],
    });
    expect(ticket.code, 'PAY-001');
    expect(ticket.status, TicketStatus.inProgress);
    expect(ticket.status.isOpen, isTrue);
    expect(ticket.description, 'Looks short.');
    expect(ticket.assignees, ['Jagdish Parmar']);

    final comment = TicketComment.fromJson({
      'id': 1,
      'comment': 'Any update?',
      'date': '2026-11-09T14:40:20.327048+05:30',
      'employee_id': {'id': 2, 'get_full_name': 'Raj Patel'},
    });
    expect(comment.author, 'Raj Patel');
    expect(comment.authorId, 2);
    expect(comment.date, isNotNull);

    final faq = FaqItem.fromJson({
      'id': 2,
      'question': 'How do I apply for leave?',
      'answer': '<p>Use <b>Requests</b>.</p>',
      'category': {'id': 2, 'title': 'Leave'},
    });
    expect(faq.answer, 'Use Requests.');
    expect(faq.category, 'Leave');
  });

  test('clock times are formatted for display', () {
    // Newer intl versions put a narrow no-break space before AM/PM.
    String plain(String s) => s.replaceAll('\u202f', ' ');
    expect(plain(formatClock('09:05:00')), '9:05 AM');
    expect(plain(formatClock('17:30')), '5:30 PM');
    expect(formatClock(null), '—');
    expect(formatClock('n/a'), 'n/a');
  });
}
