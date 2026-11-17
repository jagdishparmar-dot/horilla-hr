"""
Authentication utilities for the API
"""

from rest_framework import authentication
from rest_framework.exceptions import AuthenticationFailed


class RejectBasicAuthentication(authentication.BaseAuthentication):
    """
    Explicitly reject HTTP Basic Auth across the API with a clear error message.
    """

    def authenticate(self, request):
        auth_header = request.META.get("HTTP_AUTHORIZATION", "")
        if auth_header.startswith("Basic "):
            raise AuthenticationFailed(
                "Basic authentication is disabled. Use Bearer token (JWT) in the Authorization header."
            )
        return None
