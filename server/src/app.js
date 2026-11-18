import express from "express";
import cors from "cors";

const ADDRESS_RE = /^0x[0-9a-fA-F]{40}$/;
const MAX_SIGN_PARAMS_BYTES = 16 * 1024;

/**
 * Builds the signing server.
 *
 * The Primus browser SDK needs every attestation request signed with the project's appSecret. That secret
 * must never reach the browser, so the frontend sends the request here and we sign it, but only if it is
 * for our own appId and our NBE exchange-rate template, so this can't be used as a signing oracle for
 * arbitrary Primus templates billed to our project.
 *
 * @param {object} cfg
 * @param {string} cfg.appId           Primus project appId
 * @param {string} cfg.templateId      Primus attestation template id for the NBE rate
 * @param {{sign(s: string): Promise<string>}} cfg.signer  initialized PrimusZKTLS (or a stub in tests)
 * @param {string[]} cfg.allowedOrigins CORS allow-list ("*" allows any origin)
 * @param {{windowMs: number, max: number}} [cfg.rateLimit]
 */
export function createApp({ appId, templateId, signer, allowedOrigins, rateLimit }) {
  if (!appId || !templateId || !signer) throw new Error("createApp: appId, templateId and signer are required");

  const app = express();
  app.disable("x-powered-by");
  app.set("trust proxy", 1);

  const anyOrigin = allowedOrigins.includes("*");
  app.use(
    cors({
      origin: (origin, cb) => cb(null, anyOrigin || !origin || allowedOrigins.includes(origin)),
      methods: ["GET", "POST"],
    }),
  );
  app.use(express.json({ limit: "32kb" }));

  app.get("/health", (_req, res) => res.json({ ok: true }));

  app.post("/sign", limiter(rateLimit ?? { windowMs: 60_000, max: 30 }), async (req, res) => {
    const signParams = req.body?.signParams;
    const problem = validate(signParams, { appId, templateId });
    if (problem) return res.status(400).json({ error: problem });

    try {
      const signResult = await signer.sign(signParams);
      res.json({ signResult });
    } catch (e) {
      console.error("sign failed:", e);
      res.status(500).json({ error: "signing failed" });
    }
  });

  app.use((err, _req, res, _next) => {
    // body-parser errors (bad JSON, too large) land here
    res.status(err.status ?? 500).json({ error: err.status ? err.message : "internal error" });
  });

  return app;
}

/** @returns {string|null} a human-readable problem, or null if the request may be signed */
export function validate(signParams, { appId, templateId }) {
  if (typeof signParams !== "string" || signParams.length === 0) return "signParams must be a non-empty string";
  if (Buffer.byteLength(signParams) > MAX_SIGN_PARAMS_BYTES) return "signParams too large";

  let parsed;
  try {
    parsed = JSON.parse(signParams);
  } catch {
    return "signParams is not valid JSON";
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return "signParams must be a JSON object";
  if (parsed.appId !== appId) return "appId mismatch";
  if (parsed.attTemplateID !== templateId) return "attTemplateID not allowed";
  if (parsed.userAddress !== undefined && !ADDRESS_RE.test(parsed.userAddress)) return "invalid userAddress";
  return null;
}

/** Tiny fixed-window per-IP rate limiter (no external dependency). */
function limiter({ windowMs, max }) {
  const hits = new Map();
  return (req, res, next) => {
    const now = Date.now();
    const key = req.ip;
    let entry = hits.get(key);
    if (!entry || now - entry.start >= windowMs) {
      entry = { start: now, count: 0 };
      hits.set(key, entry);
    }
    if (++entry.count > max) {
      res.set("Retry-After", String(Math.ceil((entry.start + windowMs - now) / 1000)));
      return res.status(429).json({ error: "too many requests" });
    }
    if (hits.size > 10_000) {
      for (const [k, v] of hits) if (now - v.start >= windowMs) hits.delete(k);
    }
    next();
  };
}
