import { sendEvent } from "logflare-js";
import { describe, expect, test } from "@jest/globals";
test(" send event", async () => {
  expect(sendEvent()).toBe(true);
});
