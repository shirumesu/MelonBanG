// Bundled fallback for the declarative rules served by Melon API.
const builtinSourceRules = r'''{
  "engine": 1,
  "version": "2026.10.02.2",
  "updatedAt": "2026-10-02T07:45:11Z",
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
    }
  ]
}
''';
