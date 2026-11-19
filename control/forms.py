from django import forms
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError

from control.catalog import UNASSIGNED, sellable_plans
from control.models import Addon, Operator, Plan, Tenant
from control.pricing import addon_fits, required_addon_codes
from control.naming import TenantSlugError, validate_tenant_slug

INPUT_CLASS = "control-input"
CHECKBOX_CLASS = "control-check"


def validate_operator_password(password: str, email: str) -> str:
    """Django's AUTH_PASSWORD_VALIDATORS, including similarity to the email.

    An unsaved Operator supplies the email field the similarity check reads.
    """
    user = Operator(email=email or "")
    try:
        validate_password(password, user=user)
    except ValidationError as exc:
        raise forms.ValidationError(exc.messages) from exc
    return password


class LoginForm(forms.Form):
    email = forms.EmailField(
        label="Email",
        widget=forms.EmailInput(attrs={"class": INPUT_CLASS, "autocomplete": "username"}),
    )
    password = forms.CharField(
        label="Password",
        widget=forms.PasswordInput(
            attrs={"class": INPUT_CLASS, "autocomplete": "current-password"},
        ),
    )


class PlanSelect(forms.Select):
    def create_option(self, name, value, label, selected, index, subindex=None, attrs=None):
        option = super().create_option(
            name, value, label, selected, index, subindex=subindex, attrs=attrs
        )
        plan = getattr(value, "instance", None)
        if plan is not None:
            option["attrs"]["data-seats"] = plan.seat_cap or 25
        return option


class TenantCreateForm(forms.Form):
    name = forms.CharField(
        label="Company name",
        max_length=200,
        widget=forms.TextInput(
            attrs={"class": INPUT_CLASS, "placeholder": "Northwind Labs", "autocomplete": "organization"},
        ),
    )
    industry = forms.CharField(
        label="Industry",
        max_length=120,
        required=False,
        widget=forms.TextInput(attrs={"class": INPUT_CLASS, "placeholder": "Manufacturing"}),
    )
    admin_name = forms.CharField(
        label="Admin name",
        max_length=200,
        required=False,
        help_text="Customer contact. This does not create a Horilla login.",
        widget=forms.TextInput(attrs={"class": INPUT_CLASS, "autocomplete": "name"}),
    )
    admin_email = forms.EmailField(
        label="Admin email",
        required=False,
        widget=forms.EmailInput(attrs={"class": INPUT_CLASS, "autocomplete": "email"}),
    )
    slug = forms.CharField(
        label="Slug",
        max_length=31,
        help_text="Lowercase, 3–31 characters, starting with a letter. This becomes the host and the database name.",
        widget=forms.TextInput(
            attrs={"class": INPUT_CLASS, "placeholder": "northwind", "spellcheck": "false", "autocapitalize": "off"},
        ),
    )
    plan = forms.ModelChoiceField(
        label="Plan",
        queryset=Plan.objects.none(),
        to_field_name="code",
        empty_label=None,
        widget=PlanSelect(attrs={"class": INPUT_CLASS, "data-plan-select": "true"}),
    )
    cadence = forms.ChoiceField(
        label="Billing cadence",
        choices=Tenant.Cadence.choices,
        initial=Tenant.Cadence.MONTHLY,
        widget=forms.Select(attrs={"class": INPUT_CLASS}),
    )
    seats = forms.IntegerField(
        label="Seats",
        min_value=1,
        help_text="Stored as the seat limit. Storage limit is this count times the plan's GB per seat. A capped plan starts at its cap; Enterprise starts at 25.",
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "data-seat-input": "true", "min": "1"}),
    )
    module_employee_records = forms.BooleanField(
        label="Employee records",
        required=False,
        initial=True,
        widget=forms.CheckboxInput(attrs={"class": CHECKBOX_CLASS}),
    )
    module_payroll_engine = forms.BooleanField(
        label="Payroll engine",
        required=False,
        initial=True,
        widget=forms.CheckboxInput(attrs={"class": CHECKBOX_CLASS}),
    )
    module_performance_reviews = forms.BooleanField(
        label="Performance reviews",
        required=False,
        initial=True,
        widget=forms.CheckboxInput(attrs={"class": CHECKBOX_CLASS}),
    )
    start_as_trial = forms.BooleanField(
        label="Start as trial",
        required=False,
        help_text="The workspace stays routable and is marked trialing for 14 days after activation.",
        widget=forms.CheckboxInput(attrs={"class": CHECKBOX_CLASS}),
    )

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        sellable = sellable_plans()
        self.fields["plan"].queryset = sellable
        if not self.is_bound:
            starter = sellable.filter(code="starter").first() or sellable.first()
            if starter is not None:
                self.fields["plan"].initial = starter.code
                self.fields["seats"].initial = starter.seat_cap or 25
            else:
                self.fields["seats"].initial = 25

    def clean_slug(self):
        try:
            return validate_tenant_slug(self.cleaned_data["slug"])
        except TenantSlugError as exc:
            raise forms.ValidationError(str(exc)) from exc

    def clean_plan(self):
        plan = self.cleaned_data.get("plan")
        if plan is None or plan.code == UNASSIGNED or not plan.is_active:
            raise forms.ValidationError("Choose a sellable plan.")
        return plan

    def clean(self):
        cleaned = super().clean()
        plan = cleaned.get("plan")
        seats = cleaned.get("seats")
        if plan is not None and seats is not None and plan.seat_cap is not None and seats > plan.seat_cap:
            self.add_error("seats", f"{plan.name} allows up to {plan.seat_cap} seats.")
        return cleaned


