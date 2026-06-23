import { shell } from "electron";
import { createServer } from "node:http";
import { URL } from "node:url";
import type { BangumiSession } from "../../shared/contracts/bangumi";
import type { BangumiOAuthConfig } from "../config/bangumi";
import { TokenStore, type TokenBundle } from "../store/tokenStore";

export type BangumiAccessToken = {
  accessToken: string;
  refreshToken: string;
  expiresAt: string;
  userId: string;
};

type OAuthTokenResponse = {
  access_token: string;
  expires_in: number;
  refresh_token: string;
  token_type: string;
  user_id?: number | string;
};

type TokenStatusResponse = {
  expires: number;
  user_id: number | string;
};

type MeResponse = {
  id: number;
  username: string;
  nickname: string;
  avatar: {
    small: string;
    medium: string;
    large: string;
  };
};

type FormHeaders = {
  Accept: "application/json";
  "Content-Type": "application/x-www-form-urlencoded";
  "User-Agent": string;
};

export class BangumiOAuth {
  private readonly tokenStore = new TokenStore();
  private activeAuthorization: AbortController | null = null;

  constructor(private readonly config: BangumiOAuthConfig) {}

  getStoredSession(): Promise<BangumiSession | null> {
    const bundle = this.tokenStore.read();
    if (!bundle) {
      return Promise.resolve(null);
    }

    return Promise.resolve(JSON.parse(bundle.sessionPayload) as BangumiSession);
  }

  async getValidAccessToken(): Promise<BangumiAccessToken | null> {
    const bundle = this.tokenStore.read();
    if (!bundle) {
      return null;
    }

    if (!isExpired(bundle.expiresAt)) {
      const session = JSON.parse(bundle.sessionPayload) as BangumiSession;
      return {
        accessToken: bundle.accessToken,
        refreshToken: bundle.refreshToken,
        expiresAt: bundle.expiresAt,
        userId: session.userId
      };
    }

    try {
      const refreshed = await this.refresh(bundle.refreshToken);
      return refreshed;
    } catch {
      this.clearSession();
      return null;
    }
  }

  async signIn(): Promise<BangumiSession> {
    this.cancelSignIn();
    const state = crypto.randomUUID();
    const redirect = new URL(this.config.redirectUri);
    const controller = new AbortController();
    this.activeAuthorization = controller;

    try {
      const code = await waitForAuthorizationCode({
        authorizeUrl: buildAuthorizeUrl(this.config, state),
        redirectUrl: redirect,
        expectedState: state,
        signal: controller.signal
      });

      const token = await this.exchangeCode(code, state);
      const session = await this.fetchSession(token.accessToken);
      this.persistToken(token, session);
      return session;
    } finally {
      if (this.activeAuthorization === controller) {
        this.activeAuthorization = null;
      }
    }
  }

  clearSession(): void {
    this.cancelSignIn();
    this.tokenStore.clear();
  }

  cancelSignIn(): void {
    this.activeAuthorization?.abort();
    this.activeAuthorization = null;
  }

  private async exchangeCode(code: string, state: string): Promise<BangumiAccessToken> {
    const payload = {
      grant_type: "authorization_code",
      client_id: this.config.clientId,
      client_secret: this.config.clientSecret,
      code,
      redirect_uri: this.config.redirectUri,
      state
    };

    const response = await fetch("https://bgm.tv/oauth/access_token", {
      method: "POST",
      headers: requestHeaders(this.config.userAgent),
      body: toFormBody(payload)
    });

    if (!response.ok) {
      throw new Error(`Bangumi OAuth code exchange failed with ${response.status}.`);
    }

    const data = (await response.json()) as OAuthTokenResponse;
    return {
      accessToken: data.access_token,
      refreshToken: data.refresh_token,
      expiresAt: new Date(Date.now() + data.expires_in * 1000).toISOString(),
      userId: String(data.user_id ?? "")
    };
  }

  private async refresh(refreshToken: string): Promise<BangumiAccessToken> {
    const payload = {
      grant_type: "refresh_token",
      client_id: this.config.clientId,
      client_secret: this.config.clientSecret,
      refresh_token: refreshToken,
      redirect_uri: this.config.redirectUri
    };

    const response = await fetch("https://bgm.tv/oauth/access_token", {
      method: "POST",
      headers: requestHeaders(this.config.userAgent),
      body: toFormBody(payload)
    });

    if (!response.ok) {
      throw new Error(`Bangumi OAuth refresh failed with ${response.status}.`);
    }

    const data = (await response.json()) as OAuthTokenResponse;
    const tokenStatus = await this.queryTokenStatus(data.access_token);
    const bundle = this.tokenStore.read();
    const session = bundle ? (JSON.parse(bundle.sessionPayload) as BangumiSession) : null;

    const token: BangumiAccessToken = {
      accessToken: data.access_token,
      refreshToken: data.refresh_token,
      expiresAt: new Date(Date.now() + data.expires_in * 1000).toISOString(),
      userId: String(tokenStatus.user_id)
    };

    if (session) {
      this.persistToken(token, session);
    }

    return token;
  }

