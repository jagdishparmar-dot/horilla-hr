from django.template.loader import render_to_string
from django.utils.translation import gettext_lazy as _

from base.forms import ModelForm

from .models import GeoFencing, WorkSite


class WorkSiteForm(ModelForm):
    verbose_name = _("Work Site")

    class Meta:
        model = WorkSite
        exclude = ["company_id"]


class GeoFencingSetupForm(ModelForm):
    verbose_name = _("Geofence Configuration")

    class Meta:
        model = GeoFencing
        exclude = ["company_id"]
