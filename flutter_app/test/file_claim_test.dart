import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/features/more/claims_screen.dart';
import 'package:horilla_employee/features/more/file_claim_screen.dart';
import 'package:horilla_employee/features/more/more_models.dart';
import 'package:horilla_employee/features/more/more_providers.dart';

void main() {
  test('a reimbursement needs a title, amount, date and receipt', () {
    final draft = ClaimDraft(
      title: 'Client dinner',
      date: DateTime(2026, 11, 2),
      amount: 1250.5,
      description: 'Dinner with the client team.',
      fileName: 'dinner.pdf',
      filePath: '/tmp/dinner.pdf',
    );

    expect(draft.fields['type'], 'reimbursement');
    expect(draft.fields['title'], 'Client dinner');
    expect(draft.fields['allowance_on'], '2026-11-02');
    expect(draft.fields['amount'], '1250.5');
    expect(draft.fields['description'], 'Dinner with the client team.');
    expect(draft.fileName, 'dinner.pdf');

    expect(
      claimReady(
        title: 'Client dinner',
        amountText: '1250.5',
        date: DateTime(2026, 11, 2),
        fileName: 'dinner.pdf',
      ),
      isTrue,
    );
    expect(
      claimReady(
        title: 'Client dinner',
        amountText: '0',
        date: DateTime(2026, 11, 2),
        fileName: 'dinner.pdf',
      ),
      isFalse,
    );
    expect(
      claimReady(
        title: 'Client dinner',
        amountText: '10',
        date: DateTime(2026, 11, 2),
        fileName: null,
      ),
      isFalse,
    );
  });

  testWidgets('filing a claim sends the receipt with the expense', (
    tester,
  ) async {
    ClaimDraft? filed;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseClaimsProvider.overrideWith((ref) async => const []),
          claimFilePickerProvider.overrideWith(
            (ref) =>
                () async => (name: 'dinner.pdf', path: '/tmp/dinner.pdf'),
          ),
          claimFilerProvider.overrideWith(
            (ref) => (draft) async {
              filed = draft;
            },
          ),
        ],
        child: const MaterialApp(home: ExpenseClaimsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('File a claim'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(FileClaimScreen), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('claim-title')),
      'Client dinner',
    );
    await tester.enterText(find.byKey(const Key('claim-amount')), '1250.5');
    await tester.tap(find.text('Attach receipt'));
    await tester.pump();

    expect(find.text('dinner.pdf'), findsOneWidget);
    await tester.tap(find.text('Submit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(filed, isNotNull);
    expect(filed!.fields['type'], 'reimbursement');
    expect(filed!.fields['title'], 'Client dinner');
    expect(filed!.fields['amount'], '1250.5');
    expect(filed!.fileName, 'dinner.pdf');
    expect(filed!.filePath, '/tmp/dinner.pdf');
  });
}
