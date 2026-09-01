FROM nginx:1.27-alpine

# The default nginx.conf serves this directory, so no config change is needed
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80

# No CMD either, nginx is the base image's own entrypoint.
