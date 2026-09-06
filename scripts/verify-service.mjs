import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const directory = await mkdtemp(join(tmpdir(), "melonbang-native-test-"));
const file = join(directory, "native 10bit sample.mkv");
await writeFile(file, "The native host must not probe, decode, or transcode media.");
const processHandle = spawn(
  process.argv[3] || process.execPath,
  [process.argv[2] || "build/service/host.cjs"],
  {
    env: { ...process.env, MELONBANG_DATA_DIR: directory, MELONBANG_CONFIG_DIR: directory },
    stdio: ["pipe", "pipe", "pipe"]
  }
);
let next = 0;
const pending = new Map();
const events = [];
createInterface({ input: processHandle.stdout }).on("line", (line) => {
  const message = JSON.parse(line);
  if (message.event) events.push(message);
  else {
    const task = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) task?.reject(new Error(message.error));
    else task?.resolve(message.result);
  }
});
processHandle.stderr.on("data", () => {});
function call(method, ...args) {
  return new Promise((resolve, reject) => {
    const id = ++next;
    pending.set(id, { resolve, reject });
    processHandle.stdin.write(JSON.stringify({ id, method, args }) + "\n");
  });
}
const timeout = setTimeout(() => {
  processHandle.kill();
  throw new Error("Native service smoke timed out");
}, 20000);
try {
  assert.equal((await call("health")).player, "media_kit");
  assert.equal(await call("bangumi.getSession"), null);
  assert.deepEqual(await call("download.list"), { tasks: [], files: [] });
  await assert.rejects(call("unknown"), /未知操作/);
  const session = await call("playback.startLocal", {
    path: resolve(file),
    subjectId: 123,
    episodeId: 456
  });
  assert.equal(session.status, "ready");
  assert.equal(session.source.deliveryMode, "direct");
  assert.ok(session.source.url.startsWith("file:///"));
  assert.equal(session.durationSeconds, null);
  const eventCount = events.length;
  await call("playback.updateProgress", {
    sessionId: session.id,
    positionSeconds: 25,
    durationSeconds: 120,
    timelineOffsetSeconds: 0,
    paused: true,
    ended: false
  });
  assert.equal(events.length, eventCount, "Progress updates must not resend all danmaku");
  const saved = await call("playback.getEpisodeProgress", { subjectId: 123, episodeId: 456 });
  assert.equal(saved.positionSeconds, 25);
  assert.equal(saved.completed, false);
  await call("playback.updateProgress", {
    sessionId: session.id,
    positionSeconds: 120,
    durationSeconds: 120,
    timelineOffsetSeconds: 0,
    paused: true,
    ended: true
  });
  assert.equal(
    (await call("playback.getEpisodeProgress", { subjectId: 123, episodeId: 456 })).completed,
    true
  );
  await assert.rejects(
    call("playback.updateProgress", { sessionId: session.id, positionSeconds: -1 }),
    /./
  );
  console.log(
    "Native service: direct file handoff, progress persistence, validation, and protocol passed."
  );
} finally {
  clearTimeout(timeout);
  processHandle.stdin.end();
}
