const fs = require("fs");
require("dotenv").config({ path: "./.env" });

const baseUrl = process.env.NGROK_AUTHTOKEN
  ? "PENDING_NGROK_URL" // will be overwritten by server.js once ngrok starts
  : `http://10.0.2.2:${process.env.PORT || 3000}`;

const content = `API_BASE_URL=${baseUrl}\nAPI_TIMEOUT=${process.env.API_TIMEOUT || 30}`;

fs.writeFileSync("./app/.env", content);
console.log(`app/.env written with API_BASE_URL=${baseUrl}`);
