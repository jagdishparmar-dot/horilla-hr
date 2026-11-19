"""Operator login lockout. django-axes never sees this login.

Failures are counted per (email, client IP) in the cache under the control
scope, so a tenant cache key cannot read or reset them. Five failures inside
the window lock the pair out. The first lock lasts 15 minutes; each further
lock doubles that, up to 24 hours. A correct password during a lockout is
still rejected, and the password hash is not checked while the lock holds.
"""

import hashlib
import time
from contextlib import contextmanager

from django.core.cache import cache

from horilla.isolation import activate_cache_scope, clear_cache_scope

THRESHOLD = 5
BASE_COOLDOWN = 15 * 60
MAX_COOLDOWN = 24 * 60 * 60
# Strikes expire if the pair stays clean for a week.
STRIKE_TTL = 7 * 24 * 60 * 60
# The failure counter itself lives only as long as one base window.
FAIL_TTL = BASE_COOLDOWN

INVALID_MESSAGE = "Email or password is not valid."
LOCKED_MESSAGE = "Email or password is not valid. Try again later."


def _identity(email: str, ip: str) -> str:
    raw = f"{(email or '').strip().lower()}|{(ip or '').strip()}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _fail_key(email: str, ip: str) -> str:
    return f"operator-lockout:fail:{_identity(email, ip)}"


def _lock_key(email: str, ip: str) -> str:
    return f"operator-lockout:lock:{_identity(email, ip)}"


def _strike_key(email: str, ip: str) -> str:
    return f"operator-lockout:strikes:{_identity(email, ip)}"


@contextmanager
def _control_cache():
    token = activate_cache_scope("control")
    try:
        yield cache
    finally:
        clear_cache_scope(token)


def cooldown_for_strikes(strikes: int) -> int:
    power = max(0, strikes - 1)
    return min(BASE_COOLDOWN * (2**power), MAX_COOLDOWN)


def is_locked(email: str, ip: str, now: float | None = None) -> bool:
    moment = time.time() if now is None else now
    with _control_cache() as store:
        until = store.get(_lock_key(email, ip))
    return bool(until) and float(until) > moment


def record_failure(email: str, ip: str, now: float | None = None) -> bool:
    """Count one failure. Returns True when this failure starts a lockout."""
    moment = time.time() if now is None else now
    with _control_cache() as store:
        fail_key = _fail_key(email, ip)
        try:
            count = store.incr(fail_key)
        except ValueError:
            store.set(fail_key, 1, timeout=FAIL_TTL)
            count = 1
        if count < THRESHOLD:
            return False
        strike_key = _strike_key(email, ip)
        try:
            strikes = store.incr(strike_key)
        except ValueError:
            store.set(strike_key, 1, timeout=STRIKE_TTL)
            strikes = 1
        else:
            store.touch(strike_key, STRIKE_TTL)
        cooldown = cooldown_for_strikes(strikes)
        store.set(_lock_key(email, ip), moment + cooldown, timeout=cooldown)
        store.delete(fail_key)
        return True


def clear_failures(email: str, ip: str) -> None:
    with _control_cache() as store:
        store.delete_many(
            [_fail_key(email, ip), _lock_key(email, ip), _strike_key(email, ip)]
        )
