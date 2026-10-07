FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


FROM python:3.12-slim AS runtime

# Patch the base image. A scanner will flag known CVEs in the distro packages,
# and this is the first thing to do about them.
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 appuser

WORKDIR /app
COPY --from=builder /install /usr/local
COPY app/ ./app/

USER appuser

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request;urllib.request.urlopen('http://localhost:5000/health')"

CMD ["python", "-m", "flask", "--app", "app.app", "run", "--host", "0.0.0.0", "--port", "5000"]
