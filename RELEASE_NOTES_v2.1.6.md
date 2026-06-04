# Controllarr v2.1.6

Small UI consistency hotfix for port settings.

## What's Changed

- Native macOS Settings now shows WebUI port, preferred forwarded port, listen range start, and listen range end as matching rounded text fields.
- WebUI Settings now uses the same type/paste port input for WebUI port, preferred forwarded port, listen range start, and listen range end.
- Port inputs accept pasted digits and clamp to the valid `1...65535` range.

## Why

The port range fields were already editable, but they looked and behaved
differently from the preferred forwarded-port field. This release makes all
operator-entered port values feel consistent.

## Install

Download `Controllarr-v2.1.6-macOS-arm64.zip` from the GitHub release, unzip,
move `Controllarr.app` to `/Applications`, and self-sign if needed:

```bash
codesign --force --deep -s - /Applications/Controllarr.app
xattr -rd com.apple.quarantine /Applications/Controllarr.app
```
