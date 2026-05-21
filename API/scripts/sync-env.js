const fs = require("fs");
require("dotenv").config({ path: "./.env" });

// This script is only needed if you want to pre-seed app/.env before the server starts.
// The actual ngrok URL is set dynamically by server.js at runtime.
// For emulator dev without ngrok, we write the Android emulator localhost alias.

const baseUrl = process.env.NGROK_AUTHTOKEN
  ? "PENDING_NGROK_URL" // will be overwritten by server.js once ngrok starts
  : `http://10.0.2.2:${process.env.PORT || 3000}`;

const content = `API_BASE_URL=${baseUrl}\nAPI_TIMEOUT=${process.env.API_TIMEOUT || 30000}`;

fs.writeFileSync("./app/.env", content);
console.log(`app/.env written with API_BASE_URL=${baseUrl}`);
