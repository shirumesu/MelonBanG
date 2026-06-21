import { app } from "electron";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

export type BangumiOAuthConfig = {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  userAgent: string;
};

type LocalBangumiOAuthConfig = Partial<BangumiOAuthConfig>;

export const DEFAULT_BANGUMI_REDIRECT_URI = "http://127.0.0.1:14567/callback";

export function getBangumiOAuthConfig(): BangumiOAuthConfig | null {
  const localConfig = readLocalBangumiOAuthConfig();
  const clientId = readConfigValue("BANGUMI_CLIENT_ID", localConfig.clientId);
  const clientSecret = readConfigValue("BANGUMI_CLIENT_SECRET", localConfig.clientSecret);
  const redirectUri =
    readConfigValue("BANGUMI_REDIRECT_URI", localConfig.redirectUri) ??
    DEFAULT_BANGUMI_REDIRECT_URI;

  if (!clientId || !clientSecret) {
    return null;
  }

  return {
    clientId,
    clientSecret,
    redirectUri,
    userAgent: readConfigValue("BANGUMI_USER_AGENT", localConfig.userAgent) || defaultUserAgent()
  };
}

function defaultUserAgent(): string {
  return `83977/melonbang/${app.getVersion()} (https://github.com/83977/melonbang)`;
}

function readConfigValue(envName: string, localValue?: string): string | undefined {
  return process.env[envName]?.trim() || localValue?.trim() || undefined;
}

function readLocalBangumiOAuthConfig(): LocalBangumiOAuthConfig {
  if (app.isPackaged) {
    return {};
  }

  const configPath = join(app.getAppPath(), "temp", "bangumi-oauth.json");
  if (!existsSync(configPath)) {
    return {};
  }

  const parsed = JSON.parse(readFileSync(configPath, "utf8")) as LocalBangumiOAuthConfig;
  return parsed;
}
