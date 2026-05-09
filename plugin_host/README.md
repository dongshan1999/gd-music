# Plugin Host

Minimal local Node.js host for MusicFree-compatible `.js` plugins.

## Run

```bash
npm install
npm start
```

Default address:

```text
http://127.0.0.1:31840
```

## Endpoints

- `GET /health`
- `GET /plugins`
- `GET /plugin_vars?plugin_id=<name-or-id>`
- `POST /plugin_vars`
- `POST /install`
- `POST /search`
- `POST /source`
- `POST /lyric`
- `POST /toplists`

## Notes

- Plugin files are stored under `plugin_host/data/plugins/`
- Plugin metadata and user variables are stored in `plugin_host/data/plugins.json`
- The Godot project will try to start this host automatically on desktop by running:

```text
node res://plugin_host/src/server.js
```
