# Docker Multi-Stage Build Homework

Name: Mahir Abidi

Enrollment number: 24BCS10125

## Task 1: Run the multi-stage Dockerfile

### Where the app came from

The Dockerfile for this task is the one in the devops-hero repository:

    git clone https://github.com/Nency-Ravaliya/devops-heros.git
    cd devops-heros/session6-7-docker/multi-stage-dockerfile

I copied that folder into this repo as `multi-stage-app` so the submission stands on its
own and does not depend on cloning anything. It is three files: `Dockerfile`,
`package.json` and `server.js`.

The application is a small Express server:

    const express = require("express");

    const app = express();
    const PORT = 3000;

    app.get("/", (req, res) => {
      res.send("<h1>Hello World from Docker Multi-Stage Build!</h1>");
    });

    app.listen(PORT, () => {
      console.log(`Server running on port ${PORT}`);
    });

And the Dockerfile:

    # -------------------------
    # Stage 1: Build
    # -------------------------
    FROM node:24-alpine AS builder
    WORKDIR /app
    COPY package*.json ./
    RUN npm install
    COPY . .

    # -------------------------
    # Stage 2: Production
    # -------------------------
    FROM node:24-alpine AS production
    WORKDIR /app
    COPY --from=builder /app/package*.json ./
    RUN npm install --omit=dev
    COPY --from=builder /app/server.js ./
    EXPOSE 3000
    CMD ["npm", "start"]

How to read it. The `builder` stage installs the full dependency tree, dev packages
included, and copies the whole project in. The `production` stage then begins from a
clean `node:24-alpine` filesystem and pulls across only two things: the manifests, so it
can install with `--omit=dev`, and `server.js`. Everything the builder accumulated that
is not explicitly copied forward, so dev tooling, npm's cache, and any source files not
needed at runtime, is discarded with the stage and never becomes a layer of the final
image.

### Building the image

    $ docker build -t multistage-hello multi-stage-app

    #12 [production 5/5] COPY --from=builder /app/server.js ./
    #12 DONE 0.0s
    #13 exporting to image
    #13 naming to docker.io/library/multistage-hello:latest done
    #13 DONE 0.3s

The step labels in the build output are worth noticing: BuildKit prefixes them with the
stage name, `[builder 3/4]` and `[production 5/5]`, so you can see the two stages being
executed in sequence.

### Running it on port 8080

The server listens on 3000 inside the container, and the task asks for port 8080 on the
host, so the mapping does the translation:

    $ docker run -d --name multistage-app -p 8080:3000 multistage-hello
    33943338c338c5ddd42ca2ff4efe946a574686edc887ac1b1aaf3066a99e0d2e

    $ docker logs multistage-app
    > docker-hello-world@1.0.0 start
    > node server.js

    Server running on port 3000

The log still says port 3000, which is correct. The application knows nothing about 8080;
the remapping happens entirely outside it.

### Confirming with docker ps

    $ docker ps
    CONTAINER ID   IMAGE              COMMAND                  CREATED         STATUS         PORTS                       NAMES
    33943338c338   multistage-hello   "docker-entrypoint.s…"   3 seconds ago   Up 3 seconds   0.0.0.0:8080->3000/tcp      multistage-app

The `PORTS` column reading `0.0.0.0:8080->3000/tcp` is the confirmation that the app is
published on host port 8080.

### Reaching the application

    $ curl -i http://localhost:8080
    HTTP/1.1 200 OK
    X-Powered-By: Express
    Content-Type: text/html; charset=utf-8
    Content-Length: 51
    Connection: keep-alive

    $ curl http://localhost:8080
    <h1>Hello World from Docker Multi-Stage Build!</h1>

The `X-Powered-By: Express` header is a small extra confirmation that the response is
coming from the Express app rather than from anything else that might have been holding
that port.

## Task 2: Evidence

Name: Mahir Abidi

Enrollment number: 24BCS10125

### The application in a browser

Screenshot: `screenshots/multistage-app-8080.png`

It shows `http://localhost:8080` rendering the heading "Hello World from Docker
Multi-Stage Build!".

### docker ps showing the container published on 8080

    $ docker ps
    CONTAINER ID   IMAGE              COMMAND                  CREATED         STATUS         PORTS                                         NAMES
    33943338c338   multistage-hello   "docker-entrypoint.s…"   3 seconds ago   Up 3 seconds   0.0.0.0:8080->3000/tcp, [::]:8080->3000/tcp   multistage-app

