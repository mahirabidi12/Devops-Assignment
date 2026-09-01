import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

/**
 * A minimal web server built on com.sun.net.httpserver, which ships with the
 * JDK. That keeps the app free of any external dependency, so there is no
 * Maven or Gradle involved and the Dockerfile only has to run javac.
 */
public class HelloWorld {

    private static final int PORT = 8080;

    private static final String PAGE = """
            <html>
              <head><title>Java Hello World</title></head>
              <body style="font-family: sans-serif; text-align: center; margin-top: 15vh;">
                <h1>Hello World</h1>
                <p>Served by Java inside Docker</p>
              </body>
            </html>
            """;

    public static void main(String[] args) throws IOException {
        // Bind to 0.0.0.0 so the published port reaches the server.
        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", PORT), 0);

        server.createContext("/", exchange -> {
            byte[] body = PAGE.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "text/html; charset=utf-8");
            exchange.sendResponseHeaders(200, body.length);
            try (OutputStream out = exchange.getResponseBody()) {
                out.write(body);
            }
        });

        server.start();
        System.out.println("Java app listening on port " + PORT);
    }
}
