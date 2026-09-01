const express = require('express');

const app = express();

// Read the port from the environment so the container can be told a
// different one, and fall back to 3000 when nothing is set.
const PORT = process.env.PORT || 3000;

const page = `
    <html>
      <head><title>Node.js Hello World</title></head>
      <body style="font-family: sans-serif; text-align: center; margin-top: 15vh;">
        <h1>Hello World</h1>
        <p>Served by Node.js and Express inside Docker</p>
      </body>
    </html>
  `;

app.get('/', (req, res) => {
  res.send(page);
});

// 0.0.0.0 rather than localhost, otherwise the port mapping cannot reach it.
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Node.js app listening on port ${PORT}`);
});
