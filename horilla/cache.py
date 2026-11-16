"""Cache keys are per tenant. A missing tenant must not share the control cache."""

from django.conf import settings

from horilla.isolation import active_tenant_slug, get_cache_scope


class CacheNamespaceError(RuntimeError):
    """A cache operation ran without a tenant or the control plane."""


def tenant_cache_key(key, key_prefix, version):
    if not getattr(settings, "HORILLA_MULTITENANT", False):
        return f"horilla:{version}:{key}"
    namespace = get_cache_scope()
    if namespace == "control":
        prefix = "control"
    else:
        prefix = active_tenant_slug()
    if not prefix:
        raise CacheNamespaceError("Refusing to use the cache without a tenant.")
    return f"horilla:{prefix}:{version}:{key}"
