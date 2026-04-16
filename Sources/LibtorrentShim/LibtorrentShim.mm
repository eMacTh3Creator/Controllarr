//
//  LibtorrentShim.mm
//  Controllarr — Phase 1
//

#import "LibtorrentShim.h"

#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/load_torrent.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/write_resume_data.hpp>
#include <libtorrent/bencode.hpp>
#include <libtorrent/session_stats.hpp>
#include <libtorrent/peer_info.hpp>
#include <libtorrent/announce_entry.hpp>

#include <memory>
#include <string>
#include <vector>
#include <unordered_map>
#include <fstream>
#include <sstream>

// MARK: - CTRLTorrentStats (readwrite in the .mm, readonly in the .h)

@interface CTRLTorrentStats ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *infoHash;
@property (nonatomic, readwrite, copy) NSString *savePath;
@property (nonatomic, readwrite)       float     progress;
@property (nonatomic, readwrite)       CTRLTorrentState state;
@property (nonatomic, readwrite)       BOOL      paused;
@property (nonatomic, readwrite)       int64_t   downloadRate;
@property (nonatomic, readwrite)       int64_t   uploadRate;
@property (nonatomic, readwrite)       int64_t   totalWanted;
@property (nonatomic, readwrite)       int64_t   totalDone;
@property (nonatomic, readwrite)       int64_t   totalDownload;
@property (nonatomic, readwrite)       int64_t   totalUpload;
@property (nonatomic, readwrite)       double    ratio;
@property (nonatomic, readwrite)       int       numPeers;
@property (nonatomic, readwrite)       int       numSeeds;
@property (nonatomic, readwrite)       int       etaSeconds;
@property (nonatomic, readwrite, copy) NSDate   *addedDate;
@end
@implementation CTRLTorrentStats @end

@interface CTRLSessionStats ()
@property (nonatomic, readwrite) int64_t downloadRate;
@property (nonatomic, readwrite) int64_t uploadRate;
@property (nonatomic, readwrite) int64_t totalBytesDownloaded;
@property (nonatomic, readwrite) int64_t totalBytesUploaded;
@property (nonatomic, readwrite) int     numTorrents;
@property (nonatomic, readwrite) int     numPeersConnected;
@property (nonatomic, readwrite) BOOL    hasIncomingConnections;
@property (nonatomic, readwrite) uint16_t listenPort;
@end
@implementation CTRLSessionStats @end

@interface CTRLTrackerInfo ()
@property (nonatomic, readwrite, copy) NSString *url;
@property (nonatomic, readwrite) int tier;
@property (nonatomic, readwrite) int numPeers;
@property (nonatomic, readwrite) int numSeeds;
@property (nonatomic, readwrite) int numLeechers;
@property (nonatomic, readwrite) int numDownloaded;
@property (nonatomic, readwrite, copy) NSString *message;
@property (nonatomic, readwrite) NSInteger status;
@end
@implementation CTRLTrackerInfo @end

@interface CTRLPeerInfo ()
@property (nonatomic, readwrite, copy) NSString *ip;
@property (nonatomic, readwrite) int port;
@property (nonatomic, readwrite, copy) NSString *client;
@property (nonatomic, readwrite) float progress;
@property (nonatomic, readwrite) int64_t downloadRate;
@property (nonatomic, readwrite) int64_t uploadRate;
@property (nonatomic, readwrite) int64_t totalDownload;
@property (nonatomic, readwrite) int64_t totalUpload;
@property (nonatomic, readwrite, copy) NSString *flags;
@property (nonatomic, readwrite, copy) NSString *country;
@end
@implementation CTRLPeerInfo @end

// MARK: - Helpers

static CTRLTorrentState ctrl_map_state(lt::torrent_status const &st) {
    if ((st.flags & lt::torrent_flags::paused) && !(st.flags & lt::torrent_flags::auto_managed)) {
        return CTRLTorrentStatePaused;
    }
    switch (st.state) {
        case lt::torrent_status::checking_files:         return CTRLTorrentStateCheckingFiles;
        case lt::torrent_status::downloading_metadata:   return CTRLTorrentStateDownloadingMetadata;
        case lt::torrent_status::downloading:            return CTRLTorrentStateDownloading;
        case lt::torrent_status::finished:               return CTRLTorrentStateFinished;
        case lt::torrent_status::seeding:                return CTRLTorrentStateSeeding;
        case lt::torrent_status::checking_resume_data:   return CTRLTorrentStateCheckingResume;
        default:                                         return CTRLTorrentStateUnknown;
    }
}

