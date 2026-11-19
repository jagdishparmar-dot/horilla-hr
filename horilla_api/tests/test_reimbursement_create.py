"""A reimbursement filed from the mobile app must stay on the employee's list.

Multipart form data treats a missing checkbox as false. ``is_active`` is that
kind of field on the serializer, and both the API list and the web
reimbursement page hide inactive rows. The web form never posts ``is_active``
and relies on the model default. The API must do the same.
"""

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from rest_framework.test import APIClient

from horilla.testkit import make_company, make_employee, make_user
from payroll.models.models import Reimbursement

ENDPOINT = "/api/payroll/reimbusement/"


class ReimbursementCreateVisibilityTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        company = make_company("Claim Co")
        self.user = make_user("claim_employee", password="secret123")
        self.employee = make_employee(
            company=company,
            email="claim_employee@test.horilla",
            user=self.user,
        )
        self.client.force_authenticate(user=self.user)

    def test_filed_reimbursement_stays_active_and_listed(self):
        receipt = SimpleUploadedFile(
            "dinner.png", b"receipt", content_type="image/png"
        )
        response = self.client.post(
            ENDPOINT,
            {
                "title": "Client dinner",
                "type": "reimbursement",
                "employee_id": self.employee.id,
                "allowance_on": "2026-11-19",
                "amount": "560",
                "description": "Dinner with the client team.",
                "attachment": receipt,
            },
            format="multipart",
        )
        self.assertEqual(response.status_code, 200, response.content)

        claim = Reimbursement.objects.entire().get(title="Client dinner")
        self.assertTrue(claim.is_active)
        self.assertEqual(claim.employee_id_id, self.employee.id)
        self.assertEqual(claim.status, "requested")

        listed = self.client.get(ENDPOINT)
        self.assertEqual(listed.status_code, 200, listed.content)
        ids = [row["id"] for row in listed.data["results"]]
        self.assertIn(claim.id, ids)
