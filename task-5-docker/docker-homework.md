# Docker Homework: Hello World Applications

Six Hello World web applications, each one in its own folder with its own Dockerfile.
Every image was built, every container was started, and the page was opened in a browser
to confirm it rendered. The browser captures are in the `screenshots` folder.

## Folder structure

    task-5-docker/
      nodejs-app/     Express on Node.js
      python-app/     Flask on Python
      java-app/       Java, using the HTTP server bundled with the JDK
      Apache-app/     a static page served by Apache httpd
      React-app/      React built by Vite, served by Nginx
      nginx-app/      a static page served by Nginx
      screenshots/    browser captures of all six
      docker-homework.md

## The six at a glance

    App          Base image                    Container port   Host port
    nodejs-app   node:20-alpine                3000             3001
    python-app   python:3.12-slim              5000             5001
    java-app     eclipse-temurin:21, 2 stages  8080             8080
    Apache-app   httpd:2.4-alpine              80               8081
    nginx-app    nginx:1.27-alpine             80               8082
    React-app    node to build, nginx to serve 80               8083

Host ports 3000 and 5000 were already taken on my laptop, so the Node and Python apps
were published on 3001 and 5001 instead. Only the host side of the mapping moved; inside
their containers the apps still listen on their usual ports, because nothing about the
image changed.

## 1. nodejs-app

An Express server returning a Hello World page.

Files: `package.json`, `server.js`, `Dockerfile`, `.dockerignore`

    FROM node:20-alpine

    WORKDIR /app

    COPY package.json ./
    RUN npm install --omit=dev

    COPY server.js ./

    EXPOSE 3000
    CMD ["npm", "start"]

The reason `package.json` is copied by itself before the source: each instruction becomes
a cached layer, and a layer is only rebuilt when its inputs change. Copying the manifest
first means editing `server.js` reuses the cached `npm install` instead of downloading
everything again. `--omit=dev` skips dev dependencies, which have no business in a
runtime image.

`.dockerignore` excludes `node_modules`, so a local install on the host is never copied
into the build context and cannot shadow the one done inside the image.

    $ docker build -t nodejs-hello nodejs-app
    $ docker run -d --name node-hello -p 3001:3000 nodejs-hello

    $ docker logs node-hello
    > node server.js
    Node.js app listening on port 3000

    $ curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3001
    200

Screenshot: `screenshots/nodejs-app.png`

## 2. python-app

A Flask app serving the same page.

Files: `requirements.txt`, `app.py`, `Dockerfile`

    FROM python:3.12-slim

    WORKDIR /app

    COPY requirements.txt ./
    RUN pip install --no-cache-dir -r requirements.txt

    COPY app.py ./

    EXPOSE 5000
    CMD ["python", "app.py"]

The detail that matters here is in the Python, not the Dockerfile: `app.run` is given
`host="0.0.0.0"`. Flask's default is 127.0.0.1, and with that default the port mapping
looks like it is doing nothing, because nothing outside the container's own loopback can
reach the server. `--no-cache-dir` keeps pip's download cache out of the image layer.

    $ docker build -t python-hello python-app
    $ docker run -d --name py-hello -p 5001:5000 python-hello

    $ docker logs py-hello
     * Running on http://172.17.0.8:5000
    192.168.65.1 - - [01/Sep/2026 12:21:30] "GET / HTTP/1.1" 200 -

Screenshot: `screenshots/python-app.png`

## 3. java-app

A small server on `com.sun.net.httpserver`, which is part of the JDK, so there is no
build tool and no third party library to fetch.

Files: `HelloWorld.java`, `Dockerfile`

    # Stage 1: the JDK image has javac, so compile the source here
    FROM eclipse-temurin:21-jdk-alpine AS build
    WORKDIR /src
    COPY HelloWorld.java ./
    RUN javac HelloWorld.java

    # Stage 2: only a JRE is needed to run a compiled class, so ship that instead
    FROM eclipse-temurin:21-jre-alpine
    WORKDIR /app
    COPY --from=build /src/HelloWorld.class ./

    EXPOSE 8080
    CMD ["java", "HelloWorld"]

Two stages because the compiler is a build time requirement only. The image that actually
ships holds the compiled `.class` file and a JRE, and the JDK never reaches it.

    $ docker build -t java-hello java-app
    $ docker run -d --name jv-hello -p 8080:8080 java-hello

    $ docker logs jv-hello
    Java app listening on port 8080

Screenshot: `screenshots/java-app.png`

## 4. Apache-app

No application code whatsoever, just a static page copied into the official Apache image.

Files: `index.html`, `Dockerfile`

    FROM httpd:2.4-alpine

    COPY index.html /usr/local/apache2/htdocs/index.html

    EXPOSE 80

There is deliberately no `CMD`. The base image already starts httpd in the foreground,
and adding a `CMD` would only replace something that works. A Dockerfile of two real
instructions is a reminder that an image does not have to contain code to be useful.

    $ docker build -t apache-hello Apache-app
    $ docker run -d --name ap-hello -p 8081:80 apache-hello

Screenshot: `screenshots/Apache-app.png`

## 5. nginx-app

The same approach as Apache. The only thing that differs is the directory the server
publishes from.

Files: `index.html`, `Dockerfile`

    FROM nginx:1.27-alpine

    COPY index.html /usr/share/nginx/html/index.html

    EXPOSE 80

    $ docker build -t nginx-hello nginx-app
    $ docker run -d --name ng-hello -p 8082:80 nginx-hello