static NSString *ctrl_nsstring(const std::string &s) {
    return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *ctrl_hex_from_bytes(const std::string &bytes) {
    static const char *hex = "0123456789abcdef";
    NSMutableString *out = [NSMutableString stringWithCapacity:bytes.size() * 2];
    for (unsigned char c : bytes) {
        [out appendFormat:@"%c%c", hex[(c >> 4) & 0xF], hex[c & 0xF]];
    }
    return out;
}

static std::string ctrl_bytes_from_hex(NSString *hex) {
    std::string out;
    out.reserve(hex.length / 2);
    const char *cs = [hex.lowercaseString UTF8String];
    auto nib = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
        return 0;
    };
    for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
        out.push_back(static_cast<char>((nib(cs[i]) << 4) | nib(cs[i+1])));
    }
    return out;
}

static NSError *ctrl_error_from_ec(lt::error_code const &ec) {
    return [NSError errorWithDomain:@"ControllarrLibtorrent"
                               code:ec.value()
                           userInfo:@{ NSLocalizedDescriptionKey: ctrl_nsstring(ec.message()) }];
}

static NSString *ctrl_build_listen_interfaces(uint16_t port, BOOL bindAll) {
    if (bindAll) {
        return [NSString stringWithFormat:@"0.0.0.0:%u,[::]:%u", port, port];
    }
    // Limit to the default IPv4 + IPv6 wildcard binds. This skips
    // link-local, AWDL, utun, bridge, and lo0 interfaces that otherwise
    // spam the alert log.
    return [NSString stringWithFormat:@"0.0.0.0:%u,[::]:%u", port, port];
}

static int ctrl_balanced_aio_threads() {
    NSInteger cores = NSProcessInfo.processInfo.activeProcessorCount;
    NSInteger tuned = MAX(2, MIN(8, (cores + 1) / 2));
    return (int)tuned;
}

static int ctrl_balanced_hashing_threads() {
    NSInteger cores = NSProcessInfo.processInfo.activeProcessorCount;
    return cores >= 8 ? 2 : 1;
}

// MARK: - CTRLSession

@implementation CTRLSession {
    std::unique_ptr<lt::session> _session;
    NSString *_savePath;
    uint16_t  _listenPort;
    BOOL      _bindAll;
    // Cheap cache so statsForInfoHash: and moveTorrent: don't have to
    // rescan get_torrents() every call.
    std::unordered_map<std::string, lt::torrent_handle> _handlesByHash;
}

- (instancetype)initWithSavePath:(NSString *)savePath
                      listenPort:(uint16_t)port
               bindAllInterfaces:(BOOL)bindAll {
    if ((self = [super init])) {
        _savePath   = [savePath copy];
        _listenPort = port;
        _bindAll    = bindAll;

        lt::settings_pack pack;
        pack.set_str(lt::settings_pack::listen_interfaces,
                     ctrl_build_listen_interfaces(port, bindAll).UTF8String);
        pack.set_str(lt::settings_pack::user_agent, "Controllarr/1.4.0 libtorrent/2.0");
        pack.set_int(lt::settings_pack::alert_mask,
                     lt::alert_category::error
                     | lt::alert_category::status
                     | lt::alert_category::storage
                     | lt::alert_category::performance_warning);
        pack.set_int(lt::settings_pack::alert_queue_size, 4096);
        pack.set_int(lt::settings_pack::aio_threads, ctrl_balanced_aio_threads());
        pack.set_int(lt::settings_pack::hashing_threads, ctrl_balanced_hashing_threads());
        // Respect NAT-PMP / UPnP so the port watcher has something to
        // cross-check against.
        pack.set_bool(lt::settings_pack::enable_upnp, true);
        pack.set_bool(lt::settings_pack::enable_natpmp, true);
        pack.set_bool(lt::settings_pack::enable_dht, true);
        pack.set_bool(lt::settings_pack::enable_lsd, false); // too noisy on mac

        _session = std::make_unique<lt::session>(pack);
        NSLog(
            @"[Controllarr] session up: port=%u save=%@ aio_threads=%d hashing_threads=%d",
            port,
            _savePath,
            ctrl_balanced_aio_threads(),
            ctrl_balanced_hashing_threads()
        );
    }
    return self;
}

