import type { BangumiBridge, SubjectDetail } from "../../shared/contracts/bangumi";
import { BangumiRepository } from "../bangumi/BangumiRepository";
import { MelonApiClient } from "../bangumi/MelonApiClient";
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
  const melonApi = new MelonApiClient();

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
    async getSubject(subjectId) {
      return toPublicSubjectDetail(await melonApi.getSubject(subjectId));
    },
    async searchSubjects(keyword) {
      const subjects = await melonApi.searchSubjects(keyword);
      return subjects.map((subject) => ({
        subjectId: subject.id,
        name: subject.name,
        nameCn: subject.nameCn,
        coverUrl: subject.coverUrl,
        episodeTotal: subject.totalEpisodes,
        summary: subject.summary
      }));
    },
    getTrendingCurrent() {
      return melonApi.getTrendingCurrent();
    },
    getTodaySchedule() {
      return melonApi.getTodaySchedule();
    },
    getCalendar() {
      return melonApi.getScheduleWeek();
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

function toPublicSubjectDetail(
  subject: Awaited<ReturnType<MelonApiClient["getSubject"]>>
): SubjectDetail {
  return {
    subjectId: subject.id,
    name: subject.name,
    nameCn: subject.nameCn,
    coverUrl: subject.coverUrl,
    summary: subject.summary,
    episodeTotal: subject.totalEpisodes,
    airDate: subject.date,
    platform: subject.platform,
    score: subject.score,
    rank: subject.rank,
    ratingCount: subject.ratingCount,
    collectionStats: subject.collectionStats,
    metaTags: subject.metaTags,
    tags: subject.tags,
    infoBox: subject.infoBox,
    season: subject.season,
    characters: subject.characters,
    staff: subject.staff,
    relatedSubjects: subject.relatedSubjects,
    comments: subject.comments,
    topics: subject.topics,
    schedule: subject.schedule,
    sourceNotes: subject.sourceNotes,
    collection: null,
    episodes: subject.episodes.map((episode) => ({
      episodeId: episode.id,
      subjectId: episode.subjectId,
      sort: episode.sort,
      name: episode.name,
      nameCn: episode.nameCn,
      status: "unwatched"
    }))
  };
}
