# Security Policy

## Reporting a vulnerability

Report security issues privately rather than opening a public issue. Use GitHub's private
vulnerability reporting on this repository.

Expect an acknowledgement within 48 hours and an assessment within five working days.

## Supported versions

Only the latest release on `main` receives security fixes.

## What the pipeline enforces

Every push runs the checks in `.github-workflows/devsecops.yml`:

| Stage | Tool | Fails the build on |
|---|---|---|
| SAST | Bandit | any high-severity finding in our own code |
| SCA | pip-audit | any known vulnerability in a dependency |
| Secret scanning | Gitleaks | any credential committed to the repository |
| Image scanning | Trivy | any CRITICAL or HIGH CVE in the built image |

## Practices this project follows

- No secrets in source. Configuration is read from the environment.
- The container runs as a non-root user (`appuser`, uid 10001).
- The base image is patched during build.
- Dependencies are pinned to exact versions so a scan result is reproducible.
- `/api/config` reports whether secrets are configured, never their values.