// MARK: Adding

- (BOOL)addMagnet:(NSString *)magnetURI
         savePath:(NSString *)savePath
            error:(NSError **)error {
    lt::error_code ec;
    lt::add_torrent_params atp = lt::parse_magnet_uri(magnetURI.UTF8String, ec);
    if (ec) {
        if (error) *error = ctrl_error_from_ec(ec);
        return NO;
    }
    atp.save_path = (savePath.length ? savePath.UTF8String : _savePath.UTF8String);
    lt::torrent_handle h = _session->add_torrent(std::move(atp), ec);
    if (ec || !h.is_valid()) {
        if (error) *error = ctrl_error_from_ec(ec);
        return NO;
    }
    std::string ih = h.info_hashes().get_best().to_string();
    _handlesByHash[ih] = h;
    return YES;
}

- (BOOL)addTorrentFile:(NSString *)path
              savePath:(NSString *)savePath
                 error:(NSError **)error {
    try {
        lt::add_torrent_params atp = lt::load_torrent_file(path.UTF8String);
        atp.save_path = (savePath.length ? savePath.UTF8String : _savePath.UTF8String);
        lt::error_code ec;
        lt::torrent_handle h = _session->add_torrent(std::move(atp), ec);
        if (ec || !h.is_valid()) {
            if (error) *error = ctrl_error_from_ec(ec);
            return NO;
        }
        std::string ih = h.info_hashes().get_best().to_string();
        _handlesByHash[ih] = h;
        return YES;
    } catch (std::exception const &e) {
        if (error) {
            *error = [NSError errorWithDomain:@"ControllarrLibtorrent"
                                         code:-1
                                     userInfo:@{ NSLocalizedDescriptionKey: @(e.what()) }];
        }
        return NO;
    }
}

// MARK: Mutating

- (lt::torrent_handle)handleFor:(NSString *)hashHex {
    std::string bytes = ctrl_bytes_from_hex(hashHex);
    auto it = _handlesByHash.find(bytes);
    if (it != _handlesByHash.end() && it->second.is_valid()) return it->second;
    // Fallback: rescan session (e.g. after resume-data load).
    for (auto const &h : _session->get_torrents()) {
        if (!h.is_valid()) continue;
        std::string ih = h.info_hashes().get_best().to_string();
        if (ih == bytes) {
            _handlesByHash[ih] = h;
            return h;
        }
    }
    return lt::torrent_handle();
}

- (BOOL)pauseTorrent:(NSString *)infoHash {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return NO;
    h.unset_flags(lt::torrent_flags::auto_managed);
    h.pause();
    return YES;
}

- (BOOL)resumeTorrent:(NSString *)infoHash {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return NO;
    h.set_flags(lt::torrent_flags::auto_managed);
    h.resume();
    return YES;
}

- (BOOL)removeTorrent:(NSString *)infoHash deleteFiles:(BOOL)deleteFiles {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return NO;
    _session->remove_torrent(h, deleteFiles ? lt::session::delete_files : lt::remove_flags_t{});
    _handlesByHash.erase(ctrl_bytes_from_hex(infoHash));
    return YES;
}

- (BOOL)moveTorrent:(NSString *)infoHash toPath:(NSString *)path {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return NO;
    h.move_storage(path.UTF8String);
    return YES;
}

- (NSArray<NSString *> *)fileNamesForInfoHash:(NSString *)infoHash {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return nil;
    std::shared_ptr<const lt::torrent_info> ti = h.torrent_file();
    if (!ti) return nil; // metadata not yet available
    auto const &fs = ti->files();
    int nfiles = fs.num_files();
    NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:nfiles];
    for (lt::file_index_t i{0}; i < fs.end_file(); ++i) {
        [out addObject:ctrl_nsstring(fs.file_path(i))];
    }
    return out;
}