  private async queryTokenStatus(accessToken: string): Promise<TokenStatusResponse> {
    const response = await fetch("https://bgm.tv/oauth/token_status", {
      method: "POST",
      headers: requestHeaders(this.config.userAgent),
      body: toFormBody({ access_token: accessToken })
    });

    if (!response.ok) {
      throw new Error(`Bangumi token status request failed with ${response.status}.`);
    }

    const tokenStatus = (await response.json()) as TokenStatusResponse;
    return tokenStatus;
  }

  private async fetchSession(accessToken: string): Promise<BangumiSession> {
    const response = await fetch("https://api.bgm.tv/v0/me", {
      headers: {
        Accept: "application/json",
        "User-Agent": this.config.userAgent,
        Authorization: `Bearer ${accessToken}`
      }
    });

    if (!response.ok) {
      throw new Error(`Bangumi /v0/me failed with ${response.status}.`);
    }

    const me = (await response.json()) as MeResponse;
    return {
      userId: String(me.id),
      username: me.username,
      nickname: me.nickname,
      avatarUrl: me.avatar.medium
    };
  }

  private persistToken(token: BangumiAccessToken, session: BangumiSession): void {
    const bundle: TokenBundle = {
      accessToken: token.accessToken,
      refreshToken: token.refreshToken,
      expiresAt: token.expiresAt,
      sessionPayload: JSON.stringify(session)
    };

    this.tokenStore.write(bundle);
  }
}

function buildAuthorizeUrl(config: BangumiOAuthConfig, state: string): string {
  const url = new URL("https://bgm.tv/oauth/authorize");
  url.searchParams.set("client_id", config.clientId);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("redirect_uri", config.redirectUri);
  url.searchParams.set("state", state);
  return url.toString();
}

function requestHeaders(userAgent: string): FormHeaders {
  return {
    Accept: "application/json",
    "Content-Type": "application/x-www-form-urlencoded",
    "User-Agent": userAgent
  };
}

function toFormBody(values: Record<string, string>): string {
  return new URLSearchParams(values).toString();
}

async function waitForAuthorizationCode(input: {
  authorizeUrl: string;
  redirectUrl: URL;
  expectedState: string;
  signal?: AbortSignal;
  timeoutMs?: number;
}): Promise<string> {
  return new Promise((resolve, reject) => {
    const hostname = input.redirectUrl.hostname || "127.0.0.1";
    const port = Number(input.redirectUrl.port);

    if (hostname !== "127.0.0.1" && hostname !== "localhost") {
      reject(new Error("Bangumi redirect URI must use localhost or 127.0.0.1."));
      return;
    }

    if (!Number.isInteger(port) || port <= 0) {
      reject(new Error("Bangumi redirect URI must include an explicit localhost port."));
      return;
    }

    let settled = false;
    let timeout: ReturnType<typeof setTimeout> | null = null;
    const abort = (): void => {
      finish(() => reject(new Error("Bangumi OAuth sign-in was cancelled.")));
    };
    const finish = (fn: () => void): void => {
      if (settled) {
        return;
      }

      settled = true;
      if (timeout) {
        clearTimeout(timeout);
      }
      input.signal?.removeEventListener("abort", abort);
      if (server.listening) {
        server.close();
      }
      fn();
    };

    const server = createServer((request, response) => {
      try {
        const requestUrl = new URL(request.url ?? "/", input.redirectUrl);
        const code = requestUrl.searchParams.get("code");
        const state = requestUrl.searchParams.get("state");

        if (!code) {
          throw new Error("Bangumi redirect did not include an authorization code.");
        }
        if (state !== input.expectedState) {
          throw new Error("Bangumi OAuth state mismatch.");
        }

        response.statusCode = 200;
        response.setHeader("Content-Type", "text/html; charset=utf-8");
        response.end(
          "<html><body><h1>melonbang</h1><p>Authorization received. You can return to the app.</p></body></html>"
        );
        finish(() => resolve(code));
      } catch (error) {
        response.statusCode = 400;
        response.setHeader("Content-Type", "text/plain; charset=utf-8");
        response.end("Authorization failed.");
        finish(() => reject(asError(error)));
      }
    });

    server.on("error", (error) => finish(() => reject(asError(error))));
    if (input.signal?.aborted) {
      abort();
      return;
    }
    input.signal?.addEventListener("abort", abort, { once: true });
    timeout = setTimeout(
      () => finish(() => reject(new Error("Bangumi OAuth sign-in timed out."))),
      input.timeoutMs ?? 5 * 60_000
    );
    server.listen(port, hostname, () => {
      void shell
        .openExternal(input.authorizeUrl)
        .catch((error) => finish(() => reject(asError(error))));
    });
  });
}

function isExpired(expiresAt: string): boolean {
  return Date.parse(expiresAt) <= Date.now() + 60_000;
}

function asError(error: unknown): Error {
  return error instanceof Error ? error : new Error(String(error));
}
