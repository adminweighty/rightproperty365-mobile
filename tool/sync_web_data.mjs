// Mirrors the web app's SAMPLE data and photos into this project, so the
// mobile app shows exactly what the web shows.
//
//   node tool/sync_web_data.mjs <path to the web repository>
//
// Reads  <web>/src/lib/data/listings.ts and directory.ts
// Writes assets/data/listings.json, assets/data/directory.json
// Copies <web>/src/assets/images/* (photos and CREDITS.md) to assets/images/
//
// Needs Node 23.6 or newer (it runs the TypeScript sources directly).
import { copyFileSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const web = process.argv[2];
if (!web) {
  console.error("Usage: node tool/sync_web_data.mjs <path to the web repository>");
  process.exit(1);
}

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dataDir = join(web, "src", "lib", "data");
const imageDir = join(web, "src", "assets", "images");
const work = mkdtempSync(join(tmpdir(), "rp365-sync-"));

// The sources import photos as modules and use the "@/" alias. Turn each photo
// import into its file name and point the alias at the copies made here.
const prepare = (name) => {
  const source = readFileSync(join(dataDir, name), "utf8")
    .replace(/^import type .*$/gm, "")
    .replace(/^import (\w+) from "@\/assets\/images\/([^"]+)";$/gm, 'const $1 = "$2";')
    .replace(/from "@\/lib\/data\/(\w+)"/g, 'from "./$1.ts"')
    .replace(/StaticImageData/g, "string");
  writeFileSync(join(work, name), source);
};

try {
  prepare("listings.ts");
  prepare("directory.ts");

  const { listings } = await import(pathToFileURL(join(work, "listings.ts")).href);
  const directory = await import(pathToFileURL(join(work, "directory.ts")).href);

  const out = join(root, "assets", "data");
  mkdirSync(out, { recursive: true });

  writeFileSync(
    join(out, "listings.json"),
    JSON.stringify(
      listings.map((listing) => ({
        ...listing,
        image: { file: listing.image.src, alt: listing.image.alt },
      })),
      null,
      2,
    ) + "\n",
  );

  writeFileSync(
    join(out, "directory.json"),
    JSON.stringify(
      {
        kinds: directory.directoryKinds.map((kind) => ({ kind, ...directory.directories[kind] })),
        // The order trades are shown in, as the web computes it.
        tradeOrder: directory.serviceCategories().map((group) => group.category),
        profiles: directory.profiles,
      },
      null,
      2,
    ) + "\n",
  );

  const images = join(root, "assets", "images");
  mkdirSync(images, { recursive: true });
  const files = readdirSync(imageDir).filter((file) => /\.(jpg|jpeg|png|webp)$/i.test(file) || file === "CREDITS.md");
  for (const file of files) copyFileSync(join(imageDir, file), join(images, file));

  const missing = listings.map((l) => l.image.src).filter((file) => !files.includes(file));
  if (missing.length) throw new Error(`Photos referenced but not found: ${missing.join(", ")}`);

  console.log(`listings: ${listings.length}, profiles: ${directory.profiles.length}, files copied: ${files.length}`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
