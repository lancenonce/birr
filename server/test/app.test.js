import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { ethers } from "ethers";
import { PrimusZKTLS } from "@primuslabs/zktls-js-sdk";
import { createApp, validate } from "../src/app.js";

const APP_ID = "0x1234567890abcdef1234567890abcdef12345678";
const TEMPLATE_ID = "11111111-2222-3333-4444-555555555555";
const ORIGIN = "http://localhost:3000";
const wallet = ethers.Wallet.createRandom(); // stands in for the Primus appSecret

let server;
let base;

function params(overrides = {}) {
  return JSON.stringify({
    appId: APP_ID,
    attTemplateID: TEMPLATE_ID,
    userAddress: "0x000000000000000000000000000000000000bEEF",
    timestamp: Date.now(),
    attMode: { algorithmType: "proxytls" },
    ...overrides,
  });
}

async function post(body, headers = {}) {
  const res = await fetch(`${base}/sign`, {
    method: "POST",
    headers: { "content-type": "application/json", origin: ORIGIN, ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
  return { res, json: await res.json() };
}

before(async () => {
  const signer = new PrimusZKTLS();
  assert.equal(await signer.init(APP_ID, wallet.privateKey), true);
  const app = createApp({
    appId: APP_ID,
    templateId: TEMPLATE_ID,
    signer,
    allowedOrigins: [ORIGIN],
    rateLimit: { windowMs: 60_000, max: 8 },
  });
  await new Promise((r) => (server = app.listen(0, r)));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

test("health", async () => {
  const res = await fetch(`${base}/health`);
  assert.deepEqual(await res.json(), { ok: true });
});

test("signs a valid request with the appSecret, in the format startAttestation expects", async () => {
  const signParams = params();
  const { res, json } = await post({ signParams });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("access-control-allow-origin"), ORIGIN);

  const signed = JSON.parse(json.signResult);
  assert.deepEqual(signed.attRequest, JSON.parse(signParams));
  // Primus scheme: personal_sign over the hex string keccak256(utf8(signParams)).
  const messageHash = ethers.utils.keccak256(new TextEncoder().encode(signParams));
  assert.equal(ethers.utils.verifyMessage(messageHash, signed.appSignature), wallet.address);
});

test("rejects other templates (no signing oracle for arbitrary attestations)", async () => {
  const { res, json } = await post({ signParams: params({ attTemplateID: "someone-elses-template" }) });
  assert.equal(res.status, 400);
  assert.equal(json.error, "attTemplateID not allowed");
});

test("rejects a different appId", async () => {
  const { res, json } = await post({ signParams: params({ appId: "0xdeadbeef" }) });
  assert.equal(res.status, 400);
  assert.equal(json.error, "appId mismatch");
});

test("rejects malformed input", async () => {
  assert.equal((await post({})).res.status, 400);
  assert.equal((await post({ signParams: "not json" })).res.status, 400);
  assert.equal((await post({ signParams: "[1,2]" })).res.status, 400);
  assert.equal((await post({ signParams: params({ userAddress: "0x123" }) })).json.error, "invalid userAddress");
  assert.equal((await post("{bad json")).res.status, 400);
});

test("CORS: no allow-origin header for unknown origins", async () => {
  const { res } = await post({ signParams: params() }, { origin: "https://evil.example" });
  assert.equal(res.headers.get("access-control-allow-origin"), null);
});

test("rate limits per IP", async () => {
  // The earlier tests used up part of the 8-request window; keep going until we're throttled.
  let status;
  for (let i = 0; i < 10 && status !== 429; i++) status = (await post({ signParams: params() })).res.status;
  assert.equal(status, 429);
});

test("validate() unit", () => {
  const cfg = { appId: APP_ID, templateId: TEMPLATE_ID };
  assert.equal(validate(params(), cfg), null);
  assert.equal(validate(params({ userAddress: undefined }), cfg), null);
  assert.equal(validate("x".repeat(17 * 1024), cfg), "signParams too large");
  assert.equal(validate(123, cfg), "signParams must be a non-empty string");
});
