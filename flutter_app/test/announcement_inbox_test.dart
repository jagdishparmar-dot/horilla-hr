import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/features/home/announcement_models.dart';
import 'package:horilla_employee/features/home/announcements_repository.dart';
import 'package:horilla_employee/features/home/announcements_screen.dart';
import 'package:horilla_employee/features/home/home_extra_sections.dart';
import 'package:horilla_employee/features/home/models.dart';

void main() {
  test('inbox items use the announcement list payload', () {
    final page = AnnouncementPage.fromJson({
      'count': 2,
      'next': 'http://127.0.0.1:8000/api/v1/base/announcement-view?page=2',
      'results': [
        {
          'id': 7,
          'title': 'Office closed',
          'content': [
            {'type': 'paragraph', 'text': 'The office is closed on Friday.'},
            {'type': 'bullet', 'text': 'Bring your laptop home'},
          ],
          'created_at': '2026-11-18T09:30:00Z',
          'expire_date': '2026-12-01',
          'has_viewed': false,
        },
      ],
    });

    expect(page.hasNext, isTrue);
    expect(page.items, hasLength(1));
    final item = page.items.single;
    expect(item.id, 7);
    expect(item.title, 'Office closed');
    expect(item.hasViewed, isFalse);
    expect(item.createdAt, isNotNull);
    expect(item.expireDate, DateTime(2026, 12, 1));
    expect(
      item.previewText,
      'The office is closed on Friday.\n• Bring your laptop home',
    );
  });

  test('detail payload keeps the author and attachments', () {
    final item = AnnouncementItem.fromJson({
      'id': 3,
      'title': 'Policy update',
      'content': [
        {'type': 'heading', 'text': 'What changed'},
        {'type': 'paragraph', 'text': 'Leave now needs a manager note.'},
      ],
      'has_viewed': true,
      'author': 'Mina Cole',
      'attachments': [
        {'name': 'leave.pdf', 'url': '/media/leave.pdf', 'is_image': false},
      ],
    });

    expect(item.author, 'Mina Cole');
    expect(item.hasViewed, isTrue);
    expect(item.attachments.single.name, 'leave.pdf');
    expect(item.attachments.single.url, '/media/leave.pdf');
    expect(item.attachments.single.isImage, isFalse);
    expect(item.content.first.type, 'heading');
    expect(item.previewText, 'What changed\nLeave now needs a manager note.');
  });

  test('a missing body still has a readable preview', () {
    final item = AnnouncementItem.fromJson({
      'id': 1,
      'title': 'Hello',
      'content': const [],
    });

    expect(item.hasViewed, isFalse);
    expect(item.previewText, 'No additional details.');
    expect(item.attachments, isEmpty);
  });

  testWidgets('View all on the announcement card opens the inbox', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          announcementsProvider.overrideWith(
            (ref) async => [
              AnnouncementItem.fromJson({
                'id': 7,
                'title': 'Office closed',
                'content': [
                  {'type': 'paragraph', 'text': 'Closed on Friday.'},
                ],
                'has_viewed': false,
              }),
            ],
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HomeAnnouncementSection(
              announcement: HomeAnnouncement.fromJson({
                'id': 7,
                'title': 'Office closed',
                'description': '<p>Closed on Friday.</p>',
              }),
            ),
          ),
        ),
      ),
    );

    expect(find.text('View all'), findsOneWidget);
    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();

    expect(find.byType(AnnouncementsScreen), findsOneWidget);
    expect(find.text('Office closed'), findsWidgets);
    expect(find.text('Closed on Friday.'), findsOneWidget);
  });
}