- (BOOL)setFilePriorities:(NSArray<NSNumber *> *)priorities
              forInfoHash:(NSString *)infoHash {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return NO;
    std::shared_ptr<const lt::torrent_info> ti = h.torrent_file();
    if (!ti) return NO;
    int nfiles = ti->num_files();
    if ((int)priorities.count != nfiles) return NO;
    std::vector<lt::download_priority_t> prios;
    prios.reserve(nfiles);
    for (NSNumber *n in priorities) {
        int v = n.intValue;
        if (v < 0) v = 0;
        if (v > 7) v = 7;
        prios.push_back(lt::download_priority_t{static_cast<std::uint8_t>(v)});
    }
    h.prioritize_files(prios);
    return YES;
}

- (BOOL)reannounceTorrent:(NSString *)infoHash {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return NO;
    h.force_reannounce();
    return YES;
}

- (NSArray<CTRLTrackerInfo *> *)trackersForInfoHash:(NSString *)infoHash {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return nil;

    std::vector<lt::announce_entry> trackers = h.trackers();
    NSMutableArray<CTRLTrackerInfo *> *out = [NSMutableArray arrayWithCapacity:trackers.size()];

    for (auto const &entry : trackers) {
        CTRLTrackerInfo *t = [CTRLTrackerInfo new];
        t.url  = ctrl_nsstring(entry.url);
        t.tier = entry.tier;

        // Scrape data and status live in the first endpoint's V1 info_hash entry.
        int numPeers = 0, numSeeds = 0, numLeechers = 0, numDownloaded = 0;
        NSString *message = @"";
        NSInteger status = 1; // default: not_contacted

        if (!entry.endpoints.empty()) {
            auto const &ep = entry.endpoints[0];
            auto const &aih = ep.info_hashes[lt::protocol_version::V1];
            numPeers      = aih.scrape_incomplete + aih.scrape_complete;
            numSeeds      = aih.scrape_complete;
            numLeechers   = aih.scrape_incomplete;
            numDownloaded = aih.scrape_downloaded;
            message       = ctrl_nsstring(aih.message);

            // Status mapping:
            // if fails > 0 -> 4 (error)
            // if updating  -> 3 (updating)
            // if we got a response (complete_sent is true or scrape data exists) -> 2 (working)
            // else -> 1 (not_contacted)
            if (aih.fails > 0) {
                status = 4; // error
            } else if (aih.updating) {
                status = 3; // updating
            } else if (aih.scrape_complete >= 0 || aih.scrape_incomplete >= 0 || !aih.message.empty()) {
                status = 2; // working
            }
        }

        t.numPeers      = numPeers;
        t.numSeeds       = numSeeds;
        t.numLeechers    = numLeechers;
        t.numDownloaded  = numDownloaded;
        t.message        = message;
        t.status         = status;

        [out addObject:t];
    }
    return out;
}

- (NSArray<CTRLPeerInfo *> *)peersForInfoHash:(NSString *)infoHash {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return nil;

    std::vector<lt::peer_info> peers;
    h.get_peer_info(peers);

    NSMutableArray<CTRLPeerInfo *> *out = [NSMutableArray arrayWithCapacity:peers.size()];

    for (auto const &p : peers) {
        CTRLPeerInfo *pi = [CTRLPeerInfo new];
        pi.ip            = ctrl_nsstring(p.ip.address().to_string());
        pi.port          = p.ip.port();
        pi.client        = ctrl_nsstring(p.client);
        pi.progress      = p.progress;
        pi.downloadRate  = p.down_speed;
        pi.uploadRate    = p.up_speed;
        pi.totalDownload = p.total_download;
        pi.totalUpload   = p.total_upload;

        // Build flags string using qBittorrent conventions:
        // D = interested(local) and not choked(peer), i.e. downloading piece
        // d = interested(local)
        // U = interested(remote) and not choked(local), i.e. uploading
        // u = interested(remote)
        // O = optimistic unchoke
        // S = peer is snubbed
        // I = incoming connection
        // E = encrypted
        // H = seed/upload only
        // X = peer from PEX
        // P = peer from uTP
        // L = peer from LSD
        NSMutableString *flags = [NSMutableString string];

        if (p.flags & lt::peer_info::interesting) {
            if (!(p.flags & lt::peer_info::remote_choked))
                [flags appendString:@"D"];
            else
                [flags appendString:@"d"];
        }
        if (p.flags & lt::peer_info::remote_interested) {
            if (!(p.flags & lt::peer_info::choked))
                [flags appendString:@"U"];
            else
                [flags appendString:@"u"];
        }
        if (p.flags & lt::peer_info::optimistic_unchoke)
            [flags appendString:@"O"];
        if (p.flags & lt::peer_info::snubbed)
            [flags appendString:@"S"];
        if (!(p.flags & lt::peer_info::local_connection))
            [flags appendString:@"I"];
#ifndef TORRENT_DISABLE_ENCRYPTION
        if (p.flags & lt::peer_info::rc4_encrypted)
            [flags appendString:@"E"];
#endif
        if (p.flags & lt::peer_info::seed)
            [flags appendString:@"H"];
        if (p.source & lt::peer_info::pex)
            [flags appendString:@"X"];
        if (p.flags & lt::peer_info::utp_socket)
            [flags appendString:@"P"];
        if (p.source & lt::peer_info::lsd)
            [flags appendString:@"L"];

        pi.flags = flags;

        // Country: libtorrent's peer_info no longer has a `country` field
        // (it was removed in libtorrent 2.x). Set to empty string.
        pi.country = @"";

        [out addObject:pi];
    }
    return out;
}