class QuoteForm(forms.Form):
    plan = forms.ModelChoiceField(
        label="Plan",
        queryset=Plan.objects.none(),
        to_field_name="code",
        empty_label=None,
        widget=forms.Select(attrs={"class": INPUT_CLASS}),
    )
    cadence = forms.ChoiceField(
        label="Cadence",
        choices=Tenant.Cadence.choices,
        initial=Tenant.Cadence.ANNUAL,
        widget=forms.Select(attrs={"class": INPUT_CLASS}),
    )
    seats = forms.IntegerField(
        label="Seats",
        min_value=0,
        initial=10,
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "0"}),
    )
    addons = forms.ModelMultipleChoiceField(
        label="Add-ons",
        queryset=Addon.objects.none(),
        to_field_name="code",
        required=False,
        widget=forms.CheckboxSelectMultiple(attrs={"class": CHECKBOX_CLASS}),
    )

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["plan"].queryset = sellable_plans()
        self.fields["addons"].queryset = Addon.objects.filter(is_active=True).order_by(
            "sort_order", "name"
        )
        if not self.is_bound:
            self.fields["plan"].initial = "growth"

    def clean(self):
        cleaned = super().clean()
        plan = cleaned.get("plan")
        addons = cleaned.get("addons")
        if plan is None or addons is None:
            return cleaned
        chosen = []
        for addon in addons:
            if not addon_fits(addon, plan):
                self.add_error("addons", f"{addon.name} is not available on {plan.name}.")
                continue
            chosen.append(addon)
        required = set(required_addon_codes(plan))
        have = {addon.code for addon in chosen}
        missing = required - have
        if missing:
            chosen.extend(list(Addon.objects.filter(code__in=missing, is_active=True)))
        cleaned["addons"] = chosen
        return cleaned


