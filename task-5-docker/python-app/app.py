from flask import Flask

app = Flask(__name__)

PAGE = """
    <html>
      <head><title>Python Hello World</title></head>
      <body style="font-family: sans-serif; text-align: center; margin-top: 15vh;">
        <h1>Hello World</h1>
        <p>Served by Python and Flask inside Docker</p>
      </body>
    </html>
    """


@app.route("/")
def hello():
    return PAGE


if __name__ == "__main__":
    # host must be 0.0.0.0, the Flask default of 127.0.0.1 would only be
    # reachable from inside the container itself.
    app.run(host="0.0.0.0", port=5000)
