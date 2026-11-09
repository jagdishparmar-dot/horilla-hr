"""
Mobile directory, own-site lookup and employee document uploads.

``/employee/directory/`` is the colleague list the app shows. It is the one
endpoint that returns *other* people's work details to an ordinary employee, so
these pin both who may call it and which fields it may ever return.

The document tests cover ``PUT /employee/documents/<id>/``: an employee uploads
the file HR asked for, but approval stays HR's decision.
"""

from django.contrib.auth.models import Permission
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

import tempfile

from accessibility.models import DefaultAccessibility
from base.models import Department, JobPosition
from geofencing.models import WorkSite
from horilla.horilla_middlewares import set_selected_company
from horilla.testkit import make_company, make_employee, make_user
from horilla_documents.models import Document, DocumentRequest

DIRECTORY = "/api/v1/employee/directory/"
WORK_SITE = "/api/v1/mobile/work-site/"
DOCUMENT = "/api/v1/employee/documents/{}/"


class DirectoryTests(TestCase):
    def setUp(self):
        set_selected_company(None)
        self.company = make_company("Dir Co")
        self.other_company = make_company("Elsewhere Ltd")
        self.department = Department.objects.create(department="Engineering")
        self.position = JobPosition.objects.create(
            job_position="Developer", department_id=self.department
        )

        self.user = make_user("dir_viewer")
        self.me = make_employee(
            company=self.company, email="me@dir.test", first_name="Mia", user=self.user
        )
        self.colleague = make_employee(
            company=self.company,
            email="ann@dir.test",
            first_name="Ann",
            last_name="Archer",
            department=self.department,
        )
        info = self.colleague.employee_work_info
        info.job_position_id = self.position
        info.mobile = "5550100"
        info.location = "Floor 2"
        info.basic_salary = 91234
        info.save()
        self.colleague.dob = "1990-05-05"
        self.colleague.address = "12 Private Lane"
        self.colleague.phone = "9998887777"
        self.colleague.save()

        self.stranger = make_employee(
            company=self.other_company, email="far@dir.test", first_name="Far"
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_requires_authentication(self):
        self.assertEqual(APIClient().get(DIRECTORY).status_code, 401)

    def test_lists_colleagues_of_my_company_only(self):
        response = self.client.get(DIRECTORY)
        self.assertEqual(response.status_code, 200, response.content)
        ids = {row["id"] for row in response.data["results"]}
        self.assertIn(self.colleague.id, ids)
        self.assertNotIn(self.stranger.id, ids)

    def test_card_and_detail_never_carry_pay_or_personal_fields(self):
        card = next(
            row
            for row in self.client.get(DIRECTORY).data["results"]
            if row["id"] == self.colleague.id
        )
        detail = self.client.get(f"{DIRECTORY}{self.colleague.id}/").data
        forbidden = (
            "basic_salary",
            "salary_hour",
            "dob",
            "address",
            "phone",
            "bank",
            "wage",
            "contract",
        )
        for payload in (card, detail):
            for key in forbidden:
                self.assertNotIn(key, payload, f"{key} leaked into the directory")
            self.assertNotIn("91234", str(payload))
            self.assertNotIn("12 Private Lane", str(payload))
            self.assertNotIn("9998887777", str(payload))

        self.assertEqual(card["job_position"], "Developer")
        self.assertEqual(card["department"], "Engineering")
        self.assertEqual(detail["work_phone"], "5550100")
        self.assertEqual(detail["work_location"], "Floor 2")

    def test_search_and_department_filter(self):
        by_name = self.client.get(DIRECTORY, {"search": "archer"}).data
        self.assertEqual([r["id"] for r in by_name["results"]], [self.colleague.id])
        by_role = self.client.get(DIRECTORY, {"search": "develop"}).data
        self.assertEqual(by_role["count"], 1)
        by_dept = self.client.get(DIRECTORY, {"department": self.department.id}).data
        self.assertEqual([r["id"] for r in by_dept["results"]], [self.colleague.id])
        # Chips cover the whole directory, not just the filtered page.
        self.assertEqual(
            by_name["departments"],
            [{"id": self.department.id, "name": "Engineering"}],
        )

    def test_archived_employees_are_hidden_and_unknown_ids_404(self):
        self.colleague.is_active = False
        self.colleague.save()
        ids = {r["id"] for r in self.client.get(DIRECTORY).data["results"]}
        self.assertNotIn(self.colleague.id, ids)
        self.assertEqual(
            self.client.get(f"{DIRECTORY}{self.colleague.id}/").status_code, 404
        )
        # Another company's employee is invisible too, not "forbidden".
        self.assertEqual(
            self.client.get(f"{DIRECTORY}{self.stranger.id}/").status_code, 404
        )

    def test_follows_the_web_accessibility_setting(self):
        DefaultAccessibility.objects.create(
            feature="employee_view", is_enabled=True, exclude_all=True, filter="{}"
        )
        self.assertEqual(self.client.get(DIRECTORY).status_code, 403)
        self.assertEqual(
            self.client.get(f"{DIRECTORY}{self.colleague.id}/").status_code, 403
        )

    def test_permission_holder_and_manager_keep_access_when_excluded(self):
        DefaultAccessibility.objects.create(
            feature="employee_view", is_enabled=True, exclude_all=True, filter="{}"
        )
        report = make_employee(company=self.company, email="rep@dir.test")
        report.employee_work_info.reporting_manager_id = self.me
        report.employee_work_info.save()
        self.assertEqual(self.client.get(DIRECTORY).status_code, 200)

        other = make_user("dir_perm")
        make_employee(company=self.company, email="perm@dir.test", user=other)
        other.user_permissions.add(Permission.objects.get(codename="view_employee"))
        client = APIClient()
        client.force_authenticate(user=type(other).objects.get(pk=other.pk))
        self.assertEqual(client.get(DIRECTORY).status_code, 200)


class WorkSiteTests(TestCase):
    def setUp(self):
        set_selected_company(None)
        self.company = make_company("Site Co")
        self.user = make_user("site_user")
        self.employee = make_employee(
            company=self.company, email="site@test.horilla", user=self.user
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_nothing_configured(self):
        self.assertEqual(self.client.get(WORK_SITE).json(), {"kind": None})

    def test_assigned_site_is_reported_even_when_its_fence_is_off(self):
        site = WorkSite.objects.create(
            company_id=self.company,
            name="Depot",
            latitude=1.0,
            longitude=2.0,
            radius_in_meters=150,
            start=False,
        )
        info = self.employee.employee_work_info
        info.work_site = site
        info.save()
        body = self.client.get(WORK_SITE).json()
        self.assertEqual(body["kind"], "site")
        self.assertEqual(body["name"], "Depot")
        self.assertEqual(body["radius_in_meters"], 150)
        self.assertFalse(body["geofence_enabled"])


class DocumentUploadTests(TestCase):
    def setUp(self):
        set_selected_company(None)
        self.media = tempfile.mkdtemp()
        override = override_settings(MEDIA_ROOT=self.media)
        override.enable()
        self.addCleanup(override.disable)

        self.company = make_company("Doc Upload Co")
        self.user = make_user("doc_owner")
        self.owner = make_employee(
            company=self.company, email="owner@doc.test", user=self.user
        )
        request = DocumentRequest.objects.create(
            title="ID proof", format="pdf", max_size=1
        )
        request.employee_id.add(self.owner)
        self.document = Document.objects.get(
            employee_id=self.owner, document_request_id=request
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def _put(self, name="id.pdf", content=b"%PDF-1.4 ok", **extra):
        return self.client.put(
            DOCUMENT.format(self.document.pk),
            {"document": SimpleUploadedFile(name, content), **extra},
            format="multipart",
        )

    def test_owner_uploads_and_it_waits_for_review(self):
        response = self._put()
        self.assertEqual(response.status_code, 200, response.content)
        self.document.refresh_from_db()
        self.assertTrue(self.document.document)
        self.assertEqual(self.document.status, "requested")

    def test_owner_cannot_approve_their_own_upload(self):
        response = self._put(status="approved", reject_reason="", employee_id=999)
        self.assertEqual(response.status_code, 200, response.content)
        self.document.refresh_from_db()
        self.assertEqual(self.document.status, "requested")
        self.assertEqual(self.document.employee_id_id, self.owner.id)

    def test_format_and_size_limits_are_enforced(self):
        wrong_type = self._put(name="id.exe")
        self.assertEqual(wrong_type.status_code, 400)
        too_big = self._put(content=b"0" * (2 * 1024 * 1024))
        self.assertEqual(too_big.status_code, 400)
        self.document.refresh_from_db()
        self.assertFalse(self.document.document)

    def test_rejected_upload_returns_to_review_and_approved_is_locked(self):
        Document.objects.filter(pk=self.document.pk).update(
            status="rejected", reject_reason="Blurry"
        )
        response = self._put()
        self.assertEqual(response.status_code, 200, response.content)
        self.document.refresh_from_db()
        self.assertEqual(self.document.status, "requested")
        self.assertFalse(self.document.reject_reason)

        Document.objects.filter(pk=self.document.pk).update(status="approved")
        self.assertEqual(self._put().status_code, 400)
