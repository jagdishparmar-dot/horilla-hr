# syntax=docker/dockerfile:1
#
# Multi-stage image for Horilla HR.
#
# Build hang notes (Docker Desktop / slow links):
# - apt can stall forever on deb.debian.org Packages indexes (IPv6/CDN).
#   We force IPv4, short timeouts, and fall back to Aliyun if official fails.
# - Shared debian-base so BuildKit does not fetch the index twice in parallel.
# - en_core_web_sm is a GitHub release wheel; install it in a separate pip
#   step with a longer timeout so a stalled asset does not redo the whole
#   requirements install.

FROM python:3.12-slim AS debian-base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Optional override: docker build --build-arg APT_MIRROR=mirrors.aliyun.com
# When set, skip the official mirror entirely (useful behind bad CDN routes).
ARG APT_MIRROR=

RUN printf '%s\n' \
        'Acquire::Retries "2";' \
        'Acquire::http::Timeout "15";' \
        'Acquire::https::Timeout "15";' \
        'Acquire::ftp::Timeout "15";' \
        'Acquire::ForceIPv4 "true";' \
        'Acquire::http::Pipeline-Depth "0";' \
        > /etc/apt/apt.conf.d/99docker-network \
    && rewrite_mirror() { \
         mirror="$1"; \
         if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
           sed -i \
             -e "s|http://deb.debian.org/debian-security|http://${mirror}/debian-security|g" \
             -e "s|https://deb.debian.org/debian-security|http://${mirror}/debian-security|g" \
             -e "s|http://deb.debian.org|http://${mirror}|g" \
             -e "s|https://deb.debian.org|http://${mirror}|g" \
             /etc/apt/sources.list.d/debian.sources; \
         elif [ -f /etc/apt/sources.list ]; then \
           sed -i \
             -e "s|deb.debian.org|${mirror}|g" \
             -e "s|security.debian.org|${mirror}|g" \
             /etc/apt/sources.list; \
         fi; \
       } \
    && if [ -n "$APT_MIRROR" ]; then \
         echo "APT: using mirror ${APT_MIRROR}"; \
         rewrite_mirror "$APT_MIRROR"; \
         printf '%s\n' 'Acquire::Retries "5";' 'Acquire::http::Timeout "20";' 'Acquire::https::Timeout "20";' \
           > /etc/apt/apt.conf.d/99docker-network-retry; \
         apt-get update; \
       elif apt-get update; then \
         echo "APT: official Debian mirror OK"; \
       else \
         echo "APT: official mirror failed; falling back to mirrors.aliyun.com"; \
         rewrite_mirror "mirrors.aliyun.com"; \
         printf '%s\n' 'Acquire::Retries "5";' 'Acquire::http::Timeout "20";' 'Acquire::https::Timeout "20";' \
           > /etc/apt/apt.conf.d/99docker-network-retry; \
         apt-get update; \
       fi
# Intentionally no `apt-get upgrade`: it re-downloads large indexes/packages and
# is a common "stuck forever" point. Security patches come from refreshed base
# tags and the pinned runtime packages below.

# ---------------------------------------------------------------------------
# Builder: compile/install Python deps into a venv
# ---------------------------------------------------------------------------
FROM debian-base AS builder

# Runtime wheels cover most deps on 3.12; keep a minimal toolchain for sdists
# (pyzk) and any missing binary wheels.
RUN apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
        libjpeg-dev \
        zlib1g-dev \
        libffi-dev \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH" \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=120 \
    PIP_RETRIES=5 \
    PIP_PREFER_BINARY=1

COPY requirements.txt .

ARG SPACY_MODEL_VERSION=3.8.0
ARG SPACY_MODEL_URL=https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl

# Drop test-only and the GitHub direct URL so a spaCy asset stall does not
# invalidate the whole pip layer. coverage is not needed at runtime.
RUN --mount=type=cache,target=/root/.cache/pip \
    grep -vE '^(coverage|en_core_web_sm[[:space:]])' requirements.txt > /tmp/requirements.docker.txt \
    && pip install --upgrade pip \
    && pip install --no-cache-dir -r /tmp/requirements.docker.txt

# Separate layer + longer timeout: release-assets.githubusercontent.com often
# stalls on Docker Desktop / constrained links.
RUN --mount=type=cache,target=/root/.cache/pip \
    PIP_DEFAULT_TIMEOUT=300 pip install --no-cache-dir \
        "en_core_web_sm @ ${SPACY_MODEL_URL}" \
    && pip show en_core_web_sm | grep -qx "Version: ${SPACY_MODEL_VERSION}" \
    || { echo "ERROR: expected en_core_web_sm ${SPACY_MODEL_VERSION}, got:"; \
         pip show en_core_web_sm | grep -i version; exit 1; }

# ---------------------------------------------------------------------------
# Production runtime
# ---------------------------------------------------------------------------
FROM debian-base AS production

ENV PATH="/opt/venv/bin:$PATH" \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get install -y --no-install-recommends \
        libpq5 \
        libjpeg62-turbo \
        zlib1g \
        libcairo2 \
        libpango-1.0-0 \
        libgdk-pixbuf-xlib-2.0-0 \
        libxml2 \
        libxslt1.1 \
        libffi8 \
        curl \
        netcat-openbsd \
        gettext \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Base image system site-packages (outside the venv) still ship old
# setuptools/msgpack that image scanners flag. Upgrade those in place.
RUN /usr/local/bin/python -m pip install --no-cache-dir --upgrade \
        "setuptools>=78.1.1" "msgpack>=1.2.1"

RUN useradd --create-home --uid 1000 appuser

COPY --from=builder --chown=appuser:appuser /opt/venv /opt/venv

WORKDIR /app

COPY --chown=appuser:appuser . .

# Compile gettext catalogs (.po -> .mo). Not done in the repo; without this
# every non-English locale silently falls back to English.
RUN find . -name '*.po' -execdir sh -c 'msgfmt "$1" -o "${1%.po}.mo"' _ {} \;

COPY --chown=appuser:appuser docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN mkdir -p staticfiles media \
    && chown appuser:appuser staticfiles media

USER appuser

ARG VERSION=dev
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="Horilla HR" \
      org.opencontainers.image.description="Free and open source HR software" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/horilla/horilla-hr" \
      org.opencontainers.image.url="https://www.horilla.com" \
      org.opencontainers.image.documentation="https://docs.horilla.com" \
      org.opencontainers.image.vendor="Horilla" \
      org.opencontainers.image.licenses="LGPL-2.1"

EXPOSE 8000

# First boot: migrate + collectstatic before gunicorn binds (~5 min empty DB).
HEALTHCHECK --interval=30s --timeout=30s --start-period=10m --retries=3 \
    CMD curl -f http://localhost:8000/health/ || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["gunicorn", "horilla.wsgi:application", "--config", "docker/gunicorn.conf.py"]
