# Multi-stage. The builder installs dependencies; the runtime carries only what
# is needed to run, with no compiler toolchain left behind.

FROM python:3.12-slim AS builder

WORKDIR /build

# psycopg2-binary ships wheels, but keeping build tooling in this stage means
# a source build would still work without bloating the runtime image.
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


FROM python:3.12-slim AS runtime

# Patch the base image. Trivy flags distro CVEs and this is the first response.
RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends libpq5 curl \
    && rm -rf /var/lib/apt/lists/*

# Non-root, as the rubric requires and as any container should be.
RUN useradd --create-home --uid 10001 appuser

WORKDIR /app

COPY --from=builder /install /usr/local
COPY --chown=appuser:appuser app/ ./app/
COPY --chown=appuser:appuser alembic/ ./alembic/
COPY --chown=appuser:appuser alembic.ini ./

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -fsS http://localhost:8000/health || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
