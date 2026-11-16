from django import forms

from control.naming import TenantSlugError, validate_tenant_slug


class LoginForm(forms.Form):
    email = forms.EmailField(label="Email")
    password = forms.CharField(label="Password", widget=forms.PasswordInput)


class TenantCreateForm(forms.Form):
    name = forms.CharField(label="Company name", max_length=200)
    slug = forms.CharField(label="Slug", max_length=31)
    admin_name = forms.CharField(label="Admin name", max_length=150)
    admin_email = forms.EmailField(label="Admin email")
    admin_password = forms.CharField(
        label="Temporary password",
        min_length=8,
        widget=forms.PasswordInput,
    )
    plan = forms.CharField(label="Plan", max_length=64, required=False)

    def clean_slug(self):
        try:
            return validate_tenant_slug(self.cleaned_data["slug"])
        except TenantSlugError as exc:
            raise forms.ValidationError(str(exc)) from exc


class DeleteConfirmForm(forms.Form):
    confirm_slug = forms.CharField(label="Type the slug to delete")


class RestoreForm(forms.Form):
    dump_name = forms.CharField(label="Dump file name", max_length=200)


class OperatorCreateForm(forms.Form):
    email = forms.EmailField(label="Email")
    password = forms.CharField(
        label="Password",
        min_length=8,
        widget=forms.PasswordInput,
    )
    is_staff = forms.BooleanField(label="Staff", required=False, initial=True)

    def clean_email(self):
        return self.cleaned_data["email"].strip().lower()
