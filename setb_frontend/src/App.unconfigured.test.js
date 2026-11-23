import { render, screen } from "@testing-library/react";
import App from "./App";

jest.mock("@primuslabs/zktls-js-sdk", () => ({ PrimusZKTLS: jest.fn() }));
jest.mock("./config", () => ({
  ...jest.requireActual("./config"),
  missingConfig: () => ["REACT_APP_ORACLE_ADDRESS", "REACT_APP_ETB_ADDRESS"],
}));

test("shows missing-config warning and disables actions when unconfigured", () => {
  render(<App />);
  expect(screen.getByRole("alert")).toHaveTextContent(/REACT_APP_ORACLE_ADDRESS/);
  expect(screen.getByRole("button", { name: /prove latest nbe rate/i })).toBeDisabled();
  expect(screen.getByRole("button", { name: /^swap$/i })).toBeDisabled();
});
