const http = require("http");
const fsp = require("fs/promises");
const path = require("path");
const vm = require("vm");
const crypto = require("crypto");
const { URL } = require("url");

const axios = require("axios");
const cheerio = require("cheerio");
const CryptoJs = require("crypto-js");
const bigInt = require("big-integer");
const dayjs = require("dayjs");
const FormData = require("form-data");
const he = require("he");
const qs = require("qs");
const webdav = require("webdav");

const HOST = process.env.PLUGIN_HOST_BIND || "127.0.0.1";
const PORT = Number(process.env.PLUGIN_HOST_PORT || 31840);
const ROOT_DIR = path.resolve(__dirname, "..");
const DATA_DIR = path.join(ROOT_DIR, "data");
const PLUGINS_DIR = path.join(DATA_DIR, "plugins");
const META_FILE = path.join(DATA_DIR, "plugins.json");

const SUPPORTED_PACKAGES = Object.freeze({
  axios,
  cheerio,
  "crypto-js": CryptoJs,
  "big-integer": bigInt,
  "form-data": FormData,
  dayjs,
  he,
  qs,
  webdav,
  "@react-native-cookies/cookies": {
    get: async () => ({}),
    set: async () => undefined,
    clearAll: async () => undefined
  }
});

class PluginHost {
  constructor() {
    this.plugins = new Map();
    this.pluginMeta = {};
  }

  async setup() {
    await ensureDir(DATA_DIR);
    await ensureDir(PLUGINS_DIR);
    this.pluginMeta = await readJsonFile(META_FILE, {});
    await this.loadInstalledPlugins();
  }

