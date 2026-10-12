const { test } = require("node:test");
const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const path = require("node:path");
const {
  firewallScript,
  allowTabletNetwork,
} = require("../windows-network.cjs");
test("tablet firewall access is scoped to its runtime, private networks and the local subnet", () => {
  const script = firewallScript("C:\\StudioPrompter\\runtime\\node.exe");
  const rules = script
    .split("\n")
    .filter((line) => line.startsWith("New-NetFirewallRule"));
  assert.equal(rules.length, 2);
  for (const rule of rules) {
    assert.match(rule, /-Program \$program/);
    assert.match(rule, /-Profile Private -RemoteAddress LocalSubnet/);
    assert.match(rule, /-Direction Inbound/);
  }
  assert.match(rules[1], /-Protocol UDP -LocalPort 5353/);
  assert.doesNotMatch(
    script,
    /Set-NetConnectionProfile|Set-NetFirewallProfile/,
  );
});
test(
  "Windows parses quoted runtime paths without expanding them as commands",
  { skip: process.platform !== "win32" },
  () => {
    const program = "C:\\Apps\\Jack's `special` $(exit 1)\\runtime\\node.exe";
    const source = Buffer.from(firewallScript(program), "utf16le").toString(
      "base64",
    );
    const expected = Buffer.from(program, "utf16le").toString("base64");
    const check = `$s=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('${source}'))
$expected=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('${expected}'))
$t=$null;$e=$null
$a=[Management.Automation.Language.Parser]::ParseInput($s,[ref]$t,[ref]$e)
if($e.Count -gt 0){throw 'Invalid network setup syntax'}
$found=$a.Find({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -eq $expected},$true)
if($null -eq $found){throw 'Runtime path was not preserved as a literal'}
`;
    execFileSync(
      path.join(
        process.env.SystemRoot,
        "System32",
        "WindowsPowerShell",
        "v1.0",
        "powershell.exe",
      ),
      [
        "-NoProfile",
        "-NonInteractive",
        "-EncodedCommand",
        Buffer.from(check, "utf16le").toString("base64"),
      ],
      { windowsHide: true, timeout: 60000 },
    );
  },
);
test(
  "network setup refuses to modify non-Windows systems",
  { skip: process.platform === "win32" },
  async () => {
    await assert.rejects(
      allowTabletNetwork("/tmp/runtime"),
      /only needed on Windows/,
    );
  },
);
