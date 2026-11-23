import { bindings, defineConfig, defineWorker } from "cf/config";

export default defineConfig({
  worker: defineWorker({
    name: "analytics",
    entrypoint: "vinext/server/fetch-handler",
    compatibilityDate: "2026-11-17",
    compatibilityFlags: ["nodejs_compat"],
    assets: {
      htmlHandling: "none",
      notFoundHandling: "none",
      runWorkerFirst: ["/*", "!/_next/static/*", "!/*/_next/static/*"],
    },
    env: {
      ASSETS: bindings.assets(),
      ADMIN_BACKEND_URL: bindings.text("https://duka-pos-backend.brianbmk332.workers.dev"),
    },
  }),
});
