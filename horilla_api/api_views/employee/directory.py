"""
Employee directory for the mobile client.

``GET /employee/list/employees/`` already exists, but it cannot back a
directory screen: it has no department, no badge id, no work phone and no search
on role, and the per-employee endpoints (``employees/<id>/``, work information,
bank details) are -- correctly -- owner/manager only, so a colleague's role and
contact can't be fetched through them.

This is a deliberately narrow, read-only view of the *basic* profile a
company directory shows:

    name, badge id, photo, job position / role, department, company,
    reporting manager, work site, work location, work email, work phone.

It never returns salary, contract, bank, date of birth, home address or personal
phone number. ``Employee.email`` is used as a fallback for the work email only
because the existing list endpoint already publishes it to the same audience.

Who may call it mirrors the web directory (``employee_view`` on the sidebar):
anyone with ``employee.view_employee``, anyone the accessibility feature
``employee_view`` is granted to (the default when it has never been
configured), and reporting managers. Everyone else gets 403.
"""

from django.db.models import Q
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from employee.models import Employee, EmployeeWorkInformation
from horilla_api.api_methods.base.pagination import HorillaPageNumberPagination

from .views import directory_is_accessible


def _can_browse_directory(request):
    user = request.user
    employee = getattr(user, "employee_get", None)
    if employee is None:
        return False
    if user.has_perm("employee.view_employee"):
        return True
    if directory_is_accessible(request):
        return True
    return EmployeeWorkInformation.objects.filter(
        reporting_manager_id=employee
    ).exists()


def _work_info(employee):
    try:
        return employee.employee_work_info
    except EmployeeWorkInformation.DoesNotExist:
        return None


def _photo(employee):
    profile = employee.employee_profile
    return profile.url if profile else None


def _directory_queryset(request):
    caller = request.user.employee_get
    queryset = Employee.objects.filter(is_active=True).select_related(
        "employee_work_info__job_position_id",
        "employee_work_info__job_role_id",
        "employee_work_info__department_id",
        "employee_work_info__company_id",
        "employee_work_info__reporting_manager_id",
        "employee_work_info__work_site",
    )
    company = caller.get_company()
    if company is not None:
        queryset = queryset.filter(employee_work_info__company_id=company)
    return queryset


def _card(employee):
    info = _work_info(employee)
    position = getattr(info, "job_position_id", None)
    department = getattr(info, "department_id", None)
    return {
        "id": employee.id,
        "badge_id": employee.badge_id,
        "first_name": employee.employee_first_name,
        "last_name": employee.employee_last_name or "",
        "name": employee.get_full_name(),
        "photo": _photo(employee),
        "job_position": position.job_position if position else None,
        "department": department.department if department else None,
    }


def _detail(employee):
    info = _work_info(employee)
    payload = _card(employee)
    role = getattr(info, "job_role_id", None)
    company = getattr(info, "company_id", None)
    manager = getattr(info, "reporting_manager_id", None)
    site = getattr(info, "work_site", None)
    payload.update(
        {
            "job_role": role.job_role if role else None,
            "company": company.company if company else None,
            "manager": (
                {"id": manager.id, "name": manager.get_full_name()}
                if manager
                else None
            ),
            "work_site": site.name if site and site.is_active else None,
            "work_location": getattr(info, "location", None) or None,
            "work_email": getattr(info, "email", None) or employee.email or None,
            "work_phone": getattr(info, "mobile", None) or None,
        }
    )
    return payload


class EmployeeDirectoryAPIView(APIView):
    """
    List (``?search=``, ``?department=<id>``, ``?page=``, ``?page_size=``) or,
    with ``<pk>``, fetch one colleague's basic profile.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request, pk=None):
        if getattr(request.user, "employee_get", None) is None:
            return Response(
                {"error": "No employee profile is linked to this account."},
                status=status.HTTP_403_FORBIDDEN,
            )
        if not _can_browse_directory(request):
            return Response(
                {"error": "The employee directory is not available to you."},
                status=status.HTTP_403_FORBIDDEN,
            )

        queryset = _directory_queryset(request)

        if pk is not None:
            employee = queryset.filter(pk=pk).first()
            if employee is None:
                return Response(
                    {"error": "Employee not found."},
                    status=status.HTTP_404_NOT_FOUND,
                )
            return Response(_detail(employee))

        # Departments present in the whole directory (not just this page), so
        # the client can offer filter chips without a second endpoint.
        departments = sorted(
            {
                (row[0], row[1])
                for row in queryset.filter(
                    employee_work_info__department_id__isnull=False
                ).values_list(
                    "employee_work_info__department_id",
                    "employee_work_info__department_id__department",
                )
            },
            key=lambda item: item[1].lower(),
        )

        department = request.query_params.get("department")
        if department and department.isdigit():
            queryset = queryset.filter(employee_work_info__department_id=department)

        search = (request.query_params.get("search") or "").strip()
        if search:
            queryset = queryset.filter(
                Q(employee_first_name__icontains=search)
                | Q(employee_last_name__icontains=search)
                | Q(badge_id__icontains=search)
                | Q(employee_work_info__job_position_id__job_position__icontains=search)
                | Q(employee_work_info__department_id__department__icontains=search)
            )

        queryset = queryset.order_by("employee_first_name", "employee_last_name", "id")
        paginator = HorillaPageNumberPagination()
        page = paginator.paginate_queryset(queryset, request)
        response = paginator.get_paginated_response([_card(row) for row in page])
        response.data["departments"] = [
            {"id": dept_id, "name": name} for dept_id, name in departments
        ]
        return response
