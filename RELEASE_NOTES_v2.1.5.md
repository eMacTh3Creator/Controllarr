# Controllarr v2.1.5

Small UI hotfix for the VPN forwarded-port setting added in v2.1.4.

## What's Changed

- Replaced the native macOS preferred forwarded-port stepper with a direct text field.
- Replaced the WebUI preferred forwarded-port control with a dedicated numeric text box.
- Keeps validation bounded to the valid TCP/UDP port range, `1...65535`.

## Why

VPN providers such as PIA often show a concrete forwarded port, for example
`53127`. Operators should be able to type or paste that value directly instead
of clicking a stepper thousands of times.

## Install

Download `Controllarr-v2.1.5-macOS-arm64.zip` from the GitHub release, unzip,
move `Controllarr.app` to `/Applications`, and self-sign if needed:

```bash
codesign --force --deep -s - /Applications/Controllarr.app
xattr -rd com.apple.quarantine /Applications/Controllarr.app
```
