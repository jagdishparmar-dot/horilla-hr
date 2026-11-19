"""Form widget templates.

Django's default form renderer searches its own template directory before
any app, so a copy under horilla_theme/templates is never used. This renderer
looks in the theme first, then falls back to Django's built-in widget templates.
"""

from pathlib import Path

from django.conf import settings
from django.forms.renderers import DjangoTemplates
from django.utils.functional import cached_property

import django.forms.renderers as django_form_renderers


class HorillaFormRenderer(DjangoTemplates):
    @cached_property
    def engine(self):
        builtin_templates = Path(django_form_renderers.__file__).resolve().parent / "templates"
        return self.backend(
            {
                "APP_DIRS": True,
                "DIRS": [
                    settings.BASE_DIR / "horilla_theme" / "templates",
                    builtin_templates,
                ],
                "NAME": "djangoforms",
                "OPTIONS": {},
            }
        )
