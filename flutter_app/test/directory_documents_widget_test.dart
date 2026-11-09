import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/core/api/api_exception.dart';
import 'package:horilla_employee/features/directory/directory_models.dart';
import 'package:horilla_employee/features/directory/directory_repository.dart';
import 'package:horilla_employee/features/directory/directory_screen.dart';
import 'package:horilla_employee/features/more/documents_models.dart';
import 'package:horilla_employee/features/more/documents_repository.dart';
import 'package:horilla_employee/features/more/documents_screen.dart';

class _FakeDirectory extends DirectoryRepository {
  _FakeDirectory(this.onFetch) : super(Dio());

  final Future<DirectoryPage> Function(String search, int? department) onFetch;
  final calls = <(String, int?)>[];

  @override
  Future<DirectoryPage> fetchPage({
    int page = 1,
    String search = '',
    int? departmentId,
  }) {
    calls.add((search, departmentId));
    return onFetch(search, departmentId);
  }
}

DirectoryPage _page(List<DirectoryEntry> entries) => DirectoryPage(
  entries: entries,
  count: entries.length,
  hasNext: false,
  departments: const [DirectoryDepartment(id: 3, name: 'Operations')],
);

const _jagdish = DirectoryEntry(
  id: 1,
  name: 'Jagdish Parmar',
  badgeId: 'PEP0001',
  jobPosition: 'Head of Operations',
  department: 'Operations',
);
const _raj = DirectoryEntry(id: 2, name: 'Raj Patel', badgeId: 'PEP0002');

// A fresh key per host so each scenario builds a brand-new screen state.
Widget _host(Widget child, List<Override> overrides) => ProviderScope(
  key: UniqueKey(),
  overrides: overrides,
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('directory lists colleagues, then searches on the server', (
    tester,
  ) async {
    final fake = _FakeDirectory((search, dept) async {
      if (search.isEmpty) return _page(const [_jagdish, _raj]);
      return _page(const [_raj]);
    });
    await tester.pumpWidget(
      _host(const DirectoryScreen(), [
        directoryRepositoryProvider.overrideWithValue(fake),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jagdish Parmar'), findsOneWidget);
    expect(find.text('Head of Operations · Operations'), findsOneWidget);
    expect(find.text('Raj Patel'), findsOneWidget);
    expect(find.text('2 colleagues'), findsOneWidget);
    expect(find.text('Operations'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'raj');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(fake.calls.last.$1, 'raj');
    expect(find.text('Jagdish Parmar'), findsNothing);
    expect(find.text('1 colleague'), findsOneWidget);
  });

  testWidgets('directory shows empty, forbidden and error states', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const DirectoryScreen(), [
        directoryRepositoryProvider.overrideWithValue(
          _FakeDirectory((_, _) async => _page(const [])),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('No colleagues yet'), findsOneWidget);

    await tester.pumpWidget(
      _host(const DirectoryScreen(), [
        directoryRepositoryProvider.overrideWithValue(
          _FakeDirectory(
            (_, _) async => throw ApiException(
              'The employee directory is not available to you.',
              statusCode: 403,
            ),
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Directory unavailable'), findsOneWidget);
    expect(
      find.text('The employee directory is not available to you.'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _host(const DirectoryScreen(), [
        directoryRepositoryProvider.overrideWithValue(
          _FakeDirectory((_, _) async => throw ApiException('Server is down')),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load this"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('documents show what needs action and hide the rest', (
    tester,
  ) async {
    final entries = [
      DocumentEntry(
        document: DocumentItem.fromJson({
          'id': 1,
          'title': 'Upload ID proof',
          'status': 'requested',
          'document': null,
          'document_request_id': 1,
        }),
        requirement: const DocumentRequirement(
          id: 1,
          title: 'ID proof',
          format: 'pdf',
          maxSizeMb: 1,
          description: 'Upload a PDF',
        ),
      ),
      DocumentEntry(
        document: DocumentItem.fromJson({
          'id': 2,
          'title': 'Passport',
          'status': 'approved',
          'document': '/media/horilla_documents/p.pdf',
        }),
      ),
    ];
    await tester.pumpWidget(
      _host(const DocumentsScreen(), [
        documentsProvider.overrideWith((ref) async => entries),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 documents'), findsOneWidget);
    expect(find.text('1 document needs your attention.'), findsOneWidget);
    expect(find.text('ID proof'), findsOneWidget);
    expect(find.text('Upload needed'), findsOneWidget);
    expect(find.text('Accepted: PDF · up to 1 MB'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    // The approved one can be viewed but not replaced.
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
    expect(find.text('Upload again'), findsNothing);
  });

  testWidgets('documents empty state', (tester) async {
    await tester.pumpWidget(
      _host(const DocumentsScreen(), [
        documentsProvider.overrideWith((ref) async => <DocumentEntry>[]),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('No documents yet'), findsOneWidget);
  });
}