class SubscriptionForm(forms.Form):
    plan = forms.ModelChoiceField(
        label="Plan",
        queryset=Plan.objects.none(),
        to_field_name="code",
        empty_label=None,
        widget=forms.Select(attrs={"class": INPUT_CLASS}),
    )
    cadence = forms.ChoiceField(
        label="Billing cadence",
        choices=Tenant.Cadence.choices,
        widget=forms.Select(attrs={"class": INPUT_CLASS}),
    )
    addons = forms.ModelMultipleChoiceField(
        label="Add-ons",
        queryset=Addon.objects.none(),
        to_field_name="code",
        required=False,
        widget=forms.CheckboxSelectMultiple(attrs={"class": CHECKBOX_CLASS}),
    )

    def __init__(self, *args, tenant, **kwargs):
        self.tenant = tenant
        super().__init__(*args, **kwargs)
        self.fields["plan"].queryset = sellable_plans()
        current_ids = []
        if tenant.pk:
            current_ids = list(tenant.addons.values_list("pk", flat=True))
        self.fields["addons"].queryset = Addon.objects.filter(is_active=True).order_by(
            "sort_order", "name"
        )
        if current_ids:
            self.fields["addons"].queryset = (
                Addon.objects.filter(is_active=True) | Addon.objects.filter(pk__in=current_ids)
            ).distinct().order_by("sort_order", "name")
        if not self.is_bound:
            if tenant.plan_fk_id and tenant.plan_fk.code != UNASSIGNED and tenant.plan_fk.is_active:
                self.fields["plan"].initial = tenant.plan_fk.code
            elif tenant.plan_fk_id and tenant.plan_fk.code != UNASSIGNED:
                self.fields["plan"].queryset = (
                    sellable_plans() | Plan.objects.filter(pk=tenant.plan_fk_id)
                ).distinct().order_by("sort_order", "code")
                self.fields["plan"].initial = tenant.plan_fk.code
            self.fields["cadence"].initial = tenant.cadence
            self.fields["addons"].initial = list(
                tenant.addons.values_list("code", flat=True)
            )

    def clean(self):
        cleaned = super().clean()
        plan = cleaned.get("plan")
        if (
            plan is not None
            and plan.seat_cap is not None
            and self.tenant.seat_limit > plan.seat_cap
        ):
            self.add_error("plan", f"{plan.name} allows up to {plan.seat_cap} seats.")
        if plan is None:
            return cleaned
        if not plan.is_active and plan.pk != self.tenant.plan_fk_id:
            self.add_error("plan", "That plan is not available.")
        addons = list(cleaned.get("addons") or [])
        current = set(self.tenant.addons.values_list("code", flat=True))
        kept = []
        for addon in addons:
            already = addon.code in current
            if not addon.is_active and not already:
                self.add_error("addons", f"{addon.name} is not available.")
                continue
            if not already and not addon_fits(addon, plan):
                self.add_error("addons", f"{addon.name} is not available on {plan.name}.")
                continue
            kept.append(addon)
        have = {addon.code for addon in kept}
        for code in required_addon_codes(plan):
            if code not in have:
                extra = Addon.objects.filter(code=code, is_active=True).first()
                if extra is not None:
                    kept.append(extra)
        cleaned["addons"] = kept
        return cleaned


class DeleteConfirmForm(forms.Form):
    confirm_slug = forms.CharField(
        label="Type the slug to delete",
        widget=forms.TextInput(attrs={"class": INPUT_CLASS, "autocomplete": "off"}),
    )


class RestoreForm(forms.Form):
    dump_name = forms.ChoiceField(
        label="Backup",
        widget=forms.Select(attrs={"class": INPUT_CLASS}),
    )

    def __init__(self, dumps=None, *args, **kwargs):
        super().__init__(*args, **kwargs)
        choices = []
        for entry in dumps or []:
            when = entry.get("last_modified")
            stamp = when.strftime("%Y-%m-%d %H:%M") if hasattr(when, "strftime") else ""
            size = int(entry.get("size") or 0)
            label = f"{entry['name']} · {size} bytes"
            if stamp:
                label = f"{label} · {stamp}"
            choices.append((entry["name"], label))
        self.fields["dump_name"].choices = choices


class OperatorCreateForm(forms.Form):
    email = forms.EmailField(
        label="Email",
        widget=forms.EmailInput(attrs={"class": INPUT_CLASS}),
    )
    password = forms.CharField(
        label="Password",
        min_length=8,
        help_text="At least 8 characters, not a common password, and not based on the email. Share it through a private channel.",
        widget=forms.PasswordInput(attrs={"class": INPUT_CLASS, "autocomplete": "new-password"}),
    )
    is_staff = forms.BooleanField(
        label="Can manage operators",
        required=False,
        initial=True,
        help_text="Staff operators can create and deactivate other operators.",
        widget=forms.CheckboxInput(attrs={"class": CHECKBOX_CLASS}),
    )

    def clean_email(self):
        return self.cleaned_data["email"].strip().lower()

    def clean_password(self):
        email = (self.cleaned_data.get("email") or "").strip().lower()
        return validate_operator_password(self.cleaned_data["password"], email)


