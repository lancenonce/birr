import { ethers } from "ethers";
import etbAbi from "./abi/ETB.json";
import oracleAbi from "./abi/NBERateOracle.json";
import { config, SEPOLIA_CHAIN_ID } from "./config";

export const ETB_ABI = etbAbi.abi;
export const ORACLE_ABI = oracleAbi.abi;

let readProvider;
export function getReadProvider() {
  if (!readProvider) readProvider = new ethers.providers.JsonRpcProvider(config.sepoliaRpcUrl, SEPOLIA_CHAIN_ID);
  return readProvider;
}

export function oracleContract(signerOrProvider = getReadProvider()) {
  return new ethers.Contract(config.oracleAddress, ORACLE_ABI, signerOrProvider);
}

export function etbContract(signerOrProvider = getReadProvider()) {
  return new ethers.Contract(config.etbAddress, ETB_ABI, signerOrProvider);
}

/** Connect MetaMask (or any EIP-1193 wallet) and make sure it's on `chainId`. */
export async function connectWallet(chainId = SEPOLIA_CHAIN_ID) {
  if (!window.ethereum) throw new Error("No wallet found. Install MetaMask.");
  await window.ethereum.request({ method: "eth_requestAccounts" });
  const current = parseInt(await window.ethereum.request({ method: "eth_chainId" }), 16);
  if (current !== chainId) {
    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: ethers.utils.hexValue(chainId) }],
      });
    } catch (e) {
      if (e.code === 4902) throw new Error(`Chain ${chainId} is not added to your wallet.`);
      throw e;
    }
  }
  const provider = new ethers.providers.Web3Provider(window.ethereum, "any");
  const signer = provider.getSigner();
  return { signer, address: await signer.getAddress() };
}

/**
 * Convert the js-sdk attestation object into the exact shape of the Solidity `Attestation` struct.
 * (Field names already match; this drops anything extra and normalizes types.)
 */
export function toAttestationStruct(a) {
  return {
    recipient: a.recipient,
    request: {
      url: a.request.url,
      header: a.request.header ?? "",
      method: a.request.method,
      body: a.request.body ?? "",
    },
    reponseResolve: (a.reponseResolve || []).map((r) => ({
      keyName: r.keyName,
      parseType: r.parseType,
      parsePath: r.parsePath,
    })),
    data: a.data,
    attConditions: a.attConditions ?? "",
    timestamp: ethers.BigNumber.from(a.timestamp),
    additionParams: a.additionParams ?? "",
    attestors: (a.attestors || []).map((t) => ({ attestorAddr: t.attestorAddr, url: t.url ?? "" })),
    signatures: a.signatures,
  };
}

const ORACLE_ERRORS = {
  WrongUrl: "The attestation is for a different URL than the oracle expects.",
  WrongMethod: "The attestation used a different HTTP method.",
  WrongResolves: "The attestation's fields don't match the oracle's template (check nbe-spec.json).",
  NotUSD: "The attested currency is not USD.",
  StaleAttestation: "The attestation is too old.",
  FutureAttestation: "The attestation timestamp is in the future (clock skew).",
  NotNewer: "A newer (or the same) rate is already on-chain.",
  RateOutOfBounds: "The attested rate is outside the oracle's sanity bounds.",
  SellingBelowBuying: "Attested selling rate is below the buying rate.",
  EmptyDecimal: "A rate field was missing from the attestation.",
  InvalidDecimalChar: "A rate field was not a plain decimal number.",
  TooManyFractionDigits: "A rate field had too many decimals.",
  MissingDigits: "A rate field was malformed.",
};

const ETB_ERRORS = {
  StaleRate: "The official rate is stale. Prove the latest NBE rate first.",
  RateUnavailable: "No official rate on-chain yet. Prove the latest NBE rate first.",
  InsufficientReserve: "The contract doesn't hold enough USDC for this swap.",
  OfficialRateNotConfigured: "ETB is not wired to the oracle/USDC yet.",
  ZeroAmount: "Amount too small.",
  ZeroAddress: "Missing recipient address.",
};

/** Best-effort decode of a revert into a readable message. */
export function explainError(e) {
  const data = findRevertData(e);
  if (data) {
    for (const [abi, table] of [[ORACLE_ABI, ORACLE_ERRORS], [ETB_ABI, ETB_ERRORS]]) {
      try {
        const parsed = new ethers.utils.Interface(abi).parseError(data);
        return table[parsed.name] || parsed.name;
      } catch {
        // not this contract's error
      }
    }
    try {
      // Error(string), e.g. "Invalid signature" from the Primus verifier
      const [reason] = ethers.utils.defaultAbiCoder.decode(["string"], ethers.utils.hexDataSlice(data, 4));
      if (reason === "Invalid signature") return "The Primus verifier doesn't trust this attestor (see README: verifier).";
      return reason;
    } catch {
      // fall through
    }
  }
  if (e?.code === 4001 || e?.code === "ACTION_REJECTED") return "Transaction rejected in wallet.";
  return e?.reason || e?.error?.message || e?.message || String(e);
}

function findRevertData(e, depth = 0) {
  if (!e || depth > 5) return undefined;
  if (typeof e.data === "string" && e.data.startsWith("0x") && e.data.length >= 10) return e.data;
  return findRevertData(e.error, depth + 1) || findRevertData(e.data, depth + 1);
}

export function formatRate(rate1e18, digits = 4) {
  return Number(ethers.utils.formatUnits(rate1e18, 18)).toFixed(digits);
}

export function formatAge(updatedAtSec, nowSec = Math.floor(Date.now() / 1000)) {
  const s = Math.max(0, nowSec - updatedAtSec);
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}
