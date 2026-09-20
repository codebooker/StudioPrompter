"use strict";
// A small build-time manifest keeps download links current, including tester releases.
fetch(new URL("release.json", document.currentScript.src))
  .then((r) => (r.ok ? r.json() : Promise.reject()))
  .then((r) => {
    if (
      !/^https:\/\/github\.com\/codebooker\/StudioPrompter\/releases\/download\/[A-Za-z0-9._-]+\/StudioPrompter-[A-Za-z0-9._-]+\.dmg$/.test(
        r.dmg,
      )
    )
      return;
    document.querySelectorAll("a.download").forEach((a) => (a.href = r.dmg));
    const version = document.getElementById("release-version");
    if (version) version.textContent = r.version;
  })
  .catch(() => {});
