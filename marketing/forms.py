from django import forms

from control.catalog import sellable_plans
from control.models import Plan, Tenant
from control.naming import TenantSlugError, validate_tenant_slug


class WorkspaceLookupForm(forms.Form):
    slug = forms.CharField(
        label="Workspace",
        max_length=31,
        widget=forms.TextInput(
            attrs={
                "placeholder": "your_company",
                "autocomplete": "off",
                "autocapitalize": "none",
                "spellcheck": "false",
            }
        ),
    )


def _use_plain_option_template(field):
    # Horilla swaps Select.option_template_name globally, and its version
    # renders the empty choice as disabled. The public forms want Django's.
    field.widget.option_template_name = "django/forms/widgets/select_option.html"


class SalesInquiryForm(forms.Form):
    """Talk to Sales. No workspace address: sales agrees that with the customer."""

    contact_name = forms.CharField(
        label="Your name",
        max_length=120,
        widget=forms.TextInput(attrs={"placeholder": "Priya Sharma", "autocomplete": "name"}),
    )
    company_name = forms.CharField(
        label="Company",
        max_length=120,
        widget=forms.TextInput(attrs={"placeholder": "Acme Industries", "autocomplete": "organization"}),
    )
    email = forms.EmailField(
        label="Work email",
        widget=forms.EmailInput(attrs={"placeholder": "priya@acme.com", "autocomplete": "email"}),
    )
    phone = forms.CharField(
        label="Phone",
        max_length=32,
        required=False,
        widget=forms.TextInput(attrs={"placeholder": "Optional", "autocomplete": "tel"}),
    )
    plan = forms.ModelChoiceField(
        label="Plan you are interested in",
        queryset=Plan.objects.none(),
        required=False,
        empty_label="Not sure yet",
    )
    seat_count = forms.IntegerField(
        label="Active employees",
        min_value=1,
        required=False,
        widget=forms.NumberInput(attrs={"placeholder": "How many people?"}),
    )
    message = forms.CharField(
        label="What would you like to talk about?",
        widget=forms.Textarea(
            attrs={
                "rows": 4,
                "placeholder": "Your setup today, what you need, and when you want to start.",
            }
        ),
        required=False,
        max_length=2000,
    )

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["plan"].queryset = sellable_plans().filter(status=Plan.Status.ACTIVE)
        _use_plain_option_template(self.fields["plan"])


class WorkspaceRequestForm(forms.Form):
    company_name = forms.CharField(
        label="Company",
        max_length=120,
        widget=forms.TextInput(attrs={"placeholder": "Acme Industries", "autocomplete": "organization"}),
    )
    contact_name = forms.CharField(
        label="Your name",
        max_length=120,
        widget=forms.TextInput(attrs={"placeholder": "Priya Sharma", "autocomplete": "name"}),
    )
    email = forms.EmailField(
        label="Work email",
        widget=forms.EmailInput(attrs={"placeholder": "priya@acme.com", "autocomplete": "email"}),
    )
    phone = forms.CharField(
        label="Phone",
        max_length=32,
        required=False,
        widget=forms.TextInput(attrs={"placeholder": "Optional", "autocomplete": "tel"}),
    )
    slug = forms.CharField(
        label="Workspace address",
        max_length=31,
        help_text="Letters, numbers, and underscores. This becomes your sign-in address.",
        widget=forms.TextInput(
            attrs={
                "placeholder": "acme",
                "autocomplete": "off",
                "autocapitalize": "none",
                "spellcheck": "false",
            }
        ),
    )
    plan = forms.ModelChoiceField(
        label="Plan",
        queryset=Plan.objects.none(),
        required=False,
        empty_label="No preference",
    )
    seat_count = forms.IntegerField(
        label="Employees",
        min_value=1,
        required=False,
        widget=forms.NumberInput(attrs={"placeholder": "How many people?"}),
    )
    message = forms.CharField(
        label="Anything we should know?",
        widget=forms.Textarea(
            attrs={
                "rows": 4,
                "placeholder": "What you use today, when you want to start, anything else.",
            }
        ),
        required=False,
        max_length=2000,
    )

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["plan"].queryset = sellable_plans().filter(status=Plan.Status.ACTIVE)
        _use_plain_option_template(self.fields["plan"])

    def clean_slug(self):
        try:
            slug = validate_tenant_slug(self.cleaned_data["slug"])
        except TenantSlugError as exc:
            raise forms.ValidationError(str(exc)) from exc
        if Tenant.objects.filter(slug=slug).exists():
            raise forms.ValidationError("That workspace name is already in use.")
        return slug
