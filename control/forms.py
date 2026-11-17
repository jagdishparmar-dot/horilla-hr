from django import forms

from control.naming import TenantSlugError, validate_tenant_slug

INPUT_CLASS = "control-input"
CHECKBOX_CLASS = "control-check"


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


class TenantCreateForm(forms.Form):
    name = forms.CharField(
        label="Company name",
        max_length=200,
        widget=forms.TextInput(
            attrs={"class": INPUT_CLASS, "placeholder": "Northwind Labs", "autocomplete": "organization"},
        ),
    )
    slug = forms.CharField(
        label="Slug",
        max_length=31,
        help_text="Lowercase, 3–31 characters, starting with a letter. This becomes the host and the database name.",
        widget=forms.TextInput(
            attrs={"class": INPUT_CLASS, "placeholder": "northwind", "spellcheck": "false", "autocapitalize": "off"},
        ),
    )
    plan = forms.CharField(
        label="Plan",
        max_length=64,
        required=False,
        help_text="Optional label for your own records. It does not change what gets provisioned.",
        widget=forms.TextInput(attrs={"class": INPUT_CLASS, "placeholder": "standard"}),
    )

    def clean_slug(self):
        try:
            return validate_tenant_slug(self.cleaned_data["slug"])
        except TenantSlugError as exc:
            raise forms.ValidationError(str(exc)) from exc


class DeleteConfirmForm(forms.Form):
    confirm_slug = forms.CharField(
        label="Type the slug to delete",
        widget=forms.TextInput(attrs={"class": INPUT_CLASS, "autocomplete": "off"}),
    )


class RestoreForm(forms.Form):
    dump_name = forms.CharField(
        label="Dump file name",
        max_length=200,
        widget=forms.TextInput(attrs={"class": INPUT_CLASS}),
    )


class OperatorCreateForm(forms.Form):
    email = forms.EmailField(
        label="Email",
        widget=forms.EmailInput(attrs={"class": INPUT_CLASS}),
    )
    password = forms.CharField(
        label="Password",
        min_length=8,
        help_text="At least 8 characters. Share it with the operator through a private channel.",
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