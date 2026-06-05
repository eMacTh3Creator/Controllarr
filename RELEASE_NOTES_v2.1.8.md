# v2.1.8 — No Keychain prompts on remote login

This release fixes a trust-eroding macOS prompt that could appear on the torrent Mac when a remote machine logged into the WebUI or qBittorrent-compatible API.

## Fixed

- WebUI password checks no longer read from Keychain during login, so Sonarr, Radarr, Overseerr, or a remote browser should not trigger a `com.controllarr.credentials` prompt.
- Saved *arr API keys now stay in Controllarr's portable app state instead of being moved into Keychain on public ad-hoc builds.
- Legacy Keychain-backed credentials are migrated only when macOS allows a silent read. If an old WebUI password cannot be read without prompting, Controllarr falls back to the default `adminadmin` password so the operator can log in and set a new one.
- Backup/export wording now says "saved secrets" instead of "Keychain secrets."

## Notes

Sparkle update verification is unchanged. Installed Controllarr apps do not need the private Sparkle signing key and should not prompt for Keychain access during weekly update checks.
