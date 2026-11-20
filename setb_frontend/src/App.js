import React, { useCallback, useEffect, useState } from "react";
import { ethers } from "ethers";
import customLogo from "./customLogo.svg";
import "./App.css";
import { config, missingConfig, SEPOLIA_CHAIN_ID, UNICHAIN_SEPOLIA_CHAIN_ID } from "./config";
import {
  connectWallet,
  etbContract,
  explainError,
  formatAge,
  formatRate,
  oracleContract,
  toAttestationStruct,
} from "./chain";
import { attestNbeRate } from "./primus";

const CHAIN_IDS = { Ethereum: SEPOLIA_CHAIN_ID, Unichain: UNICHAIN_SEPOLIA_CHAIN_ID };

function App() {
  const [sourceAsset, setSourceAsset] = useState("sETB");
  const [targetAsset, setTargetAsset] = useState("USDC");
  const [sourceChain, setSourceChain] = useState("Ethereum");
  const [targetChain, setTargetChain] = useState("Ethereum");
  const [targetAddress, setTargetAddress] = useState("");
  const [useBankRate, setUseBankRate] = useState(true);
  const [amount, setAmount] = useState("");

  const [marketRate] = useState(121.47); // Uniswap market rate: placeholder (out of scope)
  const [official, setOfficial] = useState(null); // { selling, buying, updatedAt, maxRateAge }
  const [quote, setQuote] = useState(null);
  const [status, setStatus] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const missing = missingConfig();
  const isOfficialSwap = useBankRate && sourceChain === "Ethereum" && targetChain === "Ethereum";

  const refreshOfficialRate = useCallback(async () => {
    if (missing.length) return;
    try {
      const [[selling, buying, updatedAt], maxRateAge] = await Promise.all([
        oracleContract().getRate(),
        etbContract().maxRateAge(),
      ]);
      setOfficial({
        selling,
        buying,
        updatedAt: updatedAt.toNumber(),
        maxRateAge: maxRateAge.toNumber(),
      });
    } catch (e) {
      setError(`Could not read the official rate: ${explainError(e)}`);
    }
  }, [missing.length]);

  useEffect(() => {
    refreshOfficialRate();
  }, [refreshOfficialRate]);

  // Live USDC quote for official-rate swaps.
  useEffect(() => {
    setQuote(null);
    if (!isOfficialSwap || missing.length || !amount) return;
    let wei;
    try {
      wei = ethers.utils.parseEther(amount);
    } catch {
      return;
    }
    let cancelled = false;
    etbContract()
      .quoteOfficial(wei)
      .then(([usdcOut]) => !cancelled && setQuote(ethers.utils.formatUnits(usdcOut, 6)))
      .catch(() => !cancelled && setQuote(null));
    return () => {
      cancelled = true;
    };
  }, [amount, isOfficialSwap, missing.length, official]);

  const run = async (fn) => {
    setBusy(true);
    setError("");
    try {
      await fn();
    } catch (e) {
      setError(explainError(e));
      setStatus("");
    } finally {
      setBusy(false);
    }
  };

  const handleProveRate = () =>
    run(async () => {
      setStatus("Connecting wallet…");
      const { signer, address } = await connectWallet(SEPOLIA_CHAIN_ID);

      const attestation = await attestNbeRate(address, setStatus);
      const att = toAttestationStruct(attestation);
      const oracle = oracleContract(signer);

      setStatus("Checking the proof against the oracle…");
      await oracle.callStatic.submitRate(att); // surfaces a readable revert before asking for a signature

      setStatus("Submitting proof on-chain — confirm in your wallet…");
      const tx = await oracle.submitRate(att);
      setStatus(`Waiting for confirmation (${tx.hash.slice(0, 10)}…)`);
      await tx.wait();

      setStatus("Official NBE rate updated on-chain ✓");
      await refreshOfficialRate();
    });

  const handleSwap = () =>
    run(async () => {
      if (!amount) throw new Error("Enter an amount.");
      const amountWei = ethers.utils.parseEther(amount);

      if (isOfficialSwap) {
        if (sourceAsset !== "sETB" || targetAsset !== "USDC") {
          throw new Error("Official-rate swaps convert sETB → USDC.");
        }
        setStatus("Connecting wallet…");
        const { signer, address } = await connectWallet(SEPOLIA_CHAIN_ID);
        const etb = etbContract(signer);
        const to = targetAddress || address;

        await etb.callStatic.swapAtOfficialRate(amountWei, to);
        setStatus("Swapping at the official rate — confirm in your wallet…");
        const tx = await etb.swapAtOfficialRate(amountWei, to);
        setStatus(`Waiting for confirmation (${tx.hash.slice(0, 10)}…)`);
        await tx.wait();
        setStatus(`Swapped ${amount} sETB → USDC at the official rate ✓`);
        return;
      }

      // Cross-chain bridge (VIA Labs) — unchanged behaviour, out of scope for the official-rate work.
      if (sourceChain !== "Ethereum") throw new Error("Bridging is only supported from Ethereum (Sepolia).");
      setStatus("Connecting wallet…");
      const { signer, address } = await connectWallet(SEPOLIA_CHAIN_ID);
      const desiredOutputToken = targetChain === "Unichain" ? config.etbUnichainAddress : config.etbAddress;
      setStatus("Bridging — confirm in your wallet…");
      const tx = await etbContract(signer).bridge(
        CHAIN_IDS[targetChain],
        targetAddress || address,
        amountWei,
        desiredOutputToken,
        useBankRate
      );
      await tx.wait();
      setStatus(`Bridge transaction sent ✓ (${tx.hash.slice(0, 10)}…)`);
    });

  const now = Math.floor(Date.now() / 1000);
  const hasRate = official && official.updatedAt > 0;
  const isStale = hasRate && now > official.updatedAt + official.maxRateAge;

  return (
    <div className="App">
      <header className="App-header">
        <img src={customLogo} className="App-logo" alt="logo" />
        <h1>good rates</h1>

        {missing.length > 0 && (
          <p className="error" role="alert">
            Missing configuration: {missing.join(", ")} (see setb_frontend/.env.example)
          </p>
        )}

        <form onSubmit={(e) => e.preventDefault()}>
          <div>
            <label>Source Asset:</label>
            <select value={sourceAsset} onChange={(e) => setSourceAsset(e.target.value)}>
              <option value="sETB">sETB</option>
              <option value="USDC">USDC</option>
            </select>
          </div>
          <div>
            <label>Target Asset:</label>
            <select value={targetAsset} onChange={(e) => setTargetAsset(e.target.value)}>
              <option value="sETB">sETB</option>
              <option value="USDC">USDC</option>
            </select>
          </div>
          <div>
            <label>Source Chain:</label>
            <select value={sourceChain} onChange={(e) => setSourceChain(e.target.value)}>
              <option value="Unichain">Unichain</option>
              <option value="Ethereum">Ethereum (Sepolia)</option>
            </select>
          </div>
          <div>
            <label>Target Chain:</label>
            <select value={targetChain} onChange={(e) => setTargetChain(e.target.value)}>
              <option value="Unichain">Unichain</option>
              <option value="Ethereum">Ethereum (Sepolia)</option>
            </select>
          </div>
          <div>
            <label>Target Address:</label>
            <input
              type="text"
              placeholder="defaults to your wallet"
              value={targetAddress}
              onChange={(e) => setTargetAddress(e.target.value)}
            />
          </div>
          <div>
            <label>Amount (sETB):</label>
            <input type="text" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </div>
          <div>
            <label htmlFor="bank-rate">Use official NBE rate for USD?</label>
            <input
              id="bank-rate"
              type="checkbox"
              checked={useBankRate}
              onChange={(e) => setUseBankRate(e.target.checked)}
            />
          </div>
          {isOfficialSwap && quote && <p className="quote">You receive ≈ {quote} USDC</p>}
          <button type="button" onClick={handleSwap} disabled={busy || missing.length > 0}>
            Swap
          </button>
        </form>

        <div className="price-feed">
          <h2>Price Feed</h2>
          <p>Market Rate (Uniswap): {marketRate}</p>
          <p>
            Official NBE Rate (zkTLS-verified):{" "}
            {hasRate ? (
              <>
                {formatRate(official.selling)} ETB/USD selling · {formatRate(official.buying)} buying{" "}
                <span className={isStale ? "stale" : "fresh"}>
                  ({formatAge(official.updatedAt, now)}
                  {isStale ? ", stale" : ""})
                </span>
              </>
            ) : (
              "not proven yet"
            )}
          </p>
          <button type="button" onClick={handleProveRate} disabled={busy || missing.length > 0}>
            Prove latest NBE rate
          </button>
          <p className="hint">
            Generates a Primus zkTLS proof of api.nbe.gov.et in your browser and posts it to the on-chain oracle.
            Requires the Primus extension.
          </p>
        </div>

        {status && (
          <p className="status" role="status">
            {status}
          </p>
        )}
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
      </header>
    </div>
  );
}

export default App;
