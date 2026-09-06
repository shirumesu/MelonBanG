import { mkdir, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
await mkdir("temp/verification", { recursive: true });
await writeFile(
  "temp/verification/sample.ass",
  `[Script Info]
ScriptType: v4.00+
PlayResX: 640
PlayResY: 360
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,24,&H0000FFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,1,2,10,10,24,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,0:00:20.00,Default,,0,0,0,,ASS subtitle rendered by libass
`
);
const result = spawnSync(
  require("ffmpeg-static"),
  [
    "-hide_banner",
    "-loglevel",
    "error",
    "-y",
    "-f",
    "lavfi",
    "-i",
    "testsrc2=size=640x360:rate=24",
    "-f",
    "lavfi",
    "-i",
    "anullsrc=r=48000:cl=stereo",
    "-f",
    "lavfi",
    "-i",
    "anullsrc=r=44100:cl=stereo",
    "-i",
    "temp/verification/sample.ass",
    "-map",
    "0:v",
    "-map",
    "1:a",
    "-map",
    "2:a",
    "-map",
    "3:s",
    "-t",
    "20",
    "-c:v",
    "libx265",
    "-preset",
    "ultrafast",
    "-x265-params",
    "log-level=error:pools=2",
    "-pix_fmt",
    "yuv420p10le",
    "-c:a",
    "aac",
    "-c:s",
    "ass",
    "-metadata:s:a:0",
    "language=jpn",
    "-metadata:s:a:1",
    "language=eng",
    "temp/verification/native-hevc-10bit.mkv"
  ],
  { stdio: "inherit", windowsHide: true }
);
if (result.status !== 0) throw new Error("Could not generate native playback fixture");
