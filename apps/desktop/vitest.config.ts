import { defineConfig } from "vitest/config";

// Unit tests only, and deliberately narrow: the tier logic in src/lib/auth.ts
// decides when a note may leave the Mac readable (CLAUDE.md §4a), so it is the
// one place worth pinning down without a running app. No jsdom — auth.ts
// touches no DOM once ./sync and ./crypto are stubbed.
export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
  },
});