  async loadInstalledPlugins() {
    const entries = await fsp.readdir(PLUGINS_DIR, { withFileTypes: true }).catch(() => []);
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.endsWith(".js")) {
        continue;
      }
      const filePath = path.join(PLUGINS_DIR, entry.name);
      try {
        await this.loadPluginFromFile(filePath, false);
      } catch (error) {
        console.error("[plugin-host] Failed to load plugin:", filePath, error);
      }
    }
  }

  listPlugins() {
    const result = [];
    for (const plugin of this.plugins.values()) {
      result.push({
        id: plugin.id,
        name: plugin.name,
        version: plugin.instance.version || "",
        path: plugin.path,
        srcUrl: plugin.instance.srcUrl || "",
        supportedSearchType: plugin.instance.supportedSearchType || [],
        defaultSearchType: plugin.instance.defaultSearchType || "music",
        userVariables: Array.isArray(plugin.instance.userVariables) ? plugin.instance.userVariables : [],
        author: plugin.instance.author || "",
        description: plugin.instance.description || "",
        hasSearch: typeof plugin.instance.search === "function",
        hasGetMediaSource: typeof plugin.instance.getMediaSource === "function",
        hasGetLyric: typeof plugin.instance.getLyric === "function",
        hasGetTopLists: typeof plugin.instance.getTopLists === "function"
      });
    }
    return result.sort((a, b) => a.name.localeCompare(b.name, "zh-CN"));
  }

  async installFromUrl(url) {
    const response = await axios.get(url, {
      timeout: 10000,
      responseType: "text",
      headers: {
        "Cache-Control": "no-cache"
      }
    });
    return this.installFromCode(String(response.data), { srcUrl: url });
  }

  async installFromPath(inputPath) {
    const resolvedPath = path.resolve(inputPath);
    const stat = await fsp.stat(resolvedPath);

    if (stat.isFile()) {
      if (!resolvedPath.endsWith(".js")) {
        throw new Error("Selected file is not a .js plugin file.");
      }
      return await this.installPluginFile(resolvedPath, resolvedPath);
    }

    if (!stat.isDirectory()) {
      throw new Error("Selected path is neither a plugin file nor a plugin folder.");
    }

    const jsFiles = await this.collectJsFilesRecursively(resolvedPath);
    if (jsFiles.length === 0) {
      throw new Error("Selected folder does not contain a .js plugin file.");
    }

    const installedPlugins = [];
    const failedFiles = [];
    for (const filePath of jsFiles) {
      try {
        const result = await this.installPluginFile(filePath, resolvedPath);
        installedPlugins.push(result.plugin);
      } catch (error) {
        failedFiles.push({
          path: filePath,
          error: error?.message || "Invalid plugin file."
        });
        continue;
      }
    }

    if (installedPlugins.length === 0) {
      const firstFailure = failedFiles[0];
      if (firstFailure) {
        throw new Error(
          `Selected folder does not contain a valid MusicFree plugin. First error: ${firstFailure.error}`
        );
      }
      throw new Error("Selected folder does not contain a valid MusicFree plugin.");
    }

    return {
      ok: true,
      plugins: installedPlugins,
      installed_count: installedPlugins.length,
      failed_files: failedFiles
    };
  }

  async collectJsFilesRecursively(directoryPath) {
    const entries = await fsp.readdir(directoryPath, { withFileTypes: true });
    const jsFiles = [];

    for (const entry of entries) {
      const entryPath = path.join(directoryPath, entry.name);
      if (entry.isDirectory()) {
        jsFiles.push(...await this.collectJsFilesRecursively(entryPath));
        continue;
      }
      if (entry.isFile() && entry.name.endsWith(".js")) {
        jsFiles.push(entryPath);
      }
    }

    return jsFiles.sort((left, right) => left.localeCompare(right, "en"));
  }

  async installPluginFile(filePath, originalPath) {
    const code = await fsp.readFile(filePath, "utf8");
    return this.installFromCode(code, {
      originalPath,
      sourceFilePath: filePath
    });
  }

  async installFromCode(code, options = {}) {
    const mounted = this.mountPlugin(code, options);
    const targetFile = path.join(PLUGINS_DIR, `${mounted.id}.js`);
    await fsp.writeFile(targetFile, code, "utf8");

    mounted.path = targetFile;
    this.plugins.set(mounted.id, mounted);
    this.pluginMeta[mounted.id] = {
      id: mounted.id,
      name: mounted.name,
      path: targetFile,
      srcUrl: options.srcUrl || mounted.instance.srcUrl || "",
      installedAt: Date.now()
    };
    await this.saveMeta();

    return {
      ok: true,
      plugin: this.serializePlugin(mounted)
    };
  }

  async uninstall(pluginId) {
    const plugin = this.requirePlugin(pluginId);
    if (plugin.path) {
      await fsp.unlink(plugin.path).catch(() => undefined);
    }
    this.plugins.delete(plugin.id);
    delete this.pluginMeta[plugin.id];
    delete this.pluginMeta[`vars:${plugin.name}`];
    await this.saveMeta();
    return {
      ok: true,
      plugin_id: pluginId,
      removed: plugin.name
    };
  }

  async loadPluginFromFile(filePath, writeMeta = true) {
    const code = await fsp.readFile(filePath, "utf8");
    const mounted = this.mountPlugin(code, { originalPath: filePath });
    mounted.path = filePath;
    this.plugins.set(mounted.id, mounted);

    if (writeMeta) {
      this.pluginMeta[mounted.id] = {
        id: mounted.id,
        name: mounted.name,
        path: filePath,
        srcUrl: mounted.instance.srcUrl || "",
        installedAt: Date.now()
      };
      await this.saveMeta();
    }

    return mounted;
  }

  mountPlugin(code, options = {}) {
    const module = { exports: {} };
    const pluginNameRef = { value: "" };

    const env = {
      getUserVariables: () => {
        const name = pluginNameRef.value;
        if (!name) {
          return {};
        }
        return this.pluginMeta[`vars:${name}`] || {};
      },
      os: "windows",
      appVersion: "0.1.0",
      lang: "zh-CN"
    };

    const sandbox = {
      module,
      exports: module.exports,
      require: (packageName) => this.requirePackage(packageName),
      __musicfree_require: (packageName) => this.requirePackage(packageName),
      console,
      env,
      URL,
      process: {
        platform: process.platform,
        version: process.version,
        env: {}
      },
      setTimeout,
      clearTimeout,
      Buffer
    };

    const wrappedCode = `'use strict';\n${code}\n`;
    const script = new vm.Script(wrappedCode, {
      filename: options.originalPath || "plugin.js"
    });
    const context = vm.createContext(sandbox);
    script.runInContext(context, { timeout: 5000 });

    const instance = module.exports && module.exports.default
      ? module.exports.default
      : module.exports;

    if (!instance || typeof instance !== "object") {
      throw new Error("Plugin did not export an object.");
    }
    if (!instance.platform || typeof instance.platform !== "string") {
      throw new Error("Plugin missing platform.");
    }

    pluginNameRef.value = instance.platform;

    const id = sha256(code);
    return {
      id,
      name: instance.platform,
      path: options.originalPath || "",
      code,
      instance
    };
  }

  requirePackage(packageName) {
    if (!Object.prototype.hasOwnProperty.call(SUPPORTED_PACKAGES, packageName)) {
      throw new Error(`Unsupported package: ${packageName}`);
    }
    return SUPPORTED_PACKAGES[packageName];
  }

  getPlugin(pluginId) {
    if (!pluginId) {
      return null;
    }

    if (this.plugins.has(pluginId)) {
      return this.plugins.get(pluginId);
    }

    for (const plugin of this.plugins.values()) {
      if (plugin.name === pluginId) {
        return plugin;
      }
    }

    return null;
  }

  getPluginVariables(pluginId) {
    const plugin = this.requirePlugin(pluginId);
    return this.pluginMeta[`vars:${plugin.name}`] || {};
  }

  async setPluginVariables(pluginId, values) {
    const plugin = this.requirePlugin(pluginId);
    this.pluginMeta[`vars:${plugin.name}`] = values && typeof values === "object" ? values : {};
    await this.saveMeta();
    return this.getPluginVariables(pluginId);
  }

  async search(pluginId, query, page = 1, type = "music") {
    const plugin = this.requirePlugin(pluginId);
    if (typeof plugin.instance.search !== "function") {
      return { isEnd: true, data: [] };
    }

    const result = await plugin.instance.search(query, page, type);
    const data = Array.isArray(result?.data) ? result.data : [];
    data.forEach((item) => normalizeMediaItem(item, plugin.name));
    return {
      isEnd: result?.isEnd !== false,
      data
    };
  }

  async getMediaSource(pluginId, musicItem, quality = "standard") {
    const plugin = this.requirePlugin(pluginId || musicItem?.platform);
    if (typeof plugin.instance.getMediaSource !== "function") {
      return {
        url: musicItem?.qualities?.[quality]?.url || musicItem?.url || "",
        headers: {}
      };
    }

    const result = await plugin.instance.getMediaSource(musicItem, quality);
    return result || {};
  }

  async getLyric(pluginId, musicItem) {
    const plugin = this.requirePlugin(pluginId || musicItem?.platform);
    if (typeof plugin.instance.getLyric !== "function") {
      return {};
    }

    return (await plugin.instance.getLyric(musicItem)) || {};
  }

  async getTopLists(pluginId) {
    const plugin = this.requirePlugin(pluginId);
    if (typeof plugin.instance.getTopLists !== "function") {
      return [];
    }

    return (await plugin.instance.getTopLists()) || [];
  }

  async saveMeta() {
    await fsp.writeFile(META_FILE, JSON.stringify(this.pluginMeta, null, 2), "utf8");
  }

  serializePlugin(plugin) {
    return {
      id: plugin.id,
      name: plugin.name,
      version: plugin.instance.version || "",
      path: plugin.path,
      srcUrl: plugin.instance.srcUrl || "",
      supportedSearchType: plugin.instance.supportedSearchType || []
    };
  }

  requirePlugin(pluginId) {
    const plugin = this.getPlugin(pluginId);
    if (!plugin) {
      const error = new Error(`Plugin not found: ${pluginId}`);
      error.statusCode = 404;
      throw error;
    }
    return plugin;
  }
}

