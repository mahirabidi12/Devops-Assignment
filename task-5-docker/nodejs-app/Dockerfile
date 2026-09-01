FROM node:20-alpine

WORKDIR /app

# package.json goes in on its own first. Docker caches layers, so as long as
# the dependencies are unchanged this install is reused on every later build.
COPY package.json ./
RUN npm install --omit=dev

# The source is copied afterwards, because it changes far more often.
COPY server.js ./

EXPOSE 3000
CMD ["npm", "start"]
