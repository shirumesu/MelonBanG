import type { BangumiBridge } from "../../shared/contracts/bangumi";
import { BangumiRepository } from "../bangumi/BangumiRepository";
import { getBangumiOAuthConfig } from "../config/bangumi";
import { getMockBangumiService } from "./mockBangumiService";

let serviceInstance: BangumiBridge | null = null;

export function getBangumiService(): BangumiBridge {
  if (serviceInstance) {
    return serviceInstance;
  }

  const config = getBangumiOAuthConfig();

  if (!config) {
    serviceInstance = getMockBangumiService();
    return serviceInstance;
  }

  serviceInstance = new BangumiRepository(config);
  return serviceInstance;
}
