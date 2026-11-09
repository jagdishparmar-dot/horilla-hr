from django.core.exceptions import ValidationError
from django.db import models
from django.db.models import Q
from django.utils.translation import gettext_lazy as _
from geopy.geocoders import Nominatim

from base.horilla_company_manager import HorillaCompanyManager


class GeoFencing(models.Model):
    latitude = models.FloatField()
    longitude = models.FloatField()
    radius_in_meters = models.IntegerField()
    company_id = models.OneToOneField(
        "base.Company",
        related_name="geo_fencing",
        on_delete=models.CASCADE,
        blank=True,
        null=True,
    )
    start = models.BooleanField(default=False)

    @classmethod
    def for_company(cls, company):
        """
        The fence that applies to ``company``: its own, else the global one (the row with no
        company), else None. A company-specific fence overrides the global one - including a
        company fence that is switched off (``start=False``), which turns the fence off for
        that company even while the global one is on.
        """
        fence = None
        if company is not None:
            fence = cls.objects.filter(company_id=company).first()
        if fence is None:
            fence = cls.objects.filter(company_id__isnull=True).first()
        return fence

    def clean(self):
        if self.company_id is None:
            qs = GeoFencing.objects.filter(company_id__isnull=True)
            if self.pk:
                qs = qs.exclude(pk=self.pk)
            if qs.exists():
                raise ValidationError(
                    _("Only one GeoFencing can have a null company_id.")
                )

        geolocator = Nominatim(
            user_agent="geo_checker_unique"
        )  # Unique user-agent is important
        try:
            location = geolocator.reverse(
                (self.latitude, self.longitude), exactly_one=True
            )
            if not location:
                raise ValidationError(_("Invalid location coordinates."))
        except Exception as e:
            raise ValidationError(f"Geolocation error: {e}")

        return super().clean()

    def save(self, *args, **kwargs):
        self.full_clean()  # Run clean before save
        super().save(*args, **kwargs)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["company_id"],
                name="unique_company_id_when_not_null_geofencing",
                condition=~Q(company_id=None),
            )
        ]


class WorkSite(models.Model):
    """
    A physical site under one company. When ``start`` is on, employees assigned
    to the site must punch inside its radius. A switched-off site does not fall
    back to the company fence.
    """

    company_id = models.ForeignKey(
        "base.Company",
        related_name="work_sites",
        on_delete=models.CASCADE,
        verbose_name=_("Company"),
    )
    name = models.CharField(max_length=100, verbose_name=_("Work Site"))
    latitude = models.FloatField(verbose_name=_("Latitude"))
    longitude = models.FloatField(verbose_name=_("Longitude"))
    radius_in_meters = models.PositiveIntegerField(verbose_name=_("Radius in meters"))
    start = models.BooleanField(
        default=False,
        verbose_name=_("Enable geofence"),
        help_text=_(
            "When enabled, employees assigned to this site can check in and "
            "check out only from inside this radius."
        ),
    )
    is_active = models.BooleanField(default=True, verbose_name=_("Active"))

    # Company-scoped like the other tenant models, so site pickers and filters
    # (employee form, employee filter) only offer the selected company's sites.
    objects = HorillaCompanyManager()

    class Meta:
        verbose_name = _("Work Site")
        verbose_name_plural = _("Work Sites")
        ordering = ["name"]

    def __str__(self):
        return f"{self.name} ({self.company_id})"

    def clean(self):
        if self.latitude is None or not -90 <= float(self.latitude) <= 90:
            raise ValidationError({"latitude": _("Latitude must be between -90 and 90.")})
        if self.longitude is None or not -180 <= float(self.longitude) <= 180:
            raise ValidationError(
                {"longitude": _("Longitude must be between -180 and 180.")}
            )
        if not self.radius_in_meters or int(self.radius_in_meters) <= 0:
            raise ValidationError(
                {"radius_in_meters": _("Radius must be greater than zero.")}
            )
        return super().clean()

    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)


def fence_label(fence):
    """Name shown to the person punching: work site, else company, else a generic label."""
    name = getattr(fence, "name", None)
    if name:
        return str(name)
    company = getattr(fence, "company_id", None)
    company_name = getattr(company, "company", None)
    if company_name:
        return str(company_name)
    return "work location"


def enforceable_fence(employee=None, company=None):
    """
    The circle that must contain a punch, or None when no fence applies.

    An assigned active work site wins: enabled means that site's circle, disabled
    means the employee is not fenced (the company fence is not used). With no
    site, the company's own GeoFencing row is used, else the global one.
    """
    if employee is not None:
        work_info = None
        try:
            work_info = employee.employee_work_info
        except Exception:
            work_info = None
        site = getattr(work_info, "work_site", None) if work_info is not None else None
        if site is not None and getattr(site, "is_active", True):
            if getattr(site, "start", False):
                return site
            return None
        if company is None and hasattr(employee, "get_company"):
            company = employee.get_company()
    if company is None:
        return None
    fence = GeoFencing.for_company(company)
    if fence is not None and fence.start:
        return fence
    return None