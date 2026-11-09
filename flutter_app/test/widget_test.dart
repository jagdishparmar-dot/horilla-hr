import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:horilla_employee/app.dart';

void main() {
  testWidgets('App boots to login or loading', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HorillaApp()));
    await tester.pump();
    expect(find.byType(HorillaApp), findsOneWidget);
  });
}
