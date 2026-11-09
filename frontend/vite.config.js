/*
  vite.config.js
  author: Kabera Clapton

  description: Vite build config. Output goes to dist/, which deploy-frontend.sh syncs to S3.
*/
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react()],
  build: {
    sourcemap: false,
    // Amplify UI's sign-in screen is most of the bundle (~215 kB gzipped); acceptable for an
    // internal tool, so raise the warning limit rather than split the code.
    chunkSizeWarningLimit: 1000,
  },
});
