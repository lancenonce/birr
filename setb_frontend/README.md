# good rates — frontend

React (Create React App) UI for Birr. See the [root README](../README.md) for the full setup.

```sh
cp .env.example .env   # Primus appId/templateId, signer URL, oracle + ETB addresses
npm install
npm start              # http://localhost:3000
npm test
npm run build
```

| File | Role |
| --- | --- |
| `src/config.js` | Reads `REACT_APP_*` env vars and reports what's missing |
| `src/primus.js` | Primus zkTLS flow (init → sign via `server/` → attest → verify) |
| `src/chain.js` | ethers v5 contracts, wallet/network switching, attestation → struct, revert decoding |
| `src/polyfills.js` | `Buffer` global for the Primus SDK (must be imported first) |
| `src/abi/` | ABIs from `contracts/out` (regenerate after contract changes) |

Regenerate the ABIs:

```sh
cd ../contracts && forge build
jq '{abi: .abi}' out/ETB.sol/ETB.json > ../setb_frontend/src/abi/ETB.json
jq '{abi: .abi}' out/NBERateOracle.sol/NBERateOracle.json > ../setb_frontend/src/abi/NBERateOracle.json
```
