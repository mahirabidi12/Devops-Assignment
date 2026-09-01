# Stage 1: compile the React source into plain static files
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

# Stage 2: a finished build is only HTML, CSS and JS, so nginx can serve it
# and Node is not needed at runtime at all.
FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80