function normalizeMediaItem(item, platform) {
  if (!item || typeof item !== "object") {
    return;
  }
  if (!item.platform) {
    item.platform = platform;
  }
  if (item.id === undefined || item.id === null) {
    item.id = `${platform}:${item.title || "unknown"}`;
  }
}

function sha256(input) {
  return crypto.createHash("sha256").update(input).digest("hex");
}

async function ensureDir(targetPath) {
  await fsp.mkdir(targetPath, { recursive: true });
}

async function readJsonFile(filePath, fallback) {
  try {
    const raw = await fsp.readFile(filePath, "utf8");
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
}

function sendJson(res, statusCode, body) {
  const payload = JSON.stringify(body);
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(payload)
  });
  res.end(payload);
}

function collectJsonBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      if (chunks.length === 0) {
        resolve({});
        return;
      }

      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
      } catch (error) {
        reject(new Error("Invalid JSON body."));
      }
    });
    req.on("error", reject);
  });
}

async function main() {
  const host = new PluginHost();
  await host.setup();

  const server = http.createServer(async (req, res) => {
    try {
      if (!req.url) {
        sendJson(res, 404, { ok: false, error: "Not found" });
        return;
      }

      const url = new URL(req.url, `http://${HOST}:${PORT}`);

      if (req.method === "GET" && url.pathname === "/health") {
        sendJson(res, 200, {
          ok: true,
          host: "music-plugin-host",
          version: "0.1.0",
          plugins: host.listPlugins().length
        });
        return;
      }

      if (req.method === "GET" && url.pathname === "/plugins") {
        sendJson(res, 200, {
          ok: true,
          plugins: host.listPlugins()
        });
        return;
      }

      if (req.method === "GET" && url.pathname === "/plugin_vars") {
        const pluginId = String(url.searchParams.get("plugin_id") || "");
        const values = host.getPluginVariables(pluginId);
        sendJson(res, 200, {
          ok: true,
          plugin_id: pluginId,
          values
        });
        return;
      }

      if (req.method === "POST" && url.pathname === "/install") {
        const body = await collectJsonBody(req);
        if (body.url) {
          const result = await host.installFromUrl(String(body.url));
          sendJson(res, 200, result);
          return;
        }
        if (body.path) {
          const result = await host.installFromPath(String(body.path));
          sendJson(res, 200, result);
          return;
        }
        sendJson(res, 400, { ok: false, error: "Missing url or path." });
        return;
      }

      if (req.method === "POST" && url.pathname === "/uninstall") {
        const body = await collectJsonBody(req);
        const result = await host.uninstall(String(body.plugin_id || ""));
        sendJson(res, 200, result);
        return;
      }

      if (req.method === "POST" && url.pathname === "/plugin_vars") {
        const body = await collectJsonBody(req);
        const values = await host.setPluginVariables(
          String(body.plugin_id || ""),
          body.values || {}
        );
        sendJson(res, 200, {
          ok: true,
          plugin_id: String(body.plugin_id || ""),
          values
        });
        return;
      }

      if (req.method === "POST" && url.pathname === "/search") {
        const body = await collectJsonBody(req);
        const result = await host.search(
          String(body.plugin_id || ""),
          String(body.query || ""),
          Number(body.page || 1),
          String(body.type || "music")
        );
        sendJson(res, 200, result);
        return;
      }

      if (req.method === "POST" && url.pathname === "/source") {
        const body = await collectJsonBody(req);
        const result = await host.getMediaSource(
          String(body.plugin_id || body.music_item?.platform || ""),
          body.music_item || {},
          String(body.quality || "standard")
        );
        sendJson(res, 200, result);
        return;
      }

      if (req.method === "POST" && url.pathname === "/lyric") {
        const body = await collectJsonBody(req);
        const result = await host.getLyric(
          String(body.plugin_id || body.music_item?.platform || ""),
          body.music_item || {}
        );
        sendJson(res, 200, result);
        return;
      }

      if (req.method === "POST" && url.pathname === "/toplists") {
        const body = await collectJsonBody(req);
        const result = await host.getTopLists(String(body.plugin_id || ""));
        sendJson(res, 200, result);
        return;
      }

      sendJson(res, 404, { ok: false, error: "Not found" });
    } catch (error) {
      const statusCode = Number(error?.statusCode || 500);
      sendJson(res, statusCode, {
        ok: false,
        error: error?.message || "Unknown error"
      });
    }
  });

  server.listen(PORT, HOST, () => {
    console.log(`[plugin-host] listening on http://${HOST}:${PORT}`);
  });
}

main().catch((error) => {
  console.error("[plugin-host] fatal:", error);
  process.exitCode = 1;
});
