import {
  mkdir,
  writeFile,
  readFile,
  copyFile,
  chmod,
  rm,
} from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
// Electron's BoringSSL omits the Mac's PSK-AES-GCM cipher. Use official Node/OpenSSL.
const version = "22.22.2",
  platform = process.platform === "win32" ? "win" : process.platform,
  arch = process.argv[2] || process.arch;
if (
  !["x64", "arm64"].includes(arch) ||
  !["win", "linux", "darwin"].includes(platform)
)
  throw Error("Unsupported runtime target");
const root = fileURLToPath(new URL("../", import.meta.url)),
  folder = path.join(root, ".build", "network-runtime", `${platform}-${arch}`);
const name = `node-v${version}-${platform}-${arch}`,
  archive = `${name}.${platform === "win" ? "zip" : "tar.gz"}`,
  base = `https://nodejs.org/download/release/v${version}/`;
await mkdir(folder, { recursive: true });
const sums = await (await fetch(base + "SHASUMS256.txt")).text();
const checksum = sums
  .split("\n")
  .find((line) => line.trim().endsWith(" " + archive))
  ?.split(/\s+/)[0];
if (!checksum || !/[a-f0-9]{64}/.test(checksum))
  throw Error("Official runtime checksum missing");
const archivePath = path.join(folder, archive);
let bytes;
try {
  bytes = await readFile(archivePath);
} catch {}
if (
  !bytes ||
  crypto.createHash("sha256").update(bytes).digest("hex") !== checksum
) {
  const response = await fetch(base + archive, {
    signal: AbortSignal.timeout(120000),
  });
  if (!response.ok) throw Error("Runtime download failed");
  bytes = Buffer.from(await response.arrayBuffer());
  if (
    bytes.length > 100000000 ||
    crypto.createHash("sha256").update(bytes).digest("hex") !== checksum
  )
    throw Error("Runtime integrity check failed");
  await writeFile(archivePath, bytes);
}
await rm(path.join(folder, name), { recursive: true, force: true });
const extracted = spawnSync("tar", ["-xf", archivePath, "-C", folder], {
  stdio: "inherit",
});
if (extracted.status !== 0) throw Error("Runtime extraction failed");
const target = path.join(root, "desktop", "runtime");
await mkdir(target, { recursive: true });
const exe = platform === "win" ? "node.exe" : "node";
await copyFile(
  path.join(folder, name, platform === "win" ? exe : "bin/node"),
  path.join(target, exe),
);
await copyFile(
  path.join(folder, name, "LICENSE"),
  path.join(target, "node-LICENSE.txt"),
);
if (platform !== "win") await chmod(path.join(target, exe), 0o755);
console.log(`Verified Node ${version} network runtime for ${platform}/${arch}`);