class OperatorPasswordForm(forms.Form):
    """An operator changing their own password. Requires the current one."""

    current_password = forms.CharField(
        label="Current password",
        widget=forms.PasswordInput(
            attrs={"class": INPUT_CLASS, "autocomplete": "current-password"}
        ),
    )
    new_password = forms.CharField(
        label="New password",
        min_length=8,
        help_text="At least 8 characters, not a common password, and not based on your email.",
        widget=forms.PasswordInput(
            attrs={"class": INPUT_CLASS, "autocomplete": "new-password"}
        ),
    )

    def __init__(self, operator, *args, **kwargs):
        self.operator = operator
        super().__init__(*args, **kwargs)

    def clean_current_password(self):
        raw = self.cleaned_data["current_password"]
        if not self.operator.check_password(raw):
            raise forms.ValidationError("Current password is not valid.")
        return raw

    def clean_new_password(self):
        return validate_operator_password(
            self.cleaned_data["new_password"], self.operator.email
        )


class SuspendForm(forms.Form):
    reason = forms.CharField(
        label="Suspension reason",
        min_length=1,
        max_length=200,
        widget=forms.TextInput(
            attrs={"class": INPUT_CLASS, "maxlength": "200", "placeholder": "Why is this workspace paused?"}
        ),
    )

    def clean_reason(self):
        reason = self.cleaned_data["reason"].strip()
        if not reason:
            raise forms.ValidationError("Enter a suspension reason.")
        return reason


class TenantQuotaForm(forms.Form):
    seat_limit = forms.IntegerField(
        label="Seat limit",
        min_value=1,
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "1"}),
    )
    storage_limit_gb = forms.IntegerField(
        label="Storage limit (GB)",
        min_value=0,
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "0"}),
    )
    module_employee_records = forms.BooleanField(
        label="Employee records",
        required=False,
        widget=forms.CheckboxInput(attrs={"class": CHECKBOX_CLASS}),
    )
    module_payroll_engine = forms.BooleanField(
        label="Payroll engine",
        required=False,
        widget=forms.CheckboxInput(attrs={"class": CHECKBOX_CLASS}),
    )
    module_performance_reviews = forms.BooleanField(
        label="Performance reviews",
        required=False,
        widget=forms.CheckboxInput(attrs={"class": CHECKBOX_CLASS}),
    )

    def __init__(self, *args, tenant, **kwargs):
        self.tenant = tenant
        super().__init__(*args, **kwargs)
        if not self.is_bound:
            self.fields["seat_limit"].initial = tenant.seat_limit
            self.fields["storage_limit_gb"].initial = tenant.storage_limit_gb
            self.fields["module_employee_records"].initial = tenant.module_employee_records
            self.fields["module_payroll_engine"].initial = tenant.module_payroll_engine
            self.fields["module_performance_reviews"].initial = tenant.module_performance_reviews

    def clean_seat_limit(self):
        seats = self.cleaned_data["seat_limit"]
        if seats < self.tenant.active_seats:
            raise forms.ValidationError(
                f"Seat limit cannot be below the snapshot of {self.tenant.active_seats}."
            )
        plan = self.tenant.plan_fk
        if plan is not None and plan.seat_cap is not None and seats > plan.seat_cap:
            raise forms.ValidationError(f"{plan.name} allows up to {plan.seat_cap} seats.")
        return seats

    def clean_storage_limit_gb(self):
        storage = self.cleaned_data["storage_limit_gb"]
        if storage < self.tenant.used_storage_gb:
            raise forms.ValidationError(
                f"Storage limit cannot be below the snapshot of {self.tenant.used_storage_gb} GB."
            )
        return storage


def _optional_cap(value):
    if value in (None, ""):
        return None
    return int(value)


