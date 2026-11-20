"""Hostname helpers for tenant routing.

Custom domains are not accepted in this phase. When one is verified later,
add its origin with ``origin_for_host`` rather than widening the cookie domain.
"""

from django.http.request import split_domain_port


def request_hostname(request) -> str:
    domain, _port = split_domain_port(request.get_host())
    return (domain or "").rstrip(".").lower()


def platform_host_patterns(platform_domain: str, dashboard_host: str) -> list[str]:
    """ALLOWED_HOSTS entries that cover tenant subdomains and the dashboard."""
    patterns = []
    domain = (platform_domain or "").strip().lower().rstrip(".")
    if domain:
        patterns.append(f".{domain}")
    dashboard = (dashboard_host or "").strip().lower().rstrip(".")
    if dashboard:
        patterns.append(dashboard)
    return patterns


def platform_csrf_origins(platform_domain: str) -> list[str]:
    """Origins for the platform domain, including the bare marketing host.

    A wildcard origin does not match the apex. The public request form posts
    there. Host-only cookies stay in place.
    """
    domain = (platform_domain or "").strip().lower().rstrip(".")
    if not domain:
        return []
    origins = [
        f"https://*.{domain}",
        f"http://*.{domain}",
        f"https://{domain}",
        f"http://{domain}",
    ]
    if domain == "localhost":
        origins.append("http://*.localhost:8000")
        origins.append("http://localhost:8000")
    return origins


def origin_for_host(host: str, scheme: str = "https") -> str:
    """One origin for a verified custom domain. Scheme is https unless told otherwise."""
    name = (host or "").strip().lower().rstrip(".")
    return f"{scheme}://{name}"
