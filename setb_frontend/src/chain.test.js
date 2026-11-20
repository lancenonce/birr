import { ethers } from "ethers";
import { ETB_ABI, ORACLE_ABI, explainError, formatAge, formatRate, toAttestationStruct } from "./chain";

const sdkAttestation = {
  recipient: "0x000000000000000000000000000000000000bEEF",
  request: { url: "https://api.nbe.gov.et/api/get-selected-exchange-rates", header: "{}", method: "GET", body: "" },
  reponseResolve: [{ keyName: "code", parseType: "JSON", parsePath: "$.data[0].currency.code", extra: 1 }],
  data: '{"code":"USD","selling":"162.8054","buying":"161.1935"}',
  attConditions: "",
  timestamp: 1763000000000,
  additionParams: "",
  attestors: [{ attestorAddr: "0x5Ed3176045F68617B0958a61ac1868875C98C14d", url: "https://primuslabs.xyz" }],
  signatures: ["0x" + "11".repeat(65)],
  someSdkOnlyField: "ignored",
};

test("toAttestationStruct ABI-encodes against the oracle's submitRate signature", () => {
  const iface = new ethers.utils.Interface(ORACLE_ABI);
  const calldata = iface.encodeFunctionData("submitRate", [toAttestationStruct(sdkAttestation)]);
  const [decoded] = iface.decodeFunctionData("submitRate", calldata);
  expect(decoded.data).toBe(sdkAttestation.data);
  expect(decoded.timestamp.toString()).toBe("1763000000000");
  expect(decoded.reponseResolve[0].parsePath).toBe("$.data[0].currency.code");
  expect(decoded.request.url).toBe(sdkAttestation.request.url);
});

test("explainError decodes oracle and ETB custom errors and Error(string)", () => {
  const oracle = new ethers.utils.Interface(ORACLE_ABI);
  const etb = new ethers.utils.Interface(ETB_ABI);
  expect(explainError({ error: { data: oracle.encodeErrorResult("NotNewer", []) } })).toMatch(/newer/);
  expect(explainError({ data: etb.encodeErrorResult("StaleRate", [123]) })).toMatch(/stale/i);
  const invalidSig = "0x08c379a0" + ethers.utils.defaultAbiCoder.encode(["string"], ["Invalid signature"]).slice(2);
  expect(explainError({ error: { error: { data: invalidSig } } })).toMatch(/verifier/);
  expect(explainError({ code: 4001 })).toMatch(/rejected/);
});

test("formatting helpers", () => {
  expect(formatRate(ethers.utils.parseEther("162.80541"))).toBe("162.8054");
  expect(formatAge(1000, 1030)).toBe("30s ago");
  expect(formatAge(1000, 1000 + 7200)).toBe("2h ago");
  expect(formatAge(1000, 1000 + 3 * 86400)).toBe("3d ago");
});
