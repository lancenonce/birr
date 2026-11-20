// All deployment-specific values come from env (see .env.example). CRA inlines REACT_APP_* at build time.
const env = process.env;

export const SEPOLIA_CHAIN_ID = 11155111;
export const UNICHAIN_SEPOLIA_CHAIN_ID = 1301;

export const config = {
  primusAppId: env.REACT_APP_PRIMUS_APP_ID || "",
  primusTemplateId: env.REACT_APP_PRIMUS_TEMPLATE_ID || "",
  signerUrl: (env.REACT_APP_SIGNER_URL || "http://localhost:9000").replace(/\/$/, ""),
  sepoliaRpcUrl: env.REACT_APP_SEPOLIA_RPC_URL || "https://ethereum-sepolia-rpc.publicnode.com",
  oracleAddress: env.REACT_APP_ORACLE_ADDRESS || "",
  etbAddress: env.REACT_APP_ETB_ADDRESS || "",
  etbUnichainAddress: env.REACT_APP_ETB_UNICHAIN_ADDRESS || "0xdD3324AB2e26268E15c792Cb8c1f0eD8bA9A4C76",
  usdcAddress: env.REACT_APP_USDC_ADDRESS || "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
};

export function missingConfig(cfg = config) {
  const required = {
    REACT_APP_PRIMUS_APP_ID: cfg.primusAppId,
    REACT_APP_PRIMUS_TEMPLATE_ID: cfg.primusTemplateId,
    REACT_APP_ORACLE_ADDRESS: cfg.oracleAddress,
    REACT_APP_ETB_ADDRESS: cfg.etbAddress,
  };
  return Object.entries(required)
    .filter(([, v]) => !v)
    .map(([k]) => k);
}
