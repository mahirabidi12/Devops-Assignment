# Multi-stage: the build stage installs dependencies, the runtime stage carries
# only what is needed to run. Same technique as task 6.

FROM python:3.12-slim AS builder

WORKDIR /build

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


FROM python:3.12-slim AS runtime

# Run as a non-root user. A container that does not need root should not have it.
RUN useradd --create-home --uid 10001 appuser

WORKDIR /app

COPY --from=builder /install /usr/local
COPY app/ ./app/

USER appuser

# No server here - this image is a library plus its entrypoint, exercised by the
# pipeline. A real service would EXPOSE a port and run a server.
ENTRYPOINT ["python", "-c", "from app.calculator import add; print('calculator image ok:', add(2, 3))"]
