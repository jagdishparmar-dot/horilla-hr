# Gunicorn configuration for Horilla-HR
# This file provides advanced configuration options for the WSGI server

import multiprocessing
import os

# Bind settings
bind = f"0.0.0.0:{os.environ.get('PORT', '8000')}"
host = "0.0.0.0"
port = int(os.environ.get("PORT", "8000"))

# Worker settings
# `or`, not a get() default: docker-compose.prod.yml passes GUNICORN_WORKERS
# through as an empty string when .env leaves it unset, and int("") crashes.
workers = int(
    os.environ.get("GUNICORN_WORKERS")
    or max(2, min(multiprocessing.cpu_count() * 2 + 1, 8))
)
worker_class = "gthread"
threads = int(os.environ.get("GUNICORN_THREADS") or 4)
worker_connections = 1000
max_requests = 1000
max_requests_jitter = 50
# preload_app is disabled with gthread workers to avoid ORM connection issues
preload_app = False

# Timeout settings
timeout = int(os.environ.get("GUNICORN_TIMEOUT") or 120)
graceful_timeout = int(os.environ.get("GUNICORN_GRACEFUL_TIMEOUT") or 30)
# Keep-alive must outlive the reverse proxy's idle upstream timeout (Traefik:
# 90s). If gunicorn closes first, the proxy reuses a dead connection and the
# client gets an intermittent 502. nginx opens a fresh connection per request,
# so the short default is fine there; the Coolify compose sets 95.
keepalive = int(os.environ.get("GUNICORN_KEEPALIVE") or 5)
# Heartbeat files on the container's overlay filesystem can stall workers
# under I/O pressure and trigger spurious timeouts; /dev/shm is RAM-backed.
worker_tmp_dir = "/dev/shm"

# Logging
accesslog = "-"
errorlog = "-"
loglevel = os.environ.get("GUNICORN_LOG_LEVEL", "info")
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)s'

# Process naming
proc_name = "horilla-hrms"

# Server mechanics
pidfile = "/tmp/gunicorn.pid"
user = None  # Run as current user in container
group = None
tmp_upload_dir = None

# Development settings
reload = os.environ.get("GUNICORN_RELOAD", "false").lower() == "true"

# SSL settings (if needed)
# ssl_keyfile = os.environ.get('SSL_KEYFILE')
# ssl_certfile = os.environ.get('SSL_CERTFILE')