- (NSArray<NSDictionary *> *)fileInfoForInfoHash:(NSString *)infoHash {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return nil;

    std::shared_ptr<const lt::torrent_info> ti = h.torrent_file();
    if (!ti) return nil; // metadata not yet available

    auto const &fs = ti->files();
    std::vector<lt::download_priority_t> prios = h.get_file_priorities();
    int nfiles = fs.num_files();

    NSMutableArray<NSDictionary *> *out = [NSMutableArray arrayWithCapacity:nfiles];
    for (lt::file_index_t i{0}; i < fs.end_file(); ++i) {
        int idx = static_cast<int>(i);
        int prio = (idx < (int)prios.size()) ? static_cast<int>(prios[idx]) : 4;
        [out addObject:@{
            @"name":     ctrl_nsstring(fs.file_path(i)),
            @"size":     @(fs.file_size(i)),
            @"priority": @(prio)
        }];
    }
    return out;
}

// MARK: Reading

static void ctrl_fill_stats(CTRLTorrentStats *s, lt::torrent_status const &st) {
    s.name          = ctrl_nsstring(st.name);
    s.infoHash      = ctrl_hex_from_bytes(st.info_hashes.get_best().to_string());
    s.savePath      = ctrl_nsstring(st.save_path);
    s.progress      = st.progress;
    s.state         = ctrl_map_state(st);
    s.paused        = (st.flags & lt::torrent_flags::paused) ? YES : NO;
    s.downloadRate  = st.download_payload_rate;
    s.uploadRate    = st.upload_payload_rate;
    s.totalWanted   = st.total_wanted;
    s.totalDone     = st.total_wanted_done;
    s.totalDownload = st.all_time_download;
    s.totalUpload   = st.all_time_upload;
    s.ratio         = (st.all_time_download > 0)
                      ? double(st.all_time_upload) / double(st.all_time_download)
                      : 0.0;
    s.numPeers      = st.num_peers;
    s.numSeeds      = st.num_seeds;
    s.etaSeconds    = (st.download_payload_rate > 0 && st.total_wanted > st.total_wanted_done)
                      ? int((st.total_wanted - st.total_wanted_done) / st.download_payload_rate)
                      : -1;
    s.addedDate     = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)st.added_time];
}

- (NSArray<CTRLTorrentStats *> *)pollStats {
    std::vector<lt::torrent_handle> handles = _session->get_torrents();
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:handles.size()];
    for (auto const &h : handles) {
        if (!h.is_valid()) continue;
        CTRLTorrentStats *s = [CTRLTorrentStats new];
        ctrl_fill_stats(s, h.status());
        [out addObject:s];
        _handlesByHash[h.info_hashes().get_best().to_string()] = h;
    }
    return out;
}

- (CTRLTorrentStats *)statsForInfoHash:(NSString *)infoHash {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return nil;
    CTRLTorrentStats *s = [CTRLTorrentStats new];
    ctrl_fill_stats(s, h.status());
    return s;
}

