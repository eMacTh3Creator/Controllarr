#!/usr/bin/env python3
"""Write Controllarr's Sparkle appcast for a signed release zip.

The private Ed25519 key stays in the macOS Keychain. This script calls
Sparkle's sign_update tool and commits only the public appcast metadata.
"""

from __future__ import annotations

import argparse
import email.utils
import html
import os
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SIGN_UPDATE = ROOT / ".build" / "artifacts" / "sparkle" / "Sparkle" / "bin" / "sign_update"
SPARKLE_ACCOUNT = "com.controllarr.updates"


def parse_signature(output: str) -> tuple[str, str]:
    signature_match = re.search(r'sparkle:edSignature="([^"]+)"', output)
    length_match = re.search(r'length="([^"]+)"', output)
    if not signature_match or not length_match:
        raise RuntimeError(f"Could not parse sign_update output:\n{output}")
    return signature_match.group(1), length_match.group(1)


def main() -> int:
    parser = argparse.ArgumentParser(description="Update appcast.xml for a Controllarr release.")
    parser.add_argument("--version", required=True, help="Marketing version, for example 2.1.7")
    parser.add_argument("--build", required=True, help="CFBundleVersion / Sparkle version, for example 217")
    parser.add_argument("--zip", required=True, type=Path, help="Path to the release zip")
    parser.add_argument("--output", default=ROOT / "appcast.xml", type=Path, help="Appcast path")
    args = parser.parse_args()

    zip_path = args.zip.resolve()
    if not zip_path.exists():
        raise FileNotFoundError(zip_path)
    if not SIGN_UPDATE.exists():
        raise FileNotFoundError(SIGN_UPDATE)

    private_key = os.environ.get("SPARKLE_PRIVATE_KEY")
    if private_key:
        signed = subprocess.run(
            [str(SIGN_UPDATE), "--ed-key-file", "-", str(zip_path)],
            input=private_key,
            check=True,
            text=True,
            capture_output=True,
        )
    else:
        signed = subprocess.run(
            [str(SIGN_UPDATE), "--account", SPARKLE_ACCOUNT, str(zip_path)],
            check=True,
            text=True,
            capture_output=True,
        )
    signature, length = parse_signature(signed.stdout)

    version = args.version.removeprefix("v")
    tag = f"v{version}"
    title = f"Version {version}"
    zip_name = f"Controllarr-{tag}-macOS-arm64.zip"
    release_url = f"https://github.com/eMacTh3Creator/Controllarr/releases/tag/{tag}"
    download_url = f"https://github.com/eMacTh3Creator/Controllarr/releases/download/{tag}/{zip_name}"
    pub_date = email.utils.formatdate(usegmt=True)

    xml = f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Controllarr Updates</title>
    <description>Automatic update feed for Controllarr.</description>
    <language>en</language>
    <link>https://emacth3creator.github.io/Controllarr/</link>
    <item>
      <title>{html.escape(title)}</title>
      <sparkle:version>{html.escape(args.build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>{html.escape(release_url)}</sparkle:releaseNotesLink>
      <pubDate>{html.escape(pub_date)}</pubDate>
      <enclosure
        url="{html.escape(download_url)}"
        sparkle:edSignature="{html.escape(signature)}"
        length="{html.escape(length)}"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
'''

    args.output.write_text(xml)
    print(f"Wrote {args.output}")
    print(f"{zip_name}: length={length} sparkle:edSignature={signature}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
