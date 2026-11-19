import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/features/home/models.dart';
import 'package:horilla_employee/features/notifications/models.dart';

void main() {
  test('announcement details drop html tags', () {
    final item = HomeAnnouncement.fromJson({
      'id': 4,
      'title': 'Office closed',
      'description': '<p>The office is closed on Friday.</p>',
    });

    expect(item.description, 'The office is closed on Friday.');
    expect(item.previewText, 'The office is closed on Friday.');
    expect(item.previewText.contains('<'), isFalse);
  });

  test('attendance notifications show the date instead of the placeholder', () {
    final item = AppNotification.fromJson({
      'id': 9,
      'verb': 'Your attendance for the date %(attendance_date)s is validated',
      'unread': true,
      'timestamp': '2026-11-19T10:00:00Z',
      'data': {
        'verb_params': {'attendance_date': '2026-11-18'},
        'redirect': '/attendance/attendance-view',
      },
    });

    expect(
      item.title,
      'Your attendance for the date 2026-11-18 is validated',
    );
    expect(item.title.contains('attendance_date'), isFalse);
  });
}
