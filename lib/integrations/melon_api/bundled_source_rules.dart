// Bundled fallback for the declarative rules served by Melon API.
const bundledSourceRules = r'''{
  "engine": 2,
  "version": "2026.10.10.1",
  "updatedAt": "2026-10-10T08:00:00Z",
  "rules": [
    {
      "id": "modu",
      "name": "魔都资源",
      "engine": "maccms-api",
      "minEngine": 1,
      "baseUrls": ["https://www.moduzy.com", "https://caiji.moduapi.cc"],
      "website": "https://moduzy.com",
      "search": {"url": "/api.php/provide/vod/?ac=detail&wd={query}"},
      "detail": {"url": "/api.php/provide/vod/?ac=detail&ids={id}"},
      "headers": {},
      "lineFilter": "^modum3u8$",
      "playlistFilter": {"foreignPathBlocks": true},
      "test": {"subject": "葬送的芙莉莲", "minEpisodes": 28},
      "disabled": false
    },
    {
      "id": "bilibili-video",
      "name": "Bilibili（外接）",
      "engine": "bilibili-web",
      "minEngine": 2,
      "builtinBefore": 2,
      "baseUrls": ["https://api.bilibili.com"],
      "website": "https://www.bilibili.com",
      "manualOnly": true,
      "description": "访客播放，按实际可用画质打开。投稿需确认内容和分 P；会员与地区限制由 B 站决定。",
      "disabled": false
    },
    {
      "id": "dmhy",
      "name": "动漫花园",
      "engine": "rss",
      "kind": "torrent",
      "minEngine": 2,
      "builtinBefore": 2,
      "baseUrls": ["https://share.dmhy.org"],
      "website": "https://share.dmhy.org",
      "search": {"url": "/topics/rss/rss.xml?keyword={query}"},
      "metadata": {"parser": "dmhy", "url": "/topics/list?keyword={query}"},
      "test": {"subject": "葬送的芙莉莲"},
      "disabled": false
    },
    {
      "id": "mikan",
      "name": "蜜柑计划",
      "engine": "rss",
      "kind": "torrent",
      "minEngine": 2,
      "builtinBefore": 2,
      "baseUrls": ["https://mikanani.me"],
      "website": "https://mikanani.me",
      "search": {"url": "/RSS/Search?searchstr={query}"},
      "metadata": {"parser": "mikan", "url": "/Home/Search?searchstr={query}"},
      "test": {"subject": "葬送的芙莉莲"},
      "disabled": false
    }
  ]
}
''';