class PlanCatalogForm(forms.Form):
    code = forms.SlugField(
        label="Code",
        max_length=32,
        widget=forms.TextInput(attrs={"class": INPUT_CLASS}),
    )
    name = forms.CharField(
        label="Name",
        max_length=64,
        widget=forms.TextInput(attrs={"class": INPUT_CLASS}),
    )
    description = forms.CharField(
        label="Description",
        required=False,
        widget=forms.Textarea(attrs={"class": INPUT_CLASS, "rows": 3}),
    )
    status = forms.ChoiceField(
        label="Status",
        choices=Plan.Status.choices,
        widget=forms.Select(attrs={"class": INPUT_CLASS}),
    )
    price_monthly = forms.IntegerField(
        label="Monthly price per seat",
        min_value=0,
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "0"}),
    )
    price_semiannual = forms.IntegerField(
        label="Semi-annual price per seat",
        min_value=0,
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "0"}),
    )
    price_annual = forms.IntegerField(
        label="Annual price per seat",
        min_value=0,
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "0"}),
    )
    seat_cap = forms.IntegerField(
        label="Seat cap",
        required=False,
        min_value=0,
        help_text="Leave empty for no cap.",
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "0"}),
    )
    storage_gb_per_seat = forms.IntegerField(
        label="Storage GB per seat",
        required=False,
        min_value=0,
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "0"}),
    )
    trial_days = forms.IntegerField(
        label="Trial days",
        min_value=0,
        initial=14,
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "0"}),
    )
    setup_fee = forms.IntegerField(
        label="Setup fee (INR)",
        min_value=0,
        initial=0,
        help_text="Added to the first invoice only. Whole rupees, exclusive of GST.",
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "0"}),
    )
    sort_order = forms.IntegerField(
        label="Display order",
        min_value=0,
        initial=0,
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "0"}),
    )

    def __init__(self, *args, instance=None, **kwargs):
        self.instance = instance
        super().__init__(*args, **kwargs)
        if instance is not None:
            self.fields["code"].disabled = True
            prices = {row.cadence: row.unit_rupees for row in instance.prices.all()}
            self.fields["code"].initial = instance.code
            self.fields["name"].initial = instance.name
            self.fields["description"].initial = instance.description
            self.fields["status"].initial = instance.status
            self.fields["price_monthly"].initial = prices.get("monthly", instance.monthly_price)
            self.fields["price_semiannual"].initial = prices.get("semiannual", instance.monthly_price * 6)
            self.fields["price_annual"].initial = prices.get("annual", 0)
            self.fields["seat_cap"].initial = instance.seat_cap
            self.fields["storage_gb_per_seat"].initial = instance.storage_gb_per_seat
            self.fields["trial_days"].initial = instance.trial_days
            self.fields["setup_fee"].initial = instance.setup_fee_rupees
            self.fields["sort_order"].initial = instance.sort_order

    def clean_code(self):
        code = (self.cleaned_data.get("code") or "").strip().lower()
        if code == UNASSIGNED:
            raise forms.ValidationError("Unassigned is reserved.")
        taken = Plan.objects.filter(code=code)
        if self.instance is not None:
            taken = taken.exclude(pk=self.instance.pk)
        if taken.exists():
            raise forms.ValidationError("A plan with this code already exists.")
        return code

    def save(self):
        from control.models import PlanPrice

        data = self.cleaned_data
        plan = self.instance or Plan(code=data["code"])
        plan.name = data["name"].strip()
        plan.description = data["description"]
        plan.status = data["status"]
        plan.is_active = data["status"] == Plan.Status.ACTIVE
        plan.monthly_price = data["price_monthly"]
        plan.seat_cap = _optional_cap(data.get("seat_cap"))
        plan.storage_gb_per_seat = _optional_cap(data.get("storage_gb_per_seat"))
        plan.trial_days = data["trial_days"]
        plan.setup_fee_rupees = data["setup_fee"]
        plan.sort_order = data["sort_order"]
        plan.save()
        for cadence, amount in (
            ("monthly", data["price_monthly"]),
            ("semiannual", data["price_semiannual"]),
            ("annual", data["price_annual"]),
        ):
            PlanPrice.objects.update_or_create(
                plan=plan,
                cadence=cadence,
                defaults={"unit_rupees": amount},
            )
        return plan


