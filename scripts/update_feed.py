"""Validation shared by the stable and tester Apple-silicon update feeds."""
import base64
import re
import xml.etree.ElementTree as ET
from urllib.parse import quote

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
REPOSITORY = "codebooker/StudioPrompter"


def inspect_feed(data, *, tag=None, previous=None):
    root = ET.fromstring(data)
    if root.tag != "rss" or root.find("channel") is None:
        raise ValueError("Expected an RSS appcast channel")
    items = root.findall("channel/item")
    if tag is None and not items:
        return None  # Initial feed before the first public release.
    if len(items) != 1:
        raise ValueError("The feed must contain exactly one current release")
    item = items[0]
    version = item.findtext(SPARKLE + "version", "")
    short_version = item.findtext(SPARKLE + "shortVersionString", "")
    if not re.fullmatch(r"[1-9][0-9]*", version):
        raise ValueError("An increasing integer CFBundleVersion is required")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", short_version):
        raise ValueError("Numeric semantic versions are required in this feed")
    if tag is not None and tag != short_version:
        raise ValueError("Release tag and app display version do not match")
    if item.find(SPARKLE + "channel") is not None:
        raise ValueError("Use a separate feed instead of a Sparkle channel")
    if item.findtext(SPARKLE + "minimumSystemVersion") != "13.3":
        raise ValueError("Expected the supported macOS 13.3 minimum")
    if item.findtext(SPARKLE + "hardwareRequirements") != "arm64":
        raise ValueError("An arm64-only archive must be restricted to Apple silicon")
    enclosures = item.findall("enclosure")
    if len(enclosures) != 1:
        raise ValueError("Expected exactly one update archive")
    enclosure = enclosures[0]
    expected_name = f"StudioPrompter-{short_version}-macos-arm64.zip"
    expected_url = f"https://github.com/{REPOSITORY}/releases/download/{quote(short_version)}/{expected_name}"
    if enclosure.get("url") != expected_url:
        raise ValueError("Archive must be the matching StudioPrompter GitHub release asset")
    if len(base64.b64decode(enclosure.get(SPARKLE + "edSignature", ""), validate=True)) != 64:
        raise ValueError("A valid Ed25519 signature is required")
    size = int(enclosure.get("length", "0"))
    if size <= 0:
        raise ValueError("Archive size must be positive")
    if previous:
        old = inspect_feed(previous)
        if old and int(version) <= old["build"]:
            raise ValueError("Update build number must increase; refusing downgrade or overwrite")
    return {"build": int(version), "version": short_version, "archive": expected_name, "size": size}