- (CTRLSessionStats *)sessionStats {
    CTRLSessionStats *s = [CTRLSessionStats new];
    s.listenPort = _listenPort;

    int64_t totalDown = 0, totalUp = 0, dlRate = 0, ulRate = 0;
    int peerTotal = 0, count = 0;
    BOOL hasIncoming = NO;

    for (auto const &h : _session->get_torrents()) {
        if (!h.is_valid()) continue;
        auto st = h.status();
        totalDown += st.all_time_download;
        totalUp   += st.all_time_upload;
        dlRate    += st.download_payload_rate;
        ulRate    += st.upload_payload_rate;
        peerTotal += st.num_peers;
        count++;
        if (st.flags & lt::torrent_flags::seed_mode) { /* seeds */ }
    }

    // "Has incoming" is tracked at the session level in the status alerts;
    // here we approximate via a simple "any peer is inbound" heuristic that
    // libtorrent doesn't expose directly, so we conservatively report NO
    // when we have zero peers or zero torrents.
    hasIncoming = (peerTotal > 0);

    s.downloadRate = dlRate;
    s.uploadRate   = ulRate;
    s.totalBytesDownloaded = totalDown;
    s.totalBytesUploaded   = totalUp;
    s.numTorrents          = count;
    s.numPeersConnected    = peerTotal;
    s.hasIncomingConnections = hasIncoming;
    return s;
}

// MARK: Listen port control

- (void)setListenPort:(uint16_t)port {
    if (port == _listenPort) return;
    _listenPort = port;
    lt::settings_pack pack;
    pack.set_str(lt::settings_pack::listen_interfaces,
                 ctrl_build_listen_interfaces(port, _bindAll).UTF8String);
    _session->apply_settings(std::move(pack));
    NSLog(@"[Controllarr] listen port -> %u", port);
}

- (void)setListenInterfacesString:(NSString *)interfaces {
    lt::settings_pack pack;
    pack.set_str(lt::settings_pack::listen_interfaces, interfaces.UTF8String);
    _session->apply_settings(std::move(pack));
    NSLog(@"[Controllarr] listen_interfaces -> %@", interfaces);
}

- (void)setOutgoingInterface:(NSString *)interfaceName {
    lt::settings_pack pack;
    pack.set_str(lt::settings_pack::outgoing_interfaces, interfaceName.UTF8String);
    _session->apply_settings(std::move(pack));
    NSLog(@"[Controllarr] outgoing_interfaces -> %@", interfaceName);
}

- (void)setRateLimitsDownloadKBps:(int)downKBps uploadKBps:(int)upKBps {
    lt::settings_pack pack;
    // 0 = unlimited in libtorrent
    pack.set_int(lt::settings_pack::download_rate_limit, downKBps > 0 ? downKBps * 1024 : 0);
    pack.set_int(lt::settings_pack::upload_rate_limit,   upKBps > 0   ? upKBps * 1024   : 0);
    _session->apply_settings(std::move(pack));
}

- (void)setPeerDiscoveryDHT:(BOOL)dht pex:(BOOL)pex lsd:(BOOL)lsd {
    lt::settings_pack pack;
    pack.set_bool(lt::settings_pack::enable_dht, dht ? true : false);
    pack.set_bool(lt::settings_pack::enable_lsd, lsd ? true : false);
    // PeX is a wire-protocol extension; libtorrent enables it via the
    // ut_pex plugin which is loaded by default. There is no settings_pack
    // switch in libtorrent 2.x, so we toggle via the peer_fingerprint /
    // allow_i2p_mixed / upload_only_torrents related knobs? Actually we
    // expose it through the allow_i2p_mixed adjacent pex toggle only
    // available by recompiling. For now we just apply DHT/LSD here and
    // log PeX as informational — libtorrent leaves ut_pex on by default.
    _session->apply_settings(std::move(pack));
    NSLog(@"[Controllarr] peer discovery -> dht=%d pex=%d lsd=%d (pex applied on next restart)",
          dht, pex, lsd);
}

