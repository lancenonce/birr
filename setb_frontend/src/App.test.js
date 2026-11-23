import { render, screen } from "@testing-library/react";
import App from "./App";

// The real SDK talks to the Primus browser extension and ships ESM that Jest doesn't transform.
jest.mock("@primuslabs/zktls-js-sdk", () => ({ PrimusZKTLS: jest.fn() }));

jest.mock("./config", () => ({
  ...jest.requireActual("./config"),
  missingConfig: () => [],
}));

const mockNow = Math.floor(Date.now() / 1000);
jest.mock("./chain", () => {
  const { ethers: e } = jest.requireActual("ethers");
  return {
    ...jest.requireActual("./chain"),
    oracleContract: () => ({
      getRate: async () => [
        e.utils.parseEther("162.8054"),
        e.utils.parseEther("161.1935"),
        e.BigNumber.from(mockNow - 120),
      ],
    }),
    etbContract: () => ({
      maxRateAge: async () => e.BigNumber.from(86400),
      quoteOfficial: async () => [e.BigNumber.from(6_142_302)],
    }),
  };
});

test("renders the zkTLS-verified official rate read from the oracle", async () => {
  render(<App />);
  expect(await screen.findByText(/162\.8054 ETB\/USD selling/)).toBeInTheDocument();
  expect(screen.getByText(/161\.1935 buying/)).toBeInTheDocument();
  expect(screen.getByText(/2m ago/)).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /prove latest nbe rate/i })).toBeEnabled();
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();
});
