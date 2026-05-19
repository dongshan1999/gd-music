const fs = require("fs/promises");
const path = require("path");
const { TextDecoder } = require("util");

const PROJECT_ROOT = path.resolve(__dirname, "..");
const TARGETS = [
  path.join(PROJECT_ROOT, "source_plugins"),
  path.join(PROJECT_ROOT, "source_types"),
];

const decoder = new TextDecoder("utf-8", { fatal: true });

async function collectFiles(root) {
  const entries = await fs.readdir(root, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const fullPath = path.join(root, entry.name);
    if (entry.isDirectory()) {
      files.push(...await collectFiles(fullPath));
      continue;
    }
    if (entry.isFile() && (entry.name.endsWith(".ts") || entry.name.endsWith(".d.ts"))) {
      files.push(fullPath);
    }
  }
  return files;
}

async function main() {
  let checked = 0;
  for (const target of TARGETS) {
    const files = await collectFiles(target);
    for (const filePath of files) {
      const raw = await fs.readFile(filePath);
      decoder.decode(raw);
      checked += 1;
    }
  }

  console.log(`UTF-8 check passed for ${checked} TypeScript files.`);
  console.log("If terminal output looks garbled, prefer a UTF-8 aware viewer before rewriting source files.");
}

main().catch((error) => {
  console.error("UTF-8 check failed:", error);
  process.exitCode = 1;
});
