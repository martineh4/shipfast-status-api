# syntax=docker/dockerfile:1

# --- test: run the unit tests on the same Python minor version as runtime ---
# The runtime image has no shell, so tests run here instead. The runtime stage
# copies the app from this stage, so the image can't be built if tests fail.
FROM python:3.13-slim AS test

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY app/status_api.py app/test_status_api.py ./
RUN python -m unittest -v

# --- runtime: distroless Python, no shell or package manager ---
FROM gcr.io/distroless/python3-debian13:nonroot

ARG APP_VERSION=dev
ARG GIT_COMMIT=unknown

LABEL org.opencontainers.image.title="shipfast-status-api" \
      org.opencontainers.image.description="ShipFast internal status-check API" \
      org.opencontainers.image.source="https://github.com/martineh4/shipfast-status-api" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION} \
    GIT_COMMIT=${GIT_COMMIT} \
    PORT=8080

WORKDIR /app
COPY --from=test /app/status_api.py .

# Numeric UID so Kubernetes runAsNonRoot can verify it without /etc/passwd.
USER 10001:10001
EXPOSE 8080

# For `docker run` and Compose. Kubernetes ignores this and uses the probes in
# deploy/base/deployment.yaml. Exec form, since there's no shell or curl.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/usr/bin/python3", "-c", "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ.get('PORT', '8080') + '/healthz', timeout=2)"]

ENTRYPOINT ["/usr/bin/python3", "/app/status_api.py"]