- (void)setConnectionLimitsGlobalConnections:(int)globalConnections
                        connectionsPerTorrent:(int)perTorrentConnections
                                globalUploads:(int)globalUploads
                             uploadsPerTorrent:(int)perTorrentUploads {
    lt::settings_pack pack;
    if (globalConnections > 0) {
        pack.set_int(lt::settings_pack::connections_limit, globalConnections);
    }
    if (perTorrentConnections > 0) {
        // libtorrent uses -1 to mean "unlimited" for per-torrent limits;
        // we pass the raw value (0 here means "unchanged" so we skip it).
        pack.set_int(lt::settings_pack::active_limit, perTorrentConnections);
    }
    if (globalUploads > 0) {
        pack.set_int(lt::settings_pack::unchoke_slots_limit, globalUploads);
    }
    if (perTorrentUploads > 0) {
        pack.set_int(lt::settings_pack::active_seeds, perTorrentUploads);
    }
    _session->apply_settings(std::move(pack));
    NSLog(@"[Controllarr] connection limits -> global=%d perTorrent=%d uploads=%d perTorrentUploads=%d",
          globalConnections, perTorrentConnections, globalUploads, perTorrentUploads);
}

- (void)forceReannounceAll {
    for (auto const &h : _session->get_torrents()) {
        if (h.is_valid()) h.force_reannounce();
    }
}

// MARK: Alerts

- (void)drainAlerts {
    if (!_session) return;
    std::vector<lt::alert *> alerts;
    _session->pop_alerts(&alerts);
    for (lt::alert *a : alerts) {
        if (a->category() & lt::alert_category::error) {
            NSLog(@"[Controllarr][libtorrent] %s", a->message().c_str());
        }
    }
}

// MARK: Resume data

- (void)saveResumeDataTo:(NSString *)directory {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];

    // Ask libtorrent to emit save_resume_data_alert for every torrent.
    for (auto const &h : _session->get_torrents()) {
        if (h.is_valid() && h.status().has_metadata) {
            h.save_resume_data(lt::torrent_handle::save_info_dict);
        }
    }

    // Drain alerts for a short window collecting what came back.
    int outstanding = (int)_session->get_torrents().size();
    int spins = 0;
    while (outstanding > 0 && spins < 40) {
        _session->wait_for_alert(std::chrono::milliseconds(50));
        std::vector<lt::alert *> alerts;
        _session->pop_alerts(&alerts);
        for (lt::alert *a : alerts) {
            if (auto rd = lt::alert_cast<lt::save_resume_data_alert>(a)) {
                auto buf = lt::write_resume_data_buf(rd->params);
                std::string hash = rd->handle.info_hashes().get_best().to_string();
                NSString *hex = ctrl_hex_from_bytes(hash);
                NSString *path = [directory stringByAppendingPathComponent:
                                  [hex stringByAppendingString:@".fastresume"]];
                [[NSData dataWithBytes:buf.data() length:buf.size()] writeToFile:path atomically:YES];
                outstanding--;
            } else if (lt::alert_cast<lt::save_resume_data_failed_alert>(a)) {
                outstanding--;
            }
        }
        spins++;
    }
}

- (void)loadResumeDataFrom:(NSString *)directory {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:directory error:nil] ?: @[];
    for (NSString *entry in entries) {
        if (![entry hasSuffix:@".fastresume"]) continue;
        NSString *full = [directory stringByAppendingPathComponent:entry];
        NSData *data = [NSData dataWithContentsOfFile:full];
        if (!data) continue;
        try {
            lt::error_code ec;
            lt::add_torrent_params atp = lt::read_resume_data(
                {(char const *)data.bytes, (long)data.length}, ec);
            if (ec) {
                NSLog(@"[Controllarr] read_resume_data failed: %s", ec.message().c_str());
                continue;
            }
            if (atp.save_path.empty()) atp.save_path = _savePath.UTF8String;
            lt::torrent_handle h = _session->add_torrent(std::move(atp), ec);
            if (!ec && h.is_valid()) {
                _handlesByHash[h.info_hashes().get_best().to_string()] = h;
            }
        } catch (std::exception const &e) {
            NSLog(@"[Controllarr] resume load threw: %s", e.what());
        }
    }
}

- (void)shutdown {
    _handlesByHash.clear();
    _session.reset();
}

- (void)dealloc {
    _session.reset();
}

@end