Screenshot: `screenshots/nginx-app.png`

## 6. React-app

An actual React application scaffolded with Vite, compiled to static files and handed to
Nginx.

Files: `package.json`, `vite.config.js`, `index.html`, `src/main.jsx`, `src/App.jsx`,
`Dockerfile`, `.dockerignore`

    # Stage 1: compile the React source into plain static files
    FROM node:20-alpine AS build
    WORKDIR /app
    COPY package.json ./
    RUN npm install
    COPY . .
    RUN npm run build

    # Stage 2: a finished build is only HTML, CSS and JS, so nginx can serve it
    FROM nginx:1.27-alpine
    COPY --from=build /app/dist /usr/share/nginx/html

    EXPOSE 80

Of the six this is the most instructive pattern. Node and the entire `node_modules` tree
exist only to produce `dist/`. Once that directory exists the application is static
files, so the shipped image is Nginx plus a few dozen kilobytes: 76 MB, against the 200
MB plus that carrying a Node runtime would cost.

    $ docker build -t react-hello React-app
    $ docker run -d --name rc-hello -p 8083:80 react-hello

Something worth recording from checking this one: `curl` against the React app returns a
nearly empty document, just the `<div id="root">` and a script tag, because the markup is
produced by JavaScript in the browser. So a 200 from curl says the server works but says
nothing about whether the app renders, and this is the one app of the six that genuinely
had to be opened in a browser to verify. The screenshot is the evidence.

Screenshot: `screenshots/react-app.png`

## Building and running all six

    docker build -t nodejs-hello nodejs-app
    docker build -t python-hello python-app
    docker build -t java-hello   java-app
    docker build -t apache-hello Apache-app
    docker build -t nginx-hello  nginx-app
    docker build -t react-hello  React-app

    docker run -d --name node-hello -p 3001:3000 nodejs-hello
    docker run -d --name py-hello   -p 5001:5000 python-hello
    docker run -d --name jv-hello   -p 8080:8080 java-hello
    docker run -d --name ap-hello   -p 8081:80   apache-hello
    docker run -d --name ng-hello   -p 8082:80   nginx-hello
    docker run -d --name rc-hello   -p 8083:80   react-hello

### The images

    REPOSITORY      TAG       SIZE
    react-hello     latest    76.1MB
    nginx-hello     latest    75.9MB
    apache-hello    latest    105MB
    java-hello      latest    286MB
    python-hello    latest    234MB
    nodejs-hello    latest    209MB

The two static images are the smallest, at essentially the size of their base image. The
React image is in the same class despite being a real application, which is the
multi-stage build paying off.

### The containers

    NAMES        IMAGE           STATUS          PORTS
    py-hello     python-hello    Up 3 seconds    0.0.0.0:5001->5000/tcp
    node-hello   nodejs-hello    Up 3 seconds    0.0.0.0:3001->3000/tcp
    rc-hello     react-hello     Up 28 seconds   0.0.0.0:8083->80/tcp
    ng-hello     nginx-hello     Up 28 seconds   0.0.0.0:8082->80/tcp
    ap-hello     apache-hello    Up 28 seconds   0.0.0.0:8081->80/tcp
    jv-hello     java-hello      Up 28 seconds   0.0.0.0:8080->8080/tcp

### Verifying all six

    $ for port in 3001 5001 8080 8081 8082 8083; do
        curl -s -o /dev/null -w "$port -> %{http_code}\n" http://localhost:$port
      done

    === Node.js  http://localhost:3001 ===
    HTTP status: 200   <h1>Hello World</h1>

    === Python  http://localhost:5001 ===
    HTTP status: 200   <h1>Hello World</h1>

    === Java  http://localhost:8080 ===
    HTTP status: 200   <h1>Hello World</h1>

    === Apache  http://localhost:8081 ===
    HTTP status: 200   <h1>Hello World</h1>

    === Nginx  http://localhost:8082 ===
    HTTP status: 200   <h1>Hello World</h1>

    === React  http://localhost:8083 ===
    HTTP status: 200   (markup is built in the browser, see the screenshot)

### Cleanup

    docker rm -f node-hello py-hello jv-hello ap-hello ng-hello rc-hello
    docker rmi nodejs-hello python-hello java-hello apache-hello nginx-hello react-hello

## What I took from building these

A Dockerfile is nothing more than the setup you would otherwise do by hand, written down
so it can be repeated: choose a base image, bring the code in, install what it depends
on, note the port, and state the command that starts it.

`EXPOSE` is documentation and opens nothing. `-p` on `docker run` is what actually
publishes a port, and it reads host port on the left, container port on the right. That
is also why the Node app can listen on 3000 internally and be reached on 3001 from the
laptop.

The application has to listen on `0.0.0.0`. Binding to `127.0.0.1` means the only client
that can reach it is something inside the same container, which makes a correct port
mapping look broken.

Layer order is a real performance decision, not a style preference. Dependency manifest
first, install, then source, so that editing code does not reinstall the world.

Multi-stage builds matter whenever the build produces something different in kind from
its input. React compiling to static files and Java compiling to a class file both
qualify, and the React image came out at 76 MB because of it. Where the build output is
much the same as the input, the saving is small, which is the point the next task
examines.

The two static apps need no `CMD` at all, since their base images already start a server.
The three code based apps do need one, because otherwise the container has nothing to
run and exits immediately.