### Does the multi-stage build save anything for this particular app?

To find out rather than assume, I wrote an ordinary single stage Dockerfile for the same
application and compared the images:

    $ docker images
    singlestage-hello   249MB
    multistage-hello    243MB

6 MB. That is a small enough difference to be worth explaining honestly instead of
glossing over. This app declares no dev dependencies and has no compile step, so the
builder stage produces almost exactly what it was given, and there is correspondingly
almost nothing for the second stage to leave behind.

The saving becomes significant when the build genuinely transforms its input into
something of a different kind. Two examples from the previous homework in this repo make
the point: a React app compiles down to static files, so the final image needs Nginx and
no Node at all and came out at 76 MB rather than over 200 MB; and a Java app needs the
JDK to compile but only a JRE to run. In both cases the tool that did the work is absent
from the shipped image. Here, `node` is required at build time and at runtime, so it
stays either way.

So the technique is right and the pattern is worth using by default, but the size benefit
is a property of the application, not of the Dockerfile.

## Task 3: Deploying three different types of application

I deployed three applications of different types, reusing the folders from the previous
Docker homework at `../task-5-docker`.

    docker build -t nodejs-hello ../task-5-docker/nodejs-app
    docker build -t python-hello ../task-5-docker/python-app
    docker build -t java-hello   ../task-5-docker/java-app

    docker run -d --name node-hello -p 3001:3000 nodejs-hello
    docker run -d --name py-hello   -p 5001:5000 python-hello
    docker run -d --name jv-hello   -p 8085:8080 java-hello

The three types:

1. **Node.js** with Express, on `node:20-alpine`, a single stage image.
2. **Python** with Flask, on `python:3.12-slim`, a single stage image.
3. **Java** using the JDK's built in HTTP server, built with a two stage JDK to JRE
   Dockerfile on `eclipse-temurin:21`.

### docker ps with all three running

    CONTAINER ID   IMAGE          COMMAND                  CREATED         STATUS         PORTS                      NAMES
    7e73b09bdb24   java-hello     "/__cacert_entrypoin…"   4 seconds ago   Up 3 seconds   0.0.0.0:8085->8080/tcp     jv-hello
    7230a4fdfe36   python-hello   "python app.py"          3 minutes ago   Up 3 minutes   0.0.0.0:5001->5000/tcp     py-hello
    7b3c5f4137d8   nodejs-hello   "docker-entrypoint.s…"   3 minutes ago   Up 3 minutes   0.0.0.0:3001->3000/tcp     node-hello

The `COMMAND` column is a useful detail. The Python container runs `python app.py`
straight from the `CMD`, while the Node and Java containers show an entrypoint script
that their base images install and that runs before the command.

### Verifying each one

    Node.js  http://localhost:3001  -> HTTP 200  <h1>Hello World</h1>
    Python   http://localhost:5001  -> HTTP 200  <h1>Hello World</h1>
    Java     http://localhost:8085  -> HTTP 200  <h1>Hello World</h1>

Browser screenshots for these three are in `../task-5-docker/screenshots`.

A note on the port choices: 3000 and 5000 were already occupied on my laptop, so Node and
Python went to 3001 and 5001. Port 8080 was in use by the multi-stage app from Task 1, so
the Java app was published on 8085. In every case only the host side changed and the
container side stayed at the application's normal port.

## Cleanup

    docker rm -f multistage-app node-hello py-hello jv-hello
    docker rmi multistage-hello singlestage-hello nodejs-hello python-hello java-hello

## What I took from this

A multi-stage Dockerfile is simply more than one `FROM` in a single file. Each `FROM`
opens a new stage with a fresh filesystem, `AS <name>` labels it, and
`COPY --from=<name>` reaches back into an earlier stage for specific paths. Only the
final stage becomes the image that gets tagged and shipped.

The reason to bother is that build tools and run tools are usually not the same set. A
compiler, a package manager with the dev tree installed, and the source itself are all
build time concerns. Leaving them in the shipped image makes it larger to store and pull,
and it widens the attack surface, because everything present in an image is something an
attacker who gets a shell can use.

`EXPOSE` turned out to be documentation only, again. What made the app reachable on 8080
was `-p 8080:3000` on `docker run`, read as host port then container port. That mapping is
also the reason a container can keep listening on a conventional internal port while
being served on whatever the host has free.
