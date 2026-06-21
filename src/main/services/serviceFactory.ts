import type { BangumiBridge } from "../../shared/contracts/bangumi";
import { BangumiRepository } from "../bangumi/BangumiRepository";
import { getBangumiOAuthConfig } from "../config/bangumi";

let serviceInstance: BangumiBridge | null = null;

const missingOAuthConfigMessage =
  "Bangumi OAuth 未配置。请配置 BANGUMI_CLIENT_ID 和 BANGUMI_CLIENT_SECRET，或在开发环境创建 temp/bangumi-oauth.json。";

export function getBangumiService(): BangumiBridge {
  if (serviceInstance) {
    return serviceInstance;
  }

  const config = getBangumiOAuthConfig();

  if (!config) {
    return createUnconfiguredBangumiService();
  }

  serviceInstance = new BangumiRepository(config);
  return serviceInstance;
}

function createUnconfiguredBangumiService(): BangumiBridge {
  return {
    getSession() {
      return Promise.resolve(null);
    },
    signIn() {
      return Promise.reject(new Error(missingOAuthConfigMessage));
    },
    signOut() {
      return Promise.resolve();
    },
    listCollection() {
      return Promise.resolve([]);
    },
    getSubject() {
      return Promise.reject(new Error(missingOAuthConfigMessage));
    },
    searchSubjects() {
      return Promise.reject(new Error(missingOAuthConfigMessage));
    },
    getCalendar() {
      return Promise.resolve([]);
    },
    updateTracking() {
      return Promise.reject(new Error(missingOAuthConfigMessage));
    },
    refreshCollection() {
      return Promise.resolve({
        stale: true,
        pendingMutationCount: 0,
        lastSyncError: missingOAuthConfigMessage
      });
    },
    getSyncState() {
      return Promise.resolve({
        stale: true,
        pendingMutationCount: 0,
        lastSyncError: missingOAuthConfigMessage
      });
    }
  };
}
