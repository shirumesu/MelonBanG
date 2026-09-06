import { spawn } from "node:child_process";
import { resolve } from "node:path";
import { existsSync } from "node:fs";
import { cp, copyFile, mkdir, writeFile } from "node:fs/promises";

function run(command, args, cwd = process.cwd(), env = process.env) {
  return new Promise((ok, fail) => {
    const child = spawn(command, args, {
      cwd,
      env,
      stdio: "inherit",
      shell: process.platform === "win32" && /\.(bat|cmd)$/.test(command)
    });
    child.once("error", fail);
    child.once("exit", (code) => (code === 0 ? ok() : fail(new Error(`${command}: ${code}`))));
  });
}
const flutter = process.env.FLUTTER_ROOT
  ? resolve(process.env.FLUTTER_ROOT, "bin/flutter.bat")
  : "flutter.bat";
await import("./build-service.mjs");
const env = {
  ...process.env,
  MELONBANG_CONFIG_DIR: process.env.MELONBANG_CONFIG_DIR || process.cwd(),
  MELONBANG_SERVICE: resolve("build/service/host.cjs"),
  MELONBANG_NODE: process.execPath
};
if (!["build", "stage"].includes(process.argv[2])) {
  await run(flutter, ["run", "-d", "windows"], resolve("desktop"), env);
} else {
  if (process.argv[2] !== "stage")
    await run(flutter, ["build", "windows", "--release"], resolve("desktop"), env);
  const output = resolve("desktop/build/windows/x64/runner/Release/service");
  await mkdir(output, { recursive: true });
  await cp("build/service", output, { recursive: true });
  await copyFile(process.execPath, resolve(output, "node.exe"));
  // Only the torrent runtime needs external packages in the desktop bundle.
  await writeFile(
    resolve(output, "package.json"),
    JSON.stringify({ private: true, dependencies: { webtorrent: "3.0.16" } })
  );
  await run("npm.cmd", ["install", "--omit=dev", "--no-audit", "--no-fund"], output);
  const notices = ["node_modules/ffmpeg-static/LICENSE", "node_modules/webtorrent/LICENSE"];
  for (const file of notices)
    if (existsSync(file))
      await copyFile(
        file,
        resolve(output, file.includes("ffmpeg") ? "FFMPEG-LICENSE" : "WEBTORRENT-LICENSE")
      );
  console.log(`Windows application: ${resolve(output, "../melonbang.exe")}`);
}
