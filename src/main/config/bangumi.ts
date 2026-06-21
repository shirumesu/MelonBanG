import { app } from "electron";

export type BangumiOAuthConfig = {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  userAgent: string;
};

export function getBangumiOAuthConfig(): BangumiOAuthConfig | null {
  const clientId = process.env.BANGUMI_CLIENT_ID?.trim();
  const clientSecret = process.env.BANGUMI_CLIENT_SECRET?.trim();
  const redirectUri = process.env.BANGUMI_REDIRECT_URI?.trim();

  if (!clientId || !clientSecret || !redirectUri) {
    return null;
  }

  return {
    clientId,
    clientSecret,
    redirectUri,
    userAgent: process.env.BANGUMI_USER_AGENT?.trim() || defaultUserAgent()
  };
}

function defaultUserAgent(): string {
  return `83977/melonbang/${app.getVersion()} (https://github.com/83977/melonbang)`;
}
