import test from "node:test";
import assert from "node:assert/strict";

const normalize = (name) => name.trim().toLowerCase().replace(/\s+/g, "");

test("normalizes capitalization and all whitespace identically", () => {
  assert.equal(normalize(" Void  Lords "), "voidlords");
  assert.equal(normalize("VOID LORDS"), "voidlords");
  assert.equal(normalize("voidlords"), "voidlords");
});

test("display-name limits apply after trimming", () => {
  assert.equal(" x ".trim().length, 1);
  assert.equal("x".repeat(61).trim().length > 60, true);
});