class AddonCatalogForm(forms.Form):
    code = forms.SlugField(
        label="Code",
        max_length=32,
        widget=forms.TextInput(attrs={"class": INPUT_CLASS}),
    )
    name = forms.CharField(
        label="Name",
        max_length=120,
        widget=forms.TextInput(attrs={"class": INPUT_CLASS}),
    )
    description = forms.CharField(
        label="Description",
        required=False,
        widget=forms.Textarea(attrs={"class": INPUT_CLASS, "rows": 3}),
    )
    is_active = forms.BooleanField(
        label="Active",
        required=False,
        initial=True,
        widget=forms.CheckboxInput(attrs={"class": CHECKBOX_CLASS}),
    )
    per_seat = forms.BooleanField(
        label="Price is per seat",
        required=False,
        widget=forms.CheckboxInput(attrs={"class": CHECKBOX_CLASS}),
    )
    required_on_plan = forms.BooleanField(
        label="Mandatory on compatible plans",
        required=False,
        widget=forms.CheckboxInput(attrs={"class": CHECKBOX_CLASS}),
    )
    price_monthly = forms.IntegerField(
        label="Monthly price",
        min_value=0,
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "0"}),
    )
    price_semiannual = forms.IntegerField(
        label="Semi-annual price",
        min_value=0,
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "0"}),
    )
    price_annual = forms.IntegerField(
        label="Annual price",
        min_value=0,
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "0"}),
    )
    sort_order = forms.IntegerField(
        label="Display order",
        min_value=0,
        initial=0,
        widget=forms.NumberInput(attrs={"class": INPUT_CLASS, "min": "0"}),
    )
    compatible_plans = forms.ModelMultipleChoiceField(
        label="Compatible plans",
        queryset=Plan.objects.none(),
        required=False,
        help_text="Leave empty to allow every plan.",
        widget=forms.CheckboxSelectMultiple(attrs={"class": CHECKBOX_CLASS}),
    )

    def __init__(self, *args, instance=None, **kwargs):
        self.instance = instance
        super().__init__(*args, **kwargs)
        self.fields["compatible_plans"].queryset = Plan.objects.exclude(code=UNASSIGNED).order_by(
            "sort_order", "code"
        )
        if instance is not None:
            self.fields["code"].disabled = True
            prices = {row.cadence: row.unit_rupees for row in instance.prices.all()}
            self.fields["code"].initial = instance.code
            self.fields["name"].initial = instance.name
            self.fields["description"].initial = instance.description
            self.fields["is_active"].initial = instance.is_active
            self.fields["per_seat"].initial = instance.per_seat
            self.fields["required_on_plan"].initial = instance.required
            self.fields["price_monthly"].initial = prices.get("monthly", instance.amount)
            self.fields["price_semiannual"].initial = prices.get("semiannual", instance.amount * 6)
            self.fields["price_annual"].initial = prices.get("annual", 0)
            self.fields["sort_order"].initial = instance.sort_order
            self.fields["compatible_plans"].initial = list(
                instance.compatible_plans.values_list("pk", flat=True)
            )

    def clean_code(self):
        code = (self.cleaned_data.get("code") or "").strip().lower()
        taken = Addon.objects.filter(code=code)
        if self.instance is not None:
            taken = taken.exclude(pk=self.instance.pk)
        if taken.exists():
            raise forms.ValidationError("An add-on with this code already exists.")
        return code

    def save(self):
        from control.models import AddonPrice

        data = self.cleaned_data
        addon = self.instance or Addon(code=data["code"])
        addon.name = data["name"].strip()
        addon.description = data["description"]
        addon.is_active = bool(data["is_active"])
        addon.per_seat = bool(data["per_seat"])
        addon.required = bool(data["required_on_plan"])
        addon.amount = data["price_monthly"]
        addon.sort_order = data["sort_order"]
        addon.save()
        addon.compatible_plans.set(data["compatible_plans"])
        for cadence, amount in (
            ("monthly", data["price_monthly"]),
            ("semiannual", data["price_semiannual"]),
            ("annual", data["price_annual"]),
        ):
            AddonPrice.objects.update_or_create(
                addon=addon,
                cadence=cadence,
                defaults={"unit_rupees": amount},
            )
        return addon
