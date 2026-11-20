import { PrimusZKTLS } from "@primuslabs/zktls-js-sdk";
import { config } from "./config";

let primus;
let initPromise;

/** Lazily initialize the Primus SDK (talks to the Primus browser extension). */
async function getPrimus() {
  if (!initPromise) {
    primus = new PrimusZKTLS();
    initPromise = primus.init(config.primusAppId).catch((e) => {
      initPromise = undefined; // allow retry after the user installs/unlocks the extension
      throw humanizePrimusError(e);
    });
  }
  await initPromise;
  return primus;
}

/** Ask our signing server (server/) to sign the request with the Primus appSecret. */
export async function signRequest(signParams, fetchImpl = fetch) {
  const res = await fetchImpl(`${config.signerUrl}/sign`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ signParams }),
  });
  let body = {};
  try {
    body = await res.json();
  } catch {
    // fall through
  }
  if (!res.ok || !body.signResult) {
    throw new Error(`Signing server error: ${body.error || res.status}`);
  }
  return body.signResult;
}

/**
 * Produce a Primus zkTLS attestation of the NBE exchange-rate API for `userAddress`.
 * @param {(msg: string) => void} onStatus progress callback
 * @returns the attestation object, shaped like the on-chain `Attestation` struct
 */
export async function attestNbeRate(userAddress, onStatus = () => {}) {
  onStatus("Connecting to the Primus extension…");
  const zk = await getPrimus();

  const request = zk.generateRequestParams(config.primusTemplateId, userAddress);
  request.setAttMode({ algorithmType: "proxytls" });
  const signParams = request.toJsonString();

  onStatus("Requesting a signed attestation request…");
  const signed = await signRequest(signParams);

  onStatus("Generating zkTLS proof of the NBE rate (a Primus tab may open)…");
  let attestation;
  try {
    attestation = await zk.startAttestation(signed);
  } catch (e) {
    throw humanizePrimusError(e);
  }

  if (!zk.verifyAttestation(attestation)) {
    throw new Error("Primus attestation failed signature verification");
  }
  return attestation;
}

export function humanizePrimusError(e) {
  const code = e?.code;
  if (code === "00006") {
    return new Error("Primus browser extension not found. Install it from https://primuslabs.xyz and reload.");
  }
  const msg = e?.message || e?.data?.desc || e?.title || String(e);
  return new Error(code ? `Primus error ${code}: ${msg}` : msg);
}
