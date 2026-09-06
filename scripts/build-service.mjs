import { build } from "esbuild";
import { mkdir, copyFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { resolve } from "node:path";

const require = createRequire(import.meta.url);
await mkdir("build/service", { recursive: true });
await build({
  entryPoints: ["src/native/host.ts"],
  outfile: "build/service/host.cjs",
  bundle: true,
  platform: "node",
  format: "cjs",
  target: "node24",
  external: ["webtorrent"],
  alias: {
    electron: resolve("src/native/platform.ts"),
    "ffmpeg-static": resolve("src/native/ffmpeg.ts")
  }
});
await copyFile(require("ffmpeg-static"), "build/service/ffmpeg.exe");
