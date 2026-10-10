# syntax=docker/dockerfile:1
# Standard-library-only service, so a single slim stage is enough.
FROM python:3.14-slim

ARG APP_VERSION=dev
ARG GIT_COMMIT=unknown

LABEL org.opencontainers.image.source="https://github.com/martineh4/shipfast-status-api" \
      org.opencontainers.image.description="ShipFast internal status-check API"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION} \
    GIT_COMMIT=${GIT_COMMIT} \
    PORT=8080

WORKDIR /app
COPY app/status_api.py .

# Numeric UID so Kubernetes runAsNonRoot can verify it without /etc/passwd.
USER 10001:10001
EXPOSE 8080

CMD ["python", "status_api.py"]
