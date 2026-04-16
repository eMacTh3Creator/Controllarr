# Controllarr v1.2.1

## Highlights

- Added built-in network diagnostics to both the native Settings window and the WebUI Settings tab
- Surfaced the current WebUI bind host, detected LAN IPs, VPN interface/IP, and recommended LAN URLs for remote clients
- Added a targeted warning when Controllarr is configured correctly for LAN access but the VPN client is still likely blocking inbound local-network traffic
- Fixed the local **Open Web UI** action so wildcard bind hosts like `0.0.0.0` still open cleanly on loopback
- Relaxed the dylib embedding verification step so local Xcode packaging builds do not fail on the final grep check alone

## Operator Notes

- For Sonarr, Radarr, Overseerr, or another browser on your LAN, bind the WebUI to `0.0.0.0`, restart Controllarr, and target the Mac's LAN IP such as `http://192.168.1.122:8791`
- Torrent traffic remains bound separately to the VPN adapter when VPN interface binding is enabled
- If the diagnostics panel reports that LAN access is configured correctly but remote machines still cannot connect with the VPN enabled, check the VPN client's local-network-access rules or firewall behavior
