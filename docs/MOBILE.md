# Controllarr Remote for iOS

The native SwiftUI iPhone/iPad preview requires iOS 17+ and Controllarr server
v2.3.0+ on macOS or Windows. It does not run a torrent engine on the phone.

## Connect

1. On the server, change the default admin password. Set WebUI bind host to a
   specific LAN address or `0.0.0.0`, and restart.
2. Enable **Advertise to iOS on the LAN** in server Settings (restart required).
   Allow private-network firewall access. Discovery uses `_controllarr._tcp`
   multicast DNS/UDP 5353 and normally does not cross routers/VLANs.
3. In iOS **Instances**, select a Nearby server or add a hostname/address, e.g.
   `plexbox.local:8791` or `https://plex.example.com/controllarr`.
4. Enter WebUI credentials. Unencrypted HTTP requires an explicit opt-in and is
   suitable only for a trusted LAN or an encrypted private VPN.

Discovery advertises a name/port/protocol, never credentials. It can be disabled.
A loopback-only server is not advertised. VPN products may block LAN multicast;
manual hostname/IP setup remains available. Discovery is not proof that the
VPN firewall allows API traffic. Torrent binding and the control-plane listener
remain separate.

For Internet access, use an encrypted private VPN or HTTPS reverse proxy with a
trusted certificate. Do not port-forward the plaintext admin port to the Internet.
Redirects and invalid/self-signed TLS certificates are not silently accepted.
Passwords are held in the iOS app's private Keychain, without biometric/password
access-control prompts; unavailable credentials require re-entry, not a prompt loop.
The Mac/Windows server does not acquire a new runtime Keychain dependency.

## Controls

Up to eight saved servers; 100-row pages with server-side search/category filters;
magnet and `.torrent` intake; pause, resume, force resume, recheck, reannounce,
move, confirmed keep-files/delete-files removal, category assignment, category
CRUD, schema-preserving settings editing, file priorities, trackers/peers,
health clearing, post-processing retries, logs and VPN diagnostics. Page-based
selection is deliberate: **Select Page** does not secretly select the whole server.

The server accepts explicit `contentLayout=Subfolder` for *arr/mobile intake.
Legacy categories retain their previous policy. Trailing separators are unnecessary.
Folder repair moves only a selected torrent after confirmation, rejects conflicting
destinations, and is not an automatic migration of all existing downloads.

## Notifications

Opt in separately to completion, error, VPN-disconnect and listen-port-change
alerts. The first connection establishes a baseline without flooding alerts for
the existing library. The server retains 512 in-memory events and signals cursor
reset after restart/retention loss. This is not an audit log or guaranteed delivery.

This preview polls while active and requests best-effort iOS background refresh
for the selected instance. iOS controls timing; force-quitting, local-network
privacy, network availability and device lock can prevent delivery. **No APNs
push service is included.** Reliable suspended-app alerts remain release work
requiring APNs integration, device-token registration and a secure push provider.

## Distribution

Source and a simulator app are published as developer previews. A simulator ZIP
cannot be installed on a physical iPhone. Device build 1.0.0 (2) was delivered
through Apple Transporter on October 8, 2026 using release Xcode, valid Apple
Distribution signing and the matching provisioning profile. Apple processing
completed, and the build is active in the publisher's internal TestFlight group.
Invited internal testers install using Apple's TestFlight app, not the simulator
ZIP. Public beta access still requires external-testing setup and Apple beta
review; this is not yet a public TestFlight release. See [iOS build guide](../iOS/README.md).
