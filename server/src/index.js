import "dotenv/config";
import { PrimusZKTLS } from "@primuslabs/zktls-js-sdk";
import { createApp } from "./app.js";

function required(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`Missing required env var ${name} (see server/.env.example)`);
    process.exit(1);
  }
  return v;
}

const appId = required("APP_ID");
const appSecret = required("APP_SECRET");
const templateId = required("TEMPLATE_ID");
const allowedOrigins = (process.env.ALLOWED_ORIGINS ?? "http://localhost:3000")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);
const port = Number(process.env.PORT ?? 9000);

const signer = new PrimusZKTLS();
await signer.init(appId, appSecret); // local only when an appSecret is given in Node

createApp({ appId, templateId, signer, allowedOrigins }).listen(port, () => {
  console.log(`Primus signer listening on http://localhost:${port}`);
  console.log(`  template: ${templateId}`);
  console.log(`  allowed origins: ${allowedOrigins.join(", ")}`);
});
