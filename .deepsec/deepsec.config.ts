import { defineConfig } from "deepsec/config";

export default defineConfig({
  projects: [
    { id: "ccblocks", root: ".." },
    // <deepsec:projects-insert-above>
  ],
});
