import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('App boots to login or loading', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HorillaApp()));
    await tester.pump();
    expect(find.byType(HorillaApp), findsOneWidget);
  });
}
