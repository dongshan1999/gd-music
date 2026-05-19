# MusicFree Plugin Migration Report

Generated plugins: 13

| Plugin | Platform | Difficulty | Methods | Dependencies |
| --- | --- | --- | --- | --- |
| kuaishou | 快手 | low | search, getMediaSource | axios |
| suno | suno | low | getLyric, getTopLists, getTopListDetail | axios |
| yinyuetai | 音悦台 | low | search, getMediaSource | axios |
| youtube | Youtube | low | search, getMediaSource | axios |
| geciqianxun | 歌词千寻 | medium | search, getLyric | axios, cheerio |
| geciwang | 歌词网 | medium | search, getLyric | axios, cheerio |
| maoerfm | 猫耳FM | medium | search, getMediaSource, getAlbumInfo | axios, he |
| navidrome | Navidrome | medium | search, getMediaSource | axios, crypto-js |
| udio | udio | medium | search, getMediaSource, getLyric, getTopLists, getTopListDetail | axios |
| webdav | WebDAV | medium | search, getMediaSource, getTopLists, getTopListDetail | webdav |
| airsonic | Airsonic Advanced | high | search, getMediaSource, getLyric, getAlbumInfo, getArtistWorks, getTopLists, getTopListDetail | axios, crypto-js |
| audiomack | Audiomack | high | search, getMediaSource, getAlbumInfo, getArtistWorks, getTopLists, getTopListDetail | axios, cheerio, crypto-js, dayjs |
| bilibili | bilibili | high | search, getMediaSource, getAlbumInfo, getArtistWorks, importMusicSheet, getTopLists, getTopListDetail | axios, cheerio, crypto-js, dayjs, he |

## Suggested order

- kuaishou: low - replace axios calls with Godot HTTPRequest or HTTPClient helper
- suno: low - replace axios calls with Godot HTTPRequest or HTTPClient helper
- yinyuetai: low - replace axios calls with Godot HTTPRequest or HTTPClient helper
- youtube: low - replace axios calls with Godot HTTPRequest or HTTPClient helper
- geciqianxun: medium - replace axios calls with Godot HTTPRequest or HTTPClient helper
- geciwang: medium - replace axios calls with Godot HTTPRequest or HTTPClient helper
- maoerfm: medium - replace axios calls with Godot HTTPRequest or HTTPClient helper
- navidrome: medium - replace axios calls with Godot HTTPRequest or HTTPClient helper
- udio: medium - replace axios calls with Godot HTTPRequest or HTTPClient helper
- webdav: medium - replace webdav client calls with direct WebDAV HTTP methods or a Godot-side adapter
- airsonic: high - replace axios calls with Godot HTTPRequest or HTTPClient helper
- audiomack: high - replace axios calls with Godot HTTPRequest or HTTPClient helper
- bilibili: high - replace axios calls with Godot HTTPRequest or HTTPClient helper
