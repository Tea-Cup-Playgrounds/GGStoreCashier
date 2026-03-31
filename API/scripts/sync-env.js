const fs = require("fs");
require("dotenv").config({ path: "./.env" });

const content = `API_BASE_URL=${process.env.NGROK_API_URL}\nAPI_TIMEOUT=${process.env.NGROK_API_TIMEOUT}`;

fs.writeFileSync("./app/.env", content);