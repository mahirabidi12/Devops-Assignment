FROM httpd:2.4-alpine

# Apache in this image serves out of htdocs, so the page just drops in there
COPY index.html /usr/local/apache2/htdocs/index.html

EXPOSE 80

# No CMD: the base image already launches httpd in the foreground.
