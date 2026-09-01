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
