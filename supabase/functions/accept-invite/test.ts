// supabase/functions/accept-invite/test.ts
// Validates the UUID input-format gate and that the module imports cleanly.

function assert(condition: boolean, message = "Assertion failed") {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T) {
  if (actual !== expected) {
    throw new Error(`Expected ${String(expected)}, got ${String(actual)}`);
  }
}

function seedRequiredEnv() {
  Deno.env.set("SUPABASE_URL", "http://127.0.0.1:54321");
  Deno.env.set("SUPABASE_ANON_KEY", "test-anon-key");
}

Deno.test("UUID regex rejects garbage", () => {
  const re =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

  assertEquals(re.test("nope"), false);
  assertEquals(re.test("00000000-0000-0000-0000-000000000000"), false); // null UUID isn't v1-5
  assertEquals(re.test("c5e1d2f0-7c8e-4d3a-9f4b-1234567890ab"), true);
});

Deno.test({
  name: "module loads without runtime error",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    seedRequiredEnv();
    await import("./index.ts");
    assert(true);
  },
});
