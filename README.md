# Birr ☃️🇪🇹 (aka good rates)

sETB is a cross-chain Ethiopian Birr token. Holders can redeem it for USDC at the **official National Bank of Ethiopia (NBE) USD rate**. The rate isn't typed in by an admin. Anyone can prove it on-chain with a **Primus zkTLS attestation** of `https://api.nbe.gov.et/api/get-selected-exchange-rates`.

## How it works

```
 browser (setb_frontend)                          Ethereum Sepolia
 ───────────────────────                          ────────────────
 1. "Prove latest NBE rate"
 2. Primus js-sdk builds a request ──► server/ POST /sign   (holds the Primus appSecret)
 3. Primus extension runs zkTLS against api.nbe.gov.et
    and returns a signed attestation
 4. oracle.submitRate(attestation) ─────────────► NBERateOracle
                                                    ├─ PrimusZKTLS.verifyAttestation (attestor signature)
                                                    ├─ URL, method and JSON paths match the pinned template
                                                    ├─ fresh (≤ 1h old) and newer than the last one
                                                    ├─ currency code == "USD"
                                                    └─ stores selling / buying (1e18 ETB per USD)
 5. etb.swapAtOfficialRate(amount, to) ─────────► ETB
                                                    burns sETB, pays amount / selling USDC
                                                    from its USDC reserve (rate must be ≤ 1 day old)
```

- **`NBERateOracle`** ([contracts/src/oracle/NBERateOracle.sol](contracts/src/oracle/NBERateOracle.sol)). Permissionless: anyone with a valid proof can update the rate.
  - The Primus verifier only checks the attestor's signature. Everything else is checked here: the URL, the JSON paths, freshness, replay, `USD`, and sanity bounds.
  - The owner can change the verifier, the template spec, and the age and bounds limits.
- **`ETB`** ([contracts/src/ETB.sol](contracts/src/ETB.sol)). Provides `swapAtOfficialRate` and `quoteOfficial`. The owner funds the USDC reserve with plain transfers and can take it out with `withdrawReserve`.
  - Cross-chain official swaps (VIA Labs `bridge` → `messageProcess`) pay USDC when they can. Otherwise they re-mint sETB to the recipient, so burned value is never stranded.
- **`server/`**: a tiny Express signing server. The Primus appSecret must never reach the browser. The server only signs requests for the configured appId and NBE template.
- **`setb_frontend/`**: a React app. Shows the on-chain rate and its age, proves new rates, and swaps.

Not covered yet: the Uniswap v4 market-rate path (`marketSwap`, `src/hooks/`), and fixing the VIA bridge setup. [Diagram.png](Diagram.png) is the original hook design.

## Repo layout

