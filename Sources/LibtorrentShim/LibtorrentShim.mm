//
//  LibtorrentShim.mm
//  Controllarr — Phase 0 PoC
//
//  Objective-C++ implementation. Includes libtorrent headers here and
//  nowhere else — the public LibtorrentShim.h stays pure Obj-C so Swift
//  can import it through the generated module map.
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
#include <libtorrent/alert_types.hpp>
#include <libtorrent/error_code.hpp>

#include <memory>
#include <string>
#include <vector>

// MARK: - CTRLTorrentStats (readwrite in the .mm, readonly in the .h)

@interface CTRLTorrentStats ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *infoHash;
@property (nonatomic, readwrite)       float     progress;
@property (nonatomic, readwrite)       CTRLTorrentState state;
@property (nonatomic, readwrite)       int64_t   downloadRate;
@property (nonatomic, readwrite)       int64_t   uploadRate;
@property (nonatomic, readwrite)       int64_t   totalWanted;
@property (nonatomic, readwrite)       int64_t   totalDone;
@property (nonatomic, readwrite)       int       numPeers;
@property (nonatomic, readwrite)       int       numSeeds;
@end

@implementation CTRLTorrentStats
@end

// MARK: - Small helpers

static CTRLTorrentState ctrl_map_state(lt::torrent_status::state_t s) {
    switch (s) {
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

static NSError *ctrl_error_from_ec(lt::error_code const &ec) {
    return [NSError errorWithDomain:@"ControllarrLibtorrent"
                               code:ec.value()
                           userInfo:@{ NSLocalizedDescriptionKey: ctrl_nsstring(ec.message()) }];
}

// MARK: - CTRLSession

@implementation CTRLSession {
    std::unique_ptr<lt::session> _session;
    NSString *_savePath;
}

- (instancetype)initWithSavePath:(NSString *)savePath listenPort:(uint16_t)port {
    if ((self = [super init])) {
        _savePath = [savePath copy];

        lt::settings_pack pack;

        NSString *listen = [NSString stringWithFormat:@"0.0.0.0:%u,[::]:%u", port, port];
        pack.set_str(lt::settings_pack::listen_interfaces, listen.UTF8String);

        pack.set_str(lt::settings_pack::user_agent, "Controllarr/0.0.1 libtorrent/2.0");

        // Alert mask — we only want things that are cheap and useful at PoC
        // time. A full session will want a lot more.
        pack.set_int(lt::settings_pack::alert_mask,
                     lt::alert_category::error
                     | lt::alert_category::status
                     | lt::alert_category::storage);

        _session = std::make_unique<lt::session>(pack);
        NSLog(@"[Controllarr] libtorrent session up on port %u, save_path=%@", port, _savePath);
    }
    return self;
}

- (BOOL)addMagnet:(NSString *)magnetURI error:(NSError **)error {
    lt::error_code ec;
    lt::add_torrent_params atp = lt::parse_magnet_uri(magnetURI.UTF8String, ec);
    if (ec) {
        if (error) *error = ctrl_error_from_ec(ec);
        return NO;
    }
    atp.save_path = _savePath.UTF8String;
    _session->async_add_torrent(std::move(atp));
    return YES;
}

- (BOOL)addTorrentFile:(NSString *)path error:(NSError **)error {
    lt::error_code ec;
    lt::add_torrent_params atp = lt::load_torrent_file(path.UTF8String);
    if (ec) {
        if (error) *error = ctrl_error_from_ec(ec);
        return NO;
    }
    atp.save_path = _savePath.UTF8String;
    _session->async_add_torrent(std::move(atp));
    return YES;
}

- (NSArray<CTRLTorrentStats *> *)pollStats {
    std::vector<lt::torrent_handle> handles = _session->get_torrents();
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:handles.size()];
    for (auto const &h : handles) {
        if (!h.is_valid()) continue;
        lt::torrent_status st = h.status();
        CTRLTorrentStats *s = [CTRLTorrentStats new];
        s.name         = ctrl_nsstring(st.name);
        s.infoHash     = ctrl_hex_from_bytes(st.info_hashes.get_best().to_string());
        s.progress     = st.progress;
        s.state        = ctrl_map_state(st.state);
        s.downloadRate = st.download_payload_rate;
        s.uploadRate   = st.upload_payload_rate;
        s.totalWanted  = st.total_wanted;
        s.totalDone    = st.total_wanted_done;
        s.numPeers     = st.num_peers;
        s.numSeeds     = st.num_seeds;
        [out addObject:s];
    }
    return out;
}

- (void)drainAlerts {
    if (!_session) return;
    std::vector<lt::alert *> alerts;
    _session->pop_alerts(&alerts);
    for (lt::alert *a : alerts) {
        if (a->category() & lt::alert_category::error) {
            NSLog(@"[Controllarr][libtorrent error] %s", a->message().c_str());
        }
    }
}

- (void)shutdown {
    _session.reset();
}

- (void)dealloc {
    _session.reset();
}

@end
