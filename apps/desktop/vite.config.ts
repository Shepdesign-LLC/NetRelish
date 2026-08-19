import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Tauri expects a fixed port and no auto-open.
export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: {
    port: 5273,
    strictPort: true,
    watch: { ignored: ["**/src-tauri/**"] },
  },
  build: {
    // WKWebView on macOS 13+ handles modern syntax fine.
    target: "safari15",
    sourcemap: process.env.TAURI_ENV_DEBUG === "true",
    minify: process.env.TAURI_ENV_DEBUG === "true" ? false : "esbuild",
  },
});
