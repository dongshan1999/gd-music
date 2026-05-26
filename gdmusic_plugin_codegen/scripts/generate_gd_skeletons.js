const fs = require("fs/promises");
const path = require("path");

const PROJECT_ROOT = path.resolve(__dirname, "..");
const DEFAULT_SOURCE_ROOT = path.resolve(PROJECT_ROOT, "source_plugins");
const DEFAULT_OUTPUT_ROOT = path.resolve(PROJECT_ROOT, ".generated");
const DEFAULT_HANDWRITTEN_PLUGIN_ROOT = DEFAULT_OUTPUT_ROOT;

function parseCliArgs(argv) {
  const options = {
    sourceRoot: DEFAULT_SOURCE_ROOT,
    outputRoot: DEFAULT_OUTPUT_ROOT,
    pluginNames: [],
  };

  const positional = [];
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg.startsWith("--plugins=")) {
      options.pluginNames = arg
        .slice("--plugins=".length)
        .split(",")
        .map((item) => item.trim().toLowerCase())
        .filter(Boolean);
      continue;
    }
    if (arg === "--plugins") {
      const value = argv[index + 1] ?? "";
      options.pluginNames = value
        .split(",")
        .map((item) => item.trim().toLowerCase())
        .filter(Boolean);
      index += 1;
      continue;
    }
    positional.push(arg);
  }

  if (positional[0]) {
    options.sourceRoot = path.resolve(positional[0]);
  }
  if (positional[1]) {
    options.outputRoot = path.resolve(positional[1]);
  }

  return options;
}

const METHOD_SPECS = [
  {
    tsName: "search",
    gdName: "search",
    args: "query: String, page: int, media_type: String",
    returnType: "Dictionary",
    returnStub: 'return {"isEnd": true, "data": []}',
  },
  {
    tsName: "getMediaSource",
    gdName: "get_media_source",
    args: "music_item: Dictionary, quality: String",
    returnType: "Dictionary",
    returnStub: "return {}",
  },
  {
    tsName: "getMusicInfo",
    gdName: "get_music_info",
    args: "media_base: Dictionary",
    returnType: "Dictionary",
    returnStub: "return {}",
  },
  {
    tsName: "getLyric",
    gdName: "get_lyric",
    args: "music_item: Dictionary",
    returnType: "Dictionary",
    returnStub: "return {}",
  },
  {
    tsName: "getAlbumInfo",
    gdName: "get_album_info",
    args: "album_item: Dictionary, page: int",
    returnType: "Dictionary",
    returnStub: "return {}",
  },
  {
    tsName: "getArtistWorks",
    gdName: "get_artist_works",
    args: "artist_item: Dictionary, page: int, media_type: String",
    returnType: "Dictionary",
    returnStub: 'return {"isEnd": true, "data": []}',
  },
  {
    tsName: "importMusicSheet",
    gdName: "import_music_sheet",
    args: "url_like: String",
    returnType: "Array",
    returnStub: "return []",
  },
  {
    tsName: "importMusicItem",
    gdName: "import_music_item",
    args: "url_like: String",
    returnType: "Dictionary",
    returnStub: "return {}",
  },
  {
    tsName: "getTopLists",
    gdName: "get_toplists",
    args: "",
    returnType: "Array",
    returnStub: "return []",
  },
  {
    tsName: "getTopListDetail",
    gdName: "get_toplist_detail",
    args: "toplist_item: Dictionary",
    returnType: "Dictionary",
    returnStub: "return {}",
  },
];