| Path | What |
| --- | --- |
| `contracts/` | Foundry project: `ETB`, `NBERateOracle`, `DecimalParser`, deploy scripts, tests |
| `server/` | Primus request-signing server (Node ≥ 20) |
| `setb_frontend/` | React (CRA) frontend |

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation), Node 20+, MetaMask
- The Primus browser extension (linked from [primuslabs.xyz](https://primuslabs.xyz)) in the browser that runs the frontend
- A Primus Developer Hub project ([dev.primuslabs.xyz](https://dev.primuslabs.xyz)):
  1. Create a project and note the **appId** and **appSecret**. The secret is shown once.
  2. Create a custom template for `GET https://api.nbe.gov.et/api/get-selected-exchange-rates` that reveals these three fields in plaintext and nothing else:

     | keyName | parsePath |
     | --- | --- |
     | `code` | `$.data[0].currency.code` |
     | `selling` | `$.data[0].selling` |
     | `buying` | `$.data[0].buying` |

     Note the **templateId**.
- Sepolia ETH, plus Sepolia USDC for the reserve ([faucet.circle.com](https://faucet.circle.com))

```sh
git clone --recurse-submodules <repo>   # or: git submodule update --init --recursive
```

## 1. Contracts

```sh
cd contracts
cp .env.example .env        # PRIVATE_KEY, SEPOLIA_RPC_URL, ETHERSCAN_API_KEY
forge build
forge test
```

Deploy in this order:

```sh
# a) Primus verifier that trusts the current Primus attestor (see "Verifier caveat")
forge script script/DeployPrimusVerifier.s.sol --rpc-url sepolia --broadcast --verify
#    → put the proxy address in PRIMUS_VERIFIER

# b) Oracle + ETB, wired together. Set RESERVE_USDC (6 decimals) to fund the reserve in the same run.
forge script script/DeployOfficialRate.s.sol --rpc-url sepolia --broadcast --verify
#    → put the addresses in ORACLE_ADDRESS / ETB_ADDRESS (and in setb_frontend/.env)

# c) Optional: mint test sETB (only the deployer can)
ETB_ADDRESS=0x... MINT_TO=0x... MINT_AMOUNT=1000 forge script script/MintETB.s.sol --rpc-url sepolia --broadcast
```

You can fund or top up the reserve later by sending Sepolia USDC to the ETB address.

Other scripts:
- `SubmitRate.s.sol`: submits a saved attestation JSON (`ATTESTATION_FILE`). Good for smoke tests or relaying.
- `ConfigureOracleSpec.s.sol`: re-pins the oracle to an edited [`script/config/nbe-spec.json`](contracts/script/config/nbe-spec.json).

### Matching the oracle to your template

The oracle only accepts attestations whose `reponseResolve` array (keyName, parseType and parsePath, in order) hashes to the pinned spec. It reads `code`, `selling` and `buying` from the attestation's `data` JSON.

The defaults in `nbe-spec.json` are a best guess and haven't been checked against a real attestation. If your first real proof reverts with `WrongResolves`, or with a parse error such as `EmptyDecimal`:
1. Copy the `reponseResolve` array and key names from that attestation into `nbe-spec.json`. The frontend logs the full attestation to the browser console as `Primus attestation`. You can also save that JSON and replay it with `SubmitRate`.
2. Run `ConfigureOracleSpec`.

## 2. Signing server

```sh
cd server
cp .env.example .env        # APP_ID, APP_SECRET, TEMPLATE_ID, ALLOWED_ORIGINS
npm install
npm test
npm start                   # http://localhost:9000  (GET /health, POST /sign)
```

In production, put it behind HTTPS and set `ALLOWED_ORIGINS` to the frontend's origin. Anyone who can reach `/sign` can spend your Primus quota.

## 3. Frontend

```sh
cd setb_frontend
cp .env.example .env        # Primus appId/templateId, signer URL, oracle + ETB addresses
npm install
npm test
npm start                   # http://localhost:3000
```

1. Click **Prove latest NBE rate** and approve the steps in the Primus extension and MetaMask. The panel then shows the verified rate.
2. Keep **Use official NBE rate** checked, with both chains set to Ethereum.
3. Enter an sETB amount and click **Swap**.

## Verifier caveat

Primus's own Sepolia verifier (`0x3760aB354507a29a9F5c65A66C74353fd86393FA`) still trusts only the old attestor `0xDB736B13…8eF6`. `zktls-js-sdk@0.3.15` signs with `0x5Ed3176045F68617B0958a61ac1868875C98C14d`. `DeployPrimusVerifier` deploys Primus's unmodified `PrimusZKTLS` contract trusting the new attestor.
- If Primus updates their verifier, point the oracle at it with `setVerifier`.
- If Primus rotates the attestor, call `setAttestor` on our verifier. Its owner is the deployer.

## Deployments (Sepolia)

| Contract | Address |
| --- | --- |
| PrimusZKTLS verifier (proxy) | _TBD_ |
| NBERateOracle | _TBD_ |
| ETB (official rate) | _TBD_ |
| USDC (Circle) | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |

Earlier bridge-only deployments, before the official rate existed:

| Network | ETB |
| --- | --- |
| Ethereum Sepolia | `0x7b230BE939C5A7795938916e4F7409B5e0880F4C` |
| Unichain Sepolia | `0xdD3324AB2e26268E15c792Cb8c1f0eD8bA9A4C76` |

## Known limitations

- The `data` format and the template fields are unconfirmed until the first real attestation. See [Matching the oracle to your template](#matching-the-oracle-to-your-template).
- The oracle trusts Primus's attestor. zkTLS proves what `api.nbe.gov.et` returned, not that NBE's number is right.
- ETB's `MESSAGE_OWNER` (VIA's `recoverToken`) can also move the USDC reserve. `script/ConfigureETB.s.sol` passes each ETB's own address as the VIA message gateway. Both belong to the bridge work, which is out of scope here.
- The Uniswap PoolManager addresses in `script/lib/Chains.sol` haven't been checked. They're only used by `marketSwap`.
