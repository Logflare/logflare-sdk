import LogflareJs from "../src/main";
import { vi, Mock, beforeEach, expect, test } from "vitest";
import { describe } from "node:test";
beforeEach(() => {
  vi.clearAllMocks();
  (fetch as Mock).mockImplementation(async () => {
    return new Response(
      JSON.stringify({
        message: "msg from server",
      })
    );
  });
});
describe("ok request", () => {
  beforeEach(() => {
    (fetch as Mock).mockImplementation(async () => {
      return new Response(
        JSON.stringify({
          message: "msg from server",
        })
      );
    });
  });

  test("sendEvent() and sendEvents()", async () => {
    const client = new LogflareJs({
      sourceToken: "some token",
      apiKey: "some key",
    });
    expect(
      await client.sendEvent({
        message: "some event",
      })
    ).toMatchObject({ message: "msg from server" });
    expect(
      await client.sendEvents([
        {
          message: "some event",
        },
      ])
    ).toMatchObject({ message: "msg from server" });
  });
});

test("onError callback", async () => {
  (fetch as Mock).mockImplementation(async () => {
    throw Error("NetworkError");
  });

  const mockFn = vi.fn();
  const client = new LogflareJs({
    sourceToken: "some token",
    apiKey: "some key",
    onError: mockFn,
  });

  const response: any = await client.sendEvent({
    message: "some event",
  });
  expect(response).toBeInstanceOf(Error);
  expect(response.message).toEqual("NetworkError");
  expect(mockFn).toBeCalledTimes(1);
});