const DEPENDENCY_RULES = [
  { name: "axios", patterns: [/from\s+["']axios["']/, /require\(["']axios["']\)/, /\baxios\b/] },
  { name: "cheerio", patterns: [/from\s+["']cheerio["']/, /require\(["']cheerio["']\)/, /\bcheerio\b/] },
  { name: "crypto-js", patterns: [/from\s+["']crypto-js["']/, /require\(["']crypto-js["']\)/, /\bCryptoJs\b/] },
  { name: "big-integer", patterns: [/from\s+["']big-integer["']/, /require\(["']big-integer["']\)/, /\bbigInt\b/] },
  { name: "dayjs", patterns: [/from\s+["']dayjs["']/, /require\(["']dayjs["']\)/, /\bdayjs\b/] },
  { name: "form-data", patterns: [/from\s+["']form-data["']/, /require\(["']form-data["']\)/, /\bFormData\b/] },
  { name: "he", patterns: [/from\s+["']he["']/, /require\(["']he["']\)/, /\bhe\b/] },
  { name: "qs", patterns: [/from\s+["']qs["']/, /require\(["']qs["']\)/, /\bqs\b/] },
  { name: "webdav", patterns: [/from\s+["']webdav["']/, /require\(["']webdav["']\)/, /\bcreateClient\b/, /\bAuthType\b/] },
];

const CAPABILITY_RULES = [
  { name: "http", patterns: [/\baxios\b/, /\bfetch\b/, /\bhttpGet\b/] },
  { name: "html_parse", patterns: [/\bcheerio\b/, /\.load\(/] },
  { name: "crypto", patterns: [/\bCryptoJs\b/, /\bcrypto-js\b/, /\bMD5\b/, /\bSHA/ ] },
  { name: "webdav_protocol", patterns: [/\bwebdav\b/, /\bcreateClient\b/, /\bgetDirectoryContents\b/, /\bgetFileDownloadLink\b/] },
  { name: "user_variables", patterns: [/env\?\.(getUserVariables|getUserVariables\?\.)/, /env\.getUserVariables/, /\buserVariables\b/] },
  { name: "state_cache", patterns: [/\bcached[A-Z]/, /\bcache[A-Z]/, /\blet\s+cached/, /\bMap\(/] },
  { name: "pagination", patterns: [/\bpage\b/, /\bpageSize\b/, /\bOffset\b/] },
];

function skipWhitespace(source, index) {
  while (index < source.length && /\s/.test(source[index])) {
    index += 1;
  }
  return index;
}

function readQuotedString(source, startIndex) {
  const quote = source[startIndex];
  if (!["'", '"', "`"].includes(quote)) {
    return null;
  }

  let value = "";
  let index = startIndex + 1;
  while (index < source.length) {
    const char = source[index];
    if (char === "\\") {
      value += char;
      index += 1;
      if (index < source.length) {
        value += source[index];
      }
      index += 1;
      continue;
    }
    if (char === quote) {
      return { value, endIndex: index + 1 };
    }
    value += char;
    index += 1;
  }

  return null;
}

function findMatchingBracket(source, startIndex, openChar, closeChar) {
  let depth = 0;
  let inLineComment = false;
  let inBlockComment = false;
  let activeQuote = "";

  for (let index = startIndex; index < source.length; index += 1) {
    const char = source[index];
    const next = source[index + 1];

    if (inLineComment) {
      if (char === "\n") {
        inLineComment = false;
      }
      continue;
    }

    if (inBlockComment) {
      if (char === "*" && next === "/") {
        inBlockComment = false;
        index += 1;
      }
      continue;
    }

    if (activeQuote) {
      if (char === "\\") {
        index += 1;
        continue;
      }
      if (char === activeQuote) {
        activeQuote = "";
      }
      continue;
    }

    if (char === "/" && next === "/") {
      inLineComment = true;
      index += 1;
      continue;
    }

    if (char === "/" && next === "*") {
      inBlockComment = true;
      index += 1;
      continue;
    }

    if (char === "'" || char === '"' || char === "`") {
      activeQuote = char;
      continue;
    }

    if (char === openChar) {
      depth += 1;
      continue;
    }

    if (char === closeChar) {
      depth -= 1;
      if (depth === 0) {
        return index;
      }
    }
  }

  return -1;
}

function extractAssignedObjectBody(source, assignmentKey) {
  const assignmentIndex = source.lastIndexOf(`${assignmentKey} =`);
  if (assignmentIndex === -1) {
    return "";
  }

  const braceIndex = source.indexOf("{", assignmentIndex);
  if (braceIndex === -1) {
    return "";
  }

  const endIndex = findMatchingBracket(source, braceIndex, "{", "}");
  if (endIndex === -1) {
    return "";
  }

  return source.slice(braceIndex + 1, endIndex);
}

function splitTopLevelProperties(objectBody) {
  const properties = [];
  let segmentStart = 0;
  let parenDepth = 0;
  let braceDepth = 0;
  let bracketDepth = 0;
  let inLineComment = false;
  let inBlockComment = false;
  let activeQuote = "";

  for (let index = 0; index < objectBody.length; index += 1) {
    const char = objectBody[index];
    const next = objectBody[index + 1];

    if (inLineComment) {
      if (char === "\n") {
        inLineComment = false;
      }
      continue;
    }

    if (inBlockComment) {
      if (char === "*" && next === "/") {
        inBlockComment = false;
        index += 1;
      }
      continue;
    }

    if (activeQuote) {
      if (char === "\\") {
        index += 1;
        continue;
      }
      if (char === activeQuote) {
        activeQuote = "";
      }
      continue;
    }

    if (char === "/" && next === "/") {
      inLineComment = true;
      index += 1;
      continue;
    }

    if (char === "/" && next === "*") {
      inBlockComment = true;
      index += 1;
      continue;
    }

    if (char === "'" || char === '"' || char === "`") {
      activeQuote = char;
      continue;
    }

    if (char === "(") {
      parenDepth += 1;
      continue;
    }
    if (char === ")") {
      parenDepth -= 1;
      continue;
    }
    if (char === "{") {
      braceDepth += 1;
      continue;
    }
    if (char === "}") {
      braceDepth -= 1;
      continue;
    }
    if (char === "[") {
      bracketDepth += 1;
      continue;
    }
    if (char === "]") {
      bracketDepth -= 1;
      continue;
    }

    if (
      char === "," &&
      parenDepth === 0 &&
      braceDepth === 0 &&
      bracketDepth === 0
    ) {
      const segment = objectBody.slice(segmentStart, index).trim();
      if (segment) {
        properties.push(segment);
      }
      segmentStart = index + 1;
    }
  }

  const tail = objectBody.slice(segmentStart).trim();
  if (tail) {
    properties.push(tail);
  }

  return properties;
}

function parseTopLevelPropertyMap(objectBody) {
  const map = new Map();
  const properties = splitTopLevelProperties(objectBody);

  for (const propertyText of properties) {
    const colonIndex = propertyText.indexOf(":");
    if (colonIndex === -1) {
      continue;
    }

    const rawKey = propertyText.slice(0, colonIndex).trim();
    const rawValue = propertyText.slice(colonIndex + 1).trim();
    const keyMatch = rawKey.match(/^["'`]?([a-zA-Z0-9_$]+)["'`]?$/);
    if (!keyMatch) {
      continue;
    }
    map.set(keyMatch[1], rawValue);
  }

  return map;
}

function parseTopLevelPropertyKeys(objectBody) {
  const keys = [];
  const properties = splitTopLevelProperties(objectBody);

  for (const propertyText of properties) {
    const methodMatch = propertyText.match(
      /^(?:async\s+)?["'`]?([a-zA-Z0-9_$]+)["'`]?\s*\(/
    );
    if (methodMatch) {
      keys.push(methodMatch[1]);
      continue;
    }

    const colonMatch = propertyText.match(
      /^["'`]?([a-zA-Z0-9_$]+)["'`]?\s*:/
    );
    if (colonMatch) {
      keys.push(colonMatch[1]);
      continue;
    }

    const shorthandMatch = propertyText.match(/^([a-zA-Z0-9_$]+)$/);
    if (shorthandMatch) {
      keys.push(shorthandMatch[1]);
    }
  }

  return keys;
}

function parseStringProperty(properties, key) {
  const rawValue = properties.get(key);
  if (!rawValue) {
    return "";
  }
  const parsed = readQuotedString(rawValue, skipWhitespace(rawValue, 0));
  return parsed?.value ?? "";
}

function parseStringArrayProperty(properties, key) {
  const rawValue = properties.get(key);
  if (!rawValue) {
    return [];
  }
  const startIndex = rawValue.indexOf("[");
  if (startIndex === -1) {
    return [];
  }
  const endIndex = findMatchingBracket(rawValue, startIndex, "[", "]");
  if (endIndex === -1) {
    return [];
  }
  const arrayBody = rawValue.slice(startIndex + 1, endIndex);
  const values = [];
  let index = 0;
  while (index < arrayBody.length) {
    index = skipWhitespace(arrayBody, index);
    if (index >= arrayBody.length) {
      break;
    }
    const parsed = readQuotedString(arrayBody, index);
    if (!parsed) {
      index += 1;
      continue;
    }
    values.push(parsed.value);
    index = parsed.endIndex;
  }
  return values;
}

function parseUserVariables(properties) {
  const rawValue = properties.get("userVariables");
  if (!rawValue) {
    return [];
  }

  const startIndex = rawValue.indexOf("[");
  if (startIndex === -1) {
    return [];
  }
  const endIndex = findMatchingBracket(rawValue, startIndex, "[", "]");
  if (endIndex === -1) {
    return [];
  }

  const arrayBody = rawValue.slice(startIndex + 1, endIndex);
  const results = [];
  let index = 0;
  while (index < arrayBody.length) {
    const braceIndex = arrayBody.indexOf("{", index);
    if (braceIndex === -1) {
      break;
    }
    const braceEndIndex = findMatchingBracket(arrayBody, braceIndex, "{", "}");
    if (braceEndIndex === -1) {
      break;
    }

    const objectBody = arrayBody.slice(braceIndex + 1, braceEndIndex);
    const objectProperties = parseTopLevelPropertyMap(objectBody);
    const key = parseStringProperty(objectProperties, "key");
    if (key) {
      results.push({
        key,
        name: parseStringProperty(objectProperties, "name"),
        type: parseStringProperty(objectProperties, "type"),
      });
    }

    index = braceEndIndex + 1;
  }

  return results;
}

function escapeGDScriptString(text) {
  return String(text ?? "").replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

function detectByRules(source, rules) {
  const hits = [];
  for (const rule of rules) {
    if (rule.patterns.some((pattern) => pattern.test(source))) {
      hits.push(rule.name);
    }
  }
  return hits;
}

function estimateMigrationDifficulty(meta) {
  let score = 0;

  score += meta.supportedMethods.length;

  if (meta.dependencies.includes("axios")) {
    score += 1;
  }
  if (meta.dependencies.includes("cheerio")) {
    score += 3;
  }
  if (meta.dependencies.includes("crypto-js")) {
    score += 2;
  }
  if (meta.dependencies.includes("webdav")) {
    score += 4;
  }
  if (meta.dependencies.includes("qs") || meta.dependencies.includes("he") || meta.dependencies.includes("dayjs")) {
    score += 1;
  }

  if (meta.capabilities.includes("state_cache")) {
    score += 1;
  }
  if (meta.capabilities.includes("user_variables")) {
    score += 1;
  }
  if (meta.capabilities.includes("html_parse")) {
    score += 2;
  }

  if (score >= 12) {
    return "high";
  }
  if (score >= 6) {
    return "medium";
  }
  return "low";
}

function buildMigrationNotes(meta) {
  const notes = [];

  if (meta.dependencies.includes("axios")) {
    notes.push("replace axios calls with Godot HTTPRequest or HTTPClient helper");
  }
  if (meta.dependencies.includes("cheerio")) {
    notes.push("replace cheerio HTML parsing with XMLParser, RegEx, or a custom HTML adapter");
  }
  if (meta.dependencies.includes("crypto-js")) {
    notes.push("replace crypto-js hashing/signature logic with Godot HashingContext or native bridge");
  }
  if (meta.dependencies.includes("webdav")) {
    notes.push("replace webdav client calls with direct WebDAV HTTP methods or a Godot-side adapter");
  }
  if (meta.capabilities.includes("user_variables")) {
    notes.push("map env.getUserVariables() to a Godot-side plugin config storage");
  }
  if (meta.capabilities.includes("state_cache")) {
    notes.push("convert JS module-level cache into plugin instance state");
  }

  return notes;
}

function toPascalCase(value) {
  return String(value)
    .replace(/[^a-zA-Z0-9]+/g, " ")
    .split(" ")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join("");
}

function toSnakeCase(value) {
  return String(value)
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/[^a-zA-Z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .toLowerCase();
}

function toHandwrittenPluginFilename(folderName) {
  return `gdmusic_${toSnakeCase(folderName)}_plugin.gd`;
}

function getDifficultyRank(difficulty) {
  if (difficulty === "low") {
    return 1;
  }
  if (difficulty === "medium") {
    return 2;
  }
  return 3;
}

function computeRecommendedPriority(meta) {
  let score = getDifficultyRank(meta.migrationDifficulty);
  if (meta.dependencies.includes("axios")) {
    score -= 0.25;
  }
  if (meta.dependencies.includes("cheerio")) {
    score += 0.75;
  }
  if (meta.dependencies.includes("crypto-js")) {
    score += 0.75;
  }
  if (meta.dependencies.includes("webdav")) {
    score += 1.0;
  }
  if (meta.supportedMethods.includes("importMusicSheet")) {
    score += 0.5;
  }
  if (meta.supportedMethods.length <= 2) {
    score -= 0.25;
  }

  if (score <= 1.5) {
    return 1;
  }
  if (score <= 2.5) {
    return 2;
  }
  return 3;
}

async function detectHandwrittenPluginInfo(folderName) {
  const filename = toHandwrittenPluginFilename(folderName);
  const absolutePath = path.join(DEFAULT_HANDWRITTEN_PLUGIN_ROOT, filename);

  try {
    await fs.stat(absolutePath);
    return {
      status: "handwritten",
      handwrittenPluginAbsolutePath: absolutePath,
      handwrittenPluginRelativePath: path.relative(PROJECT_ROOT, absolutePath).replace(/\\/g, "/"),
    };
  } catch {
    return {
      status: "skeleton",
      handwrittenPluginAbsolutePath: "",
      handwrittenPluginRelativePath: "",
    };
  }
}

function collectMethodNames(propertyKeys) {
  const propertyKeySet = new Set(propertyKeys);
  return METHOD_SPECS.filter((spec) => propertyKeySet.has(spec.tsName)).map((spec) => spec.tsName);
}

function buildMethodBlock(spec, pluginName, originalSourcePath) {
  const args = spec.args ? `(${spec.args})` : "()";
  return [
    `func ${spec.gdName}${args} -> ${spec.returnType}:`,
    `\t## TODO: migrate ${pluginName}.${spec.tsName} from MusicFree TypeScript plugin.`,
    `\t## Source: ${escapeGDScriptString(originalSourcePath)}`,
    `\tpush_warning("${escapeGDScriptString(pluginName)}.${spec.gdName}() is not implemented.")`,
    `\t${spec.returnStub}`,
    "",
  ].join("\n");
}

function buildPluginScript(meta) {
  const supportedTypes = meta.supportedSearchTypes
    .map((item) => `"${escapeGDScriptString(item)}"`)
    .join(", ");
  const supportedMethods = meta.supportedMethods
    .map((item) => `"${escapeGDScriptString(item)}"`)
    .join(", ");
  const dependencies = meta.dependencies
    .map((item) => `"${escapeGDScriptString(item)}"`)
    .join(", ");
  const capabilities = meta.capabilities
    .map((item) => `"${escapeGDScriptString(item)}"`)
    .join(", ");
  const userVariables = meta.userVariables
    .map(
      (item) =>
        `{"key": "${escapeGDScriptString(item.key)}", "name": "${escapeGDScriptString(
          item.name
        )}", "type": "${escapeGDScriptString(item.type)}"}`
    )
    .join(", ");

  const lines = [
    "## Auto-generated by gdmusic_plugin_codegen/scripts/generate_gd_skeletons.js",
    `## Source plugin entry: ${escapeGDScriptString(meta.sourcePath)}`,
    `## Migration difficulty: ${escapeGDScriptString(meta.migrationDifficulty)}`,
    "## class_name intentionally omitted to avoid global script class conflicts in Godot.",
    'extends "res://gdmusic_plugin_codegen/godot/base/gdmusic_plugin_methods.gd"',
    "",
    `const PLATFORM := "${escapeGDScriptString(meta.platform)}"`,
    `const AUTHOR := "${escapeGDScriptString(meta.author)}"`,
    `const DESCRIPTION := "${escapeGDScriptString(meta.description)}"`,
    `const VERSION := "${escapeGDScriptString(meta.version)}"`,
    `const SRC_URL := "${escapeGDScriptString(meta.srcUrl)}"`,
    `const DEFAULT_SEARCH_TYPE := "${escapeGDScriptString(meta.defaultSearchType || "music")}"`,
    `const SUPPORTED_SEARCH_TYPES := [${supportedTypes}]`,
    `const SUPPORTED_METHODS := [${supportedMethods}]`,
    `const JS_DEPENDENCIES := [${dependencies}]`,
    `const MIGRATION_CAPABILITIES := [${capabilities}]`,
    `const MIGRATION_DIFFICULTY := "${escapeGDScriptString(meta.migrationDifficulty)}"`,
    `const USER_VARIABLES := [${userVariables}]`,
    "",
    "func get_platform() -> String:",
    "\treturn PLATFORM",
    "",
    "func get_author() -> String:",
    "\treturn AUTHOR",
    "",
    "func get_description() -> String:",
    "\treturn DESCRIPTION",
    "",
    "func get_version() -> String:",
    "\treturn VERSION",
    "",
    "func get_src_url() -> String:",
    "\treturn SRC_URL",
    "",
    "func get_default_search_type() -> String:",
    "\treturn DEFAULT_SEARCH_TYPE",
    "",
    "func get_supported_search_types() -> PackedStringArray:",
    "\treturn PackedStringArray(SUPPORTED_SEARCH_TYPES)",
    "",
    "func get_supported_methods() -> PackedStringArray:",
    "\treturn PackedStringArray(SUPPORTED_METHODS)",
    "",
    "func get_js_dependencies() -> PackedStringArray:",
    "\treturn PackedStringArray(JS_DEPENDENCIES)",
    "",
    "func get_migration_capabilities() -> PackedStringArray:",
    "\treturn PackedStringArray(MIGRATION_CAPABILITIES)",
    "",
    "func get_migration_difficulty() -> String:",
    "\treturn MIGRATION_DIFFICULTY",
    "",
    "func get_user_variables() -> Array[Dictionary]:",
    "\treturn USER_VARIABLES",
    "",
  ];

  if (meta.migrationNotes.length > 0) {
    lines.push("func get_migration_notes() -> PackedStringArray:");
    lines.push(
      `\treturn PackedStringArray([${meta.migrationNotes
        .map((item) => `"${escapeGDScriptString(item)}"`)
        .join(", ")}])`
    );
    lines.push("");
  }

  for (const spec of METHOD_SPECS) {
    if (!meta.supportedMethods.includes(spec.tsName)) {
      continue;
    }
    lines.push(buildMethodBlock(spec, meta.platform, meta.sourcePath));
  }

  return lines.join("\n").trim() + "\n";
}

async function parsePlugin(pluginDirPath) {
  const sourcePath = path.join(pluginDirPath, "index.ts");
  const source = await fs.readFile(sourcePath, "utf8");
  const folderName = path.basename(pluginDirPath);
  const exportsBody = extractAssignedObjectBody(source, "module.exports");
  const properties = parseTopLevelPropertyMap(exportsBody);
  const propertyKeys = parseTopLevelPropertyKeys(exportsBody);
  const dependencies = detectByRules(source, DEPENDENCY_RULES);
  const capabilities = detectByRules(source, CAPABILITY_RULES);

  const meta = {
    folderName,
    sourcePath,
    platform: parseStringProperty(properties, "platform") || folderName,
    author: parseStringProperty(properties, "author"),
    description: parseStringProperty(properties, "description"),
    version: parseStringProperty(properties, "version"),
    srcUrl: parseStringProperty(properties, "srcUrl"),
    defaultSearchType: parseStringProperty(properties, "defaultSearchType"),
    supportedSearchTypes: parseStringArrayProperty(properties, "supportedSearchType"),
    userVariables: parseUserVariables(properties),
    supportedMethods: collectMethodNames(propertyKeys),
    dependencies,
    capabilities,
  };

  meta.migrationDifficulty = estimateMigrationDifficulty(meta);
  meta.migrationNotes = buildMigrationNotes(meta);
  return meta;
}

function buildMigrationReport(manifest) {
  const sorted = [...manifest].sort((left, right) => {
    const difficultyRank = { low: 0, medium: 1, high: 2 };
    const rankDiff =
      (difficultyRank[left.migrationDifficulty] ?? 99) - (difficultyRank[right.migrationDifficulty] ?? 99);
    if (rankDiff !== 0) {
      return rankDiff;
    }
    return left.folderName.localeCompare(right.folderName, "en");
  });

  const handwrittenPlugins = sorted.filter((item) => item.status === "handwritten");
  const skeletonPlugins = sorted.filter((item) => item.status === "skeleton");
  const recommendedCandidates = skeletonPlugins
    .filter((item) => item.recommendedPriority <= 2)
    .slice(0, 6);

  const difficultyCounts = {
    low: sorted.filter((item) => item.migrationDifficulty === "low").length,
    medium: sorted.filter((item) => item.migrationDifficulty === "medium").length,
    high: sorted.filter((item) => item.migrationDifficulty === "high").length,
  };

  const lines = [
    "# MusicFree Plugin Migration Report",
    "",
    `Generated plugins: ${sorted.length}`,
    `Handwritten runnable plugins: ${handwrittenPlugins.length}`,
    `Skeleton-only plugins: ${skeletonPlugins.length}`,
    "",
    `Difficulty summary: low=${difficultyCounts.low}, medium=${difficultyCounts.medium}, high=${difficultyCounts.high}`,
    "",
    "## Current status",
    "",
  ];

  if (handwrittenPlugins.length > 0) {
    for (const item of handwrittenPlugins) {
      lines.push(`- [done] ${item.folderName} -> ${item.handwrittenPluginRelativePath}`);
    }
  } else {
    lines.push("- No handwritten runnable plugins detected.");
  }

  lines.push("");
  lines.push("## Recommended next candidates");
  lines.push("");

  if (recommendedCandidates.length > 0) {
    for (const item of recommendedCandidates) {
      const note = item.migrationNotes[0] || "inspect source manually";
      lines.push(
        `- [p${item.recommendedPriority}] ${item.folderName} (${item.migrationDifficulty}) - methods: ${item.supportedMethods.join(", ") || "-"} - ${note}`
      );
    }
  } else {
    lines.push("- No recommended candidates available.");
  }

  lines.push("");
  lines.push("## Full table");
  lines.push("");
  lines.push("| Plugin | Status | Priority | Platform | Difficulty | Methods | Dependencies |");
  lines.push("| --- | --- | --- | --- | --- | --- | --- |");

  for (const item of sorted) {
    lines.push(
      `| ${item.folderName} | ${item.status} | p${item.recommendedPriority} | ${item.platform || ""} | ${item.migrationDifficulty} | ${item.supportedMethods.join(", ") || "-"} | ${item.dependencies.join(", ") || "-"} |`
    );
  }

  lines.push("");
  lines.push("## Suggested order");
  lines.push("");

  for (const item of sorted) {
    const note = item.migrationNotes[0] || "skeleton-only plugin, inspect source manually";
    lines.push(`- ${item.folderName}: ${item.migrationDifficulty} - ${note}`);
  }

  lines.push("");
  return lines.join("\n");
}

async function generate(sourceRoot, outputRoot, options = {}) {
  const entries = await fs.readdir(sourceRoot, { withFileTypes: true });
  await fs.mkdir(outputRoot, { recursive: true });
  const selectedPluginNames = new Set(
    (options.pluginNames ?? []).map((item) => String(item).trim().toLowerCase()).filter(Boolean)
  );

  const manifest = [];

  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }
    if (selectedPluginNames.size > 0 && !selectedPluginNames.has(entry.name.toLowerCase())) {
      continue;
    }

    const pluginDirPath = path.join(sourceRoot, entry.name);
    const sourcePath = path.join(pluginDirPath, "index.ts");

    try {
      await fs.stat(sourcePath);
    } catch {
      continue;
    }

    const meta = await parsePlugin(pluginDirPath);
    const gdSource = buildPluginScript(meta);
    const outputPath = path.join(outputRoot, `${toSnakeCase(entry.name)}_plugin.gd`);
    await fs.writeFile(outputPath, gdSource, "utf8");
    const handwrittenPluginInfo = await detectHandwrittenPluginInfo(meta.folderName);

    manifest.push({
      folderName: meta.folderName,
      platform: meta.platform,
      outputPath,
      outputPathRelative: path.relative(PROJECT_ROOT, outputPath).replace(/\\/g, "/"),
      author: meta.author,
      description: meta.description,
      userVariables: meta.userVariables,
      supportedMethods: meta.supportedMethods,
      supportedSearchTypes: meta.supportedSearchTypes,
      dependencies: meta.dependencies,
      capabilities: meta.capabilities,
      migrationDifficulty: meta.migrationDifficulty,
      migrationNotes: meta.migrationNotes,
      recommendedPriority: computeRecommendedPriority(meta),
      status: handwrittenPluginInfo.status,
      handwrittenPluginAbsolutePath: handwrittenPluginInfo.handwrittenPluginAbsolutePath,
      handwrittenPluginRelativePath: handwrittenPluginInfo.handwrittenPluginRelativePath,
    });
  }

  const summary = {
    totalPlugins: manifest.length,
    handwrittenPlugins: manifest.filter((item) => item.status === "handwritten").length,
    skeletonPlugins: manifest.filter((item) => item.status === "skeleton").length,
    byDifficulty: {
      low: manifest.filter((item) => item.migrationDifficulty === "low").length,
      medium: manifest.filter((item) => item.migrationDifficulty === "medium").length,
      high: manifest.filter((item) => item.migrationDifficulty === "high").length,
    },
  };

  const manifestPath = path.join(outputRoot, "manifest.json");
  await fs.writeFile(
    manifestPath,
    JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        sourceRoot,
        outputRoot,
        summary,
        plugins: manifest,
      },
      null,
      2
    ),
    "utf8"
  );
  const reportPath = path.join(outputRoot, "migration_report.md");
  await fs.writeFile(reportPath, buildMigrationReport(manifest), "utf8");

  console.log(`Generated ${manifest.length} plugin skeletons into ${outputRoot}`);
  console.log(`Manifest: ${manifestPath}`);
  console.log(`Migration report: ${reportPath}`);
}

async function main() {
  const options = parseCliArgs(process.argv.slice(2));
  const sourceRoot = options.sourceRoot;
  const outputRoot = options.outputRoot;

  console.log(`Source root: ${sourceRoot}`);
  console.log(`Output root: ${outputRoot}`);
  if (options.pluginNames.length > 0) {
    console.log(`Selected plugins: ${options.pluginNames.join(", ")}`);
  }
  await generate(sourceRoot, outputRoot, options);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
