jest.mock("@primuslabs/zktls-js-sdk", () => ({ PrimusZKTLS: jest.fn() }));

const { signRequest, humanizePrimusError } = require("./primus");

test("signRequest posts signParams and returns signResult", async () => {
  const fetchImpl = jest.fn(async () => ({ ok: true, json: async () => ({ signResult: "signed!" }) }));
  await expect(signRequest('{"a":1}', fetchImpl)).resolves.toBe("signed!");
  const [url, init] = fetchImpl.mock.calls[0];
  expect(url).toBe("http://localhost:9000/sign");
  expect(JSON.parse(init.body)).toEqual({ signParams: '{"a":1}' });
});

test("signRequest surfaces server errors", async () => {
  const fetchImpl = async () => ({ ok: false, status: 400, json: async () => ({ error: "attTemplateID not allowed" }) });
  await expect(signRequest("{}", fetchImpl)).rejects.toThrow(/attTemplateID not allowed/);
});

test("humanizePrimusError explains a missing extension", () => {
  expect(humanizePrimusError({ code: "00006" }).message).toMatch(/extension/);
});
