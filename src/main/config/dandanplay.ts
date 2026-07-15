import { app } from "electron";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

export type DandanplayConfig = {
  appId: string;
  appSecret: string;
  userAgent: string;
};

type LocalDandanplayConfig = Partial<DandanplayConfig>;

export function getDandanplayConfig(): DandanplayConfig | null {
  const localConfig = readLocalDandanplayConfig();
  const appId = readConfigValue("DANDANPLAY_APP_ID", localConfig.appId);
  const appSecret = readConfigValue("DANDANPLAY_APP_SECRET", localConfig.appSecret);

  if (!appId || !appSecret) {
    return null;
  }

  return {
    appId,
    appSecret,
    userAgent:
      readConfigValue("DANDANPLAY_USER_AGENT", localConfig.userAgent) ||
      `melonbang/${app.getVersion()}`
  };
}

function readConfigValue(envName: string, localValue?: string): string | undefined {
  return process.env[envName]?.trim() || localValue?.trim() || undefined;
}

function readLocalDandanplayConfig(): LocalDandanplayConfig {
  if (app.isPackaged) {
    return {};
  }

  const configPath = join(app.getAppPath(), "temp", "dandanplay.json");
  if (!existsSync(configPath)) {
    return {};
  }

  try {
    return JSON.parse(readFileSync(configPath, "utf8")) as LocalDandanplayConfig;
  } catch {
    return {};
  }
}
