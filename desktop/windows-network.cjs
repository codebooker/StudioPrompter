"use strict";
const { execFile } = require("node:child_process");
const path = require("node:path");
const literal = (value) => "'" + value.replaceAll("'", "''") + "'";
const encode = (script) => Buffer.from(script, "utf16le").toString("base64");
function firewallScript(program) {
  return `$ErrorActionPreference = 'Stop'
$program = ${literal(program)}
Get-NetFirewallRule -Name 'StudioPrompter-Tablet-TCP','StudioPrompter-Tablet-Discovery' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -Name 'StudioPrompter-Tablet-TCP' -DisplayName 'StudioPrompter tablet connections' -Direction Inbound -Action Allow -Program $program -Protocol TCP -Profile Private -RemoteAddress LocalSubnet | Out-Null
New-NetFirewallRule -Name 'StudioPrompter-Tablet-Discovery' -DisplayName 'StudioPrompter tablet discovery' -Direction Inbound -Action Allow -Program $program -Protocol UDP -LocalPort 5353 -Profile Private -RemoteAddress LocalSubnet | Out-Null
`;
}
function run(script) {
  const powershell = path.join(
    process.env.SystemRoot || "C:\\Windows",
    "System32",
    "WindowsPowerShell",
    "v1.0",
    "powershell.exe",
  );
  return new Promise((resolve, reject) =>
    execFile(
      powershell,
      ["-NoProfile", "-NonInteractive", "-EncodedCommand", encode(script)],
      { windowsHide: true, timeout: 120000, maxBuffer: 32768 },
      (error, stdout) => {
        if (error)
          reject(
            Error(
              "Windows network setup was cancelled or could not complete. An administrator must allow StudioPrompter tablet connections on this private network.",
            ),
          );
        else resolve(stdout.trim());
      },
    ),
  );
}
async function allowTabletNetwork(runtime) {
  if (process.platform !== "win32")
    throw Error("Network setup is only needed on Windows");
  const program = path.join(runtime, "node.exe");
  // The user clicks Allow, then Windows asks them to approve administrator
  // access. Never run this on startup or change their network's trust category.
  const script = firewallScript(program);
  await run(`$ErrorActionPreference='Stop'
$p = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -Wait -PassThru -ArgumentList '-NoProfile','-NonInteractive','-EncodedCommand','${encode(script)}'
if ($p.ExitCode -ne 0) { exit 1 }
`);
  const profile = await run(
    "Get-NetConnectionProfile | Select-Object -ExpandProperty NetworkCategory",
  );
  return { privateNetwork: profile.split(/\r?\n/).includes("Private") };
}
module.exports = { allowTabletNetwork, firewallScript };
