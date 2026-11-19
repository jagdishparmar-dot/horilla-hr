import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/features/more/edit_profile_screen.dart';
import 'package:horilla_employee/features/more/more_models.dart';

void main() {
  testWidgets('cancel and save sit on one aligned row', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EditProfileScreen(
            profile: const EmployeeProfile(
              id: 1,
              firstName: 'Ava',
              lastName: 'Stone',
              phone: '9999999999',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final title = tester.getCenter(find.text('Edit Profile'));
    expect(title.dx, closeTo(195, 8));

    final cancel = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Cancel'),
    );
    final save = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
    expect(cancel.top, closeTo(save.top, 0.5));
    expect(cancel.height, closeTo(save.height, 0.5));
    expect(cancel.height, greaterThanOrEqualTo(48));
    expect(cancel.width, closeTo(save.width, 1));
    expect(save.left, greaterThan(cancel.right));
    expect(find.text('CONTACT'), findsOneWidget);
  });
}
