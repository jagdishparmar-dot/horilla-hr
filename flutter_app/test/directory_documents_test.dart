import 'package:flutter_test/flutter_test.dart';
import 'package:horilla_employee/features/directory/directory_models.dart';
import 'package:horilla_employee/features/more/documents_models.dart';

// Payloads copied from the live API (`/employee/directory/`,
// `/employee/documents/`, `/employee/document-request/`, `/mobile/work-site/`).
void main() {
  test('directory page parses cards, paging and department chips', () {
    final page = DirectoryPage.fromJson({
      'count': 2,
      'next': null,
      'previous': null,
      'results': [
        {
          'id': 1,
          'badge_id': 'PEP0001',
          'first_name': 'Jagdish',
          'last_name': 'Parmar',
          'name': 'Jagdish Parmar',
          'photo': null,
          'job_position': 'Head of Operations',
          'department': 'Operations',
        },
        {
          'id': 2,
          'badge_id': 'PEP0002',
          'first_name': 'Raj',
          'last_name': 'Patel',
          'name': 'Raj Patel',
          'photo': '/media/employee/profile/raj.png',
          'job_position': null,
          'department': null,
        },
      ],
      'departments': [
        {'id': 3, 'name': 'Operations'},
      ],
    });
    expect(page.count, 2);
    expect(page.hasNext, isFalse);
    expect(page.departments.single.name, 'Operations');
    expect(page.entries.first.roleLine, 'Head of Operations · Operations');
    // A colleague with no role yet must not render "null".
    expect(page.entries.last.roleLine, '');
    expect(page.entries.last.photo, '/media/employee/profile/raj.png');
  });

  test('directory detail keeps only the basic profile', () {
    final detail = DirectoryDetail.fromJson({
      'id': 1,
      'badge_id': 'PEP0001',
      'first_name': 'Jagdish',
      'last_name': 'Parmar',
      'name': 'Jagdish Parmar',
      'photo': null,
      'job_position': null,
      'department': null,
      'job_role': null,
      'company': 'Coldverse Supply Chain Private Limited',
      'manager': null,
      'work_site': 'Jalisana',
      'work_location': null,
      'work_email': 'jagdish.parmar@shreemaruti.com',
      'work_phone': null,
    });
    expect(detail.entry.name, 'Jagdish Parmar');
    expect(detail.workSite, 'Jalisana');
    expect(detail.managerName, isNull);
    expect(detail.workPhone, isNull);
    expect(detail.workEmail, 'jagdish.parmar@shreemaruti.com');
  });

  test('work site distinguishes site, company fence and nothing', () {
    final site = WorkSiteInfo.fromJson({
      'kind': 'site',
      'name': 'Jalisana',
      'company': 'Coldverse Supply Chain Private Limited',
      'latitude': 2.0,
      'longitude': 2.0,
      'radius_in_meters': 200,
      'geofence_enabled': false,
      'location': null,
    });
    expect(site.isConfigured, isTrue);
    expect(site.hasCoordinates, isTrue);
    expect(site.geofenceEnabled, isFalse);
    expect(site.radiusMeters, 200);

    final none = WorkSiteInfo.fromJson({'kind': null});
    expect(none.isConfigured, isFalse);
  });

  test('requested document without a file waits on the employee', () {
    final doc = DocumentItem.fromJson({
      'id': 1,
      'title': 'Upload ID proof',
      'document': null,
      'status': 'requested',
      'reject_reason': null,
      'issue_date': null,
      'expiry_date': null,
      'employee_id': 2,
      'document_request_id': 1,
    });
    expect(doc.state, DocumentState.upload);
    expect(doc.canUpload, isTrue);
    expect(doc.displayTitle, 'ID proof');
    expect(doc.stateLabel, 'Upload needed');
  });

  test('uploaded, rejected and approved documents map to the right state', () {
    DocumentItem make(String status, String? file) => DocumentItem.fromJson({
      'id': 9,
      'title': 'Passport',
      'document': file,
      'status': status,
      'reject_reason': status == 'rejected' ? 'Blurry' : null,
    });

    final review = make('requested', '/media/horilla_documents/p-ae28.pdf');
    expect(review.state, DocumentState.review);
    expect(review.canUpload, isFalse);
    expect(review.fileName, 'p-ae28.pdf');

    final rejected = make('rejected', '/media/horilla_documents/p.pdf');
    expect(rejected.state, DocumentState.rejected);
    expect(rejected.canUpload, isTrue);
    expect(rejected.rejectReason, 'Blurry');

    final approved = make('approved', '/media/horilla_documents/p.pdf');
    expect(approved.state, DocumentState.approved);
    expect(approved.canUpload, isFalse);
  });

  test('upload rules mirror the request format and size limit', () {
    final rule = DocumentRequirement.fromJson({
      'id': 1,
      'title': 'ID proof',
      'format': 'pdf',
      'max_size': 1,
      'description': 'Upload a PDF',
    });
    expect(rule.ruleLabel, 'PDF · up to 1 MB');
    expect(rule.allowedExtensions, ['pdf']);

    expect(
      validateUpload(fileName: 'id.pdf', sizeBytes: 500, requirement: rule),
      isNull,
    );
    expect(
      validateUpload(fileName: 'id.exe', sizeBytes: 500, requirement: rule),
      contains('PDF'),
    );
    expect(
      validateUpload(
        fileName: 'id.pdf',
        sizeBytes: 2 * 1024 * 1024,
        requirement: rule,
      ),
      contains('limit is 1 MB'),
    );

    final any = DocumentRequirement.fromJson({
      'id': 2,
      'title': 'Other',
      'format': 'any',
    });
    expect(any.allowedExtensions, isNull);
    expect(any.ruleLabel, 'Any file type');
    expect(
      validateUpload(fileName: 'a.zip', sizeBytes: 10, requirement: any),
      isNull,
    );
  });
}
