from django.apps import AppConfig


class ControlConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "control"
    verbose_name = "Tenant control plane"

    def ready(self):
        from django.contrib.auth.signals import user_logged_in

        from control.sessions import stamp_tenant_session

        user_logged_in.connect(
            stamp_tenant_session,
            dispatch_uid="control.stamp_tenant_session",
        )
