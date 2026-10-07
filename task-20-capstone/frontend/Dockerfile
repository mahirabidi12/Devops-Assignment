# Multi-stage. Node builds the static bundle; the runtime is nginx with only
# the built assets. The node_modules tree never reaches the final image.

FROM node:22-alpine AS builder

WORKDIR /build

COPY package.json ./
RUN npm install

COPY . .
RUN npm run build


# Pinned to the Alpine 3.24 variant deliberately. The 1.27-alpine tag is built
# on Alpine 3.21, whose package repository does not carry the patched versions
# of libssl3, libcrypto3, libexpat, libpng and libxml2 - Trivy found 42 fixable
# HIGH/CRITICAL CVEs there, and `apk upgrade` could not fix them because the
# fixes simply are not in 3.21's repo. Moving the base forward is the fix.
FROM nginxinc/nginx-unprivileged:1.30-alpine3.24 AS runtime

# Still worth upgrading, to pick up anything patched since the image was built.
USER root
RUN apk upgrade --no-cache

# nginx-unprivileged runs as uid 101 and listens on 8080 rather than 80, so no
# root is needed at runtime. Using it is simpler and safer than patching the
# standard nginx image to drop privileges.
USER 101

COPY --from=builder /build/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/templates/default.conf.template

# The template is rendered at startup with these values substituted, so the
# same image works in compose and in Kubernetes with different backends.
ENV BACKEND_HOST=backend \
    BACKEND_PORT=8000

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:8080/healthz || exit 1
