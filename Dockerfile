# Dockerfile

```dockerfile
# syntax=docker/dockerfile:1

###############################################################################
# Stage 1: dependency installation (isolated for layer caching)
###############################################################################
FROM python:3.11-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt ./
RUN pip install --prefix=/install -r requirements.txt

###############################################################################
# Stage 2: production runtime
###############################################################################
FROM python:3.11-slim AS runtime

LABEL org.opencontainers.image.title="ShopSphere" \
      org.opencontainers.image.description="Flask + SQLite e-commerce marketplace" \
      org.opencontainers.image.licenses="MIT"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    SHOP_HOST=0.0.0.0 \
    SHOP_PORT=5000

# Secrets are injected at runtime by the orchestrator; never baked into layers.
ARG SHOP_SECRET_KEY=""
ARG SHOP_ADMIN_PASSWORD=""
ARG SHOP_SMTP_PASSWORD=""

# curl is kept solely for the container health probe.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system appgrp \
    && useradd --system --gid appgrp --create-home --home-dir /home/appuser appuser

WORKDIR /app

# Copy pinned dependencies from the builder stage.
COPY --from=builder /install /usr/local

# Application source (templates, static assets and schema.sql live inside shop/).
COPY run.py ./
COPY shop ./shop

# Persistent state: SQLite database, uploaded product photos, secret key file
# and the optional file-mail outbox all live under the Flask instance folder.
RUN mkdir -p /app/instance \
    && chown -R appuser:appgrp /app

USER appuser

VOLUME ["/app/instance"]

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:${SHOP_PORT}/ >/dev/null || exit 1

# run.py bootstraps the schema + demo catalogue on first boot, then serves.
CMD ["python", "run.py"]