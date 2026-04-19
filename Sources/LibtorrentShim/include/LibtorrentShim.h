//
//  LibtorrentShim.h
//  Controllarr — Phase 1
//
//  Obj-C surface over libtorrent-rasterbar. Swift imports this header via
//  the generated module map; the `.mm` implementation is the only place in
//  the entire project that sees <libtorrent/*>.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CTRLTorrentState) {
    CTRLTorrentStateUnknown             = 0,
    CTRLTorrentStateCheckingFiles       = 1,
    CTRLTorrentStateDownloadingMetadata = 2,
    CTRLTorrentStateDownloading         = 3,
    CTRLTorrentStateFinished            = 4,
    CTRLTorrentStateSeeding             = 5,
    CTRLTorrentStateCheckingResume      = 6,
    CTRLTorrentStatePaused              = 7,
};

/// Point-in-time snapshot of one torrent. All fields are immutable after
/// `-[CTRLSession pollStats]` returns.
@interface CTRLTorrentStats : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *infoHash;
@property (nonatomic, readonly, copy) NSString *savePath;
@property (nonatomic, readonly)       float      progress;      // 0.0 – 1.0
@property (nonatomic, readonly)       CTRLTorrentState state;
@property (nonatomic, readonly)       BOOL       paused;
@property (nonatomic, readonly)       int64_t    downloadRate;  // bytes/sec
@property (nonatomic, readonly)       int64_t    uploadRate;    // bytes/sec
@property (nonatomic, readonly)       int64_t    totalWanted;
@property (nonatomic, readonly)       int64_t    totalDone;
@property (nonatomic, readonly)       int64_t    totalDownload; // session total
@property (nonatomic, readonly)       int64_t    totalUpload;
@property (nonatomic, readonly)       double     ratio;
@property (nonatomic, readonly)       int        numPeers;
@property (nonatomic, readonly)       int        numSeeds;
@property (nonatomic, readonly)       int        etaSeconds;     // -1 if unknown
@property (nonatomic, readonly)       NSDate    *addedDate;
@end

/// Coarse session-wide counters for the port watcher + web UI dashboard.
@interface CTRLSessionStats : NSObject
@property (nonatomic, readonly) int64_t downloadRate;        // bytes/sec
@property (nonatomic, readonly) int64_t uploadRate;          // bytes/sec
@property (nonatomic, readonly) int64_t totalBytesDownloaded;
@property (nonatomic, readonly) int64_t totalBytesUploaded;
@property (nonatomic, readonly) int     numTorrents;
@property (nonatomic, readonly) int     numPeersConnected;
@property (nonatomic, readonly) BOOL    hasIncomingConnections;
@property (nonatomic, readonly) uint16_t listenPort;
@end

/// Point-in-time snapshot of one tracker endpoint.
@interface CTRLTrackerInfo : NSObject
@property (nonatomic, readonly, copy) NSString *url;
@property (nonatomic, readonly) int tier;
@property (nonatomic, readonly) int numPeers;      // peers tracker claims it has
@property (nonatomic, readonly) int numSeeds;
@property (nonatomic, readonly) int numLeechers;
@property (nonatomic, readonly) int numDownloaded;  // times tracker says the torrent was fully downloaded
@property (nonatomic, readonly, copy) NSString *message;  // last tracker response message
@property (nonatomic, readonly) NSInteger status;  // 0=disabled, 1=not_contacted, 2=working, 3=updating, 4=error
@end

/// Point-in-time snapshot of one connected peer.
@interface CTRLPeerInfo : NSObject
@property (nonatomic, readonly, copy) NSString *ip;
@property (nonatomic, readonly) int port;
@property (nonatomic, readonly, copy) NSString *client;
@property (nonatomic, readonly) float progress;
@property (nonatomic, readonly) int64_t downloadRate;  // speed we're downloading from this peer
@property (nonatomic, readonly) int64_t uploadRate;    // speed we're uploading to this peer
@property (nonatomic, readonly) int64_t totalDownload;
@property (nonatomic, readonly) int64_t totalUpload;
@property (nonatomic, readonly, copy) NSString *flags;    // connection flags string
@property (nonatomic, readonly, copy) NSString *country;  // 2-letter country code if available
@end

/// Owning handle on a single libtorrent session. One per process.
@interface CTRLSession : NSObject

/// Bring up a session listening on `port`, saving new torrents under
/// `savePath`. `savePath` must already exist on disk.
/// `bindAllInterfaces` = NO restricts listen binding to 0.0.0.0 + [::] only,
/// skipping link-local / tunnel / bridge interfaces (strongly recommended;
/// the Phase 0 default bound to all interfaces and generated a lot of noise).
- (instancetype)initWithSavePath:(NSString *)savePath
                      listenPort:(uint16_t)port
               bindAllInterfaces:(BOOL)bindAllInterfaces NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

// MARK: Adding torrents

- (BOOL)addMagnet:(NSString *)magnetURI
         savePath:(nullable NSString *)savePath
            error:(NSError * _Nullable *)error;

- (BOOL)addTorrentFile:(NSString *)path
              savePath:(nullable NSString *)savePath
                 error:(NSError * _Nullable *)error;

/// Inspect a magnet URI WITHOUT adding it. Returns the lowercase-hex info
/// hash on success, nil if the URI is malformed.
- (nullable NSString *)infoHashForMagnet:(NSString *)magnetURI;

/// Inspect a .torrent file WITHOUT adding it. Returns the lowercase-hex
/// info hash on success, nil if the file is unreadable / malformed.
- (nullable NSString *)infoHashForTorrentFile:(NSString *)path;

/// Return the list of tracker URLs embedded in a magnet URI (the `&tr=`
/// parameters). Does not add the torrent.
- (NSArray<NSString *> *)trackersInMagnet:(NSString *)magnetURI;

/// Return the list of tracker URLs embedded in a .torrent file.
- (NSArray<NSString *> *)trackersInTorrentFile:(NSString *)path;

/// True if the session already has a torrent with this info hash.
- (BOOL)hasTorrent:(NSString *)infoHash;

/// Merge additional tracker URLs into an existing torrent (used by the
/// duplicate-add "merge trackers" policy). Duplicate URLs are ignored by
/// libtorrent. Returns the count of trackers that were new.
- (NSInteger)addTrackersToTorrent:(NSString *)infoHash
                         trackers:(NSArray<NSString *> *)trackers;

// MARK: Mutating torrents

/// Pause a torrent by info hash (hex, lowercase). Returns NO if not found.
- (BOOL)pauseTorrent:(NSString *)infoHash;
/// Resume a torrent into the auto-managed pool. If libtorrent queueing is
/// enabled, the torrent participates in the queue (libtorrent will promote
/// it to running when an active slot opens up).
- (BOOL)resumeTorrent:(NSString *)infoHash;
/// "Force Download" / "Force Resume" — resume a torrent and remove it from
/// the auto-managed pool so the queue system can never silently re-pause it.
/// Use when the user explicitly wants this torrent to run regardless of
/// queue caps.
- (BOOL)forceResumeTorrent:(NSString *)infoHash;

/// Remove a torrent by info hash. If `deleteFiles` is YES, the on-disk
/// files are removed too. Returns NO if not found.
- (BOOL)removeTorrent:(NSString *)infoHash deleteFiles:(BOOL)deleteFiles;

/// Move the save path of a torrent (the 'move' variant copies + deletes;
/// 'rename' variant just updates the stored path without moving files).
- (BOOL)moveTorrent:(NSString *)infoHash toPath:(NSString *)path;

// MARK: Reading state

- (NSArray<CTRLTorrentStats *> *)pollStats;
- (nullable CTRLTorrentStats *)statsForInfoHash:(NSString *)infoHash;
- (CTRLSessionStats *)sessionStats;

/// Return the file list of a torrent, one entry per file, as a path
/// relative to the torrent save path. Returns nil if the torrent's
/// metadata is not yet available (magnet link still fetching) or if
/// the info hash is unknown.
- (nullable NSArray<NSString *> *)fileNamesForInfoHash:(NSString *)infoHash;

/// Apply per-file download priorities. `priorities` must be one entry
/// per file, in the same order as -fileNamesForInfoHash:. Values follow
/// libtorrent's convention — 0 = don't download, 1 = normal, 4 = normal,
/// 7 = highest. Returns NO if the torrent is unknown or still has no
/// metadata.
- (BOOL)setFilePriorities:(NSArray<NSNumber *> *)priorities
              forInfoHash:(NSString *)infoHash;

/// Ask the tracker swarm for an immediate re-announce on one torrent.
/// Used by the health watcher when flagging a stall.
- (BOOL)reannounceTorrent:(NSString *)infoHash;

/// Force a full piece-hash verification of a torrent's files on disk.
/// Equivalent to qBittorrent's "Force Recheck". Useful after moving
/// files manually or recovering partial downloads from another client.
- (BOOL)forceRecheckTorrent:(NSString *)infoHash;

/// Reconstruct a magnet: URI for an already-running torrent. Returns
/// nil if metadata isn't yet available (which can happen for magnet
/// torrents whose DHT/peer metadata fetch hasn't completed).
- (nullable NSString *)makeMagnetForTorrent:(NSString *)infoHash;

/// Return the list of trackers for a torrent. Returns nil if unknown.
- (nullable NSArray<CTRLTrackerInfo *> *)trackersForInfoHash:(NSString *)infoHash;

/// Return the list of currently connected peers for a torrent. Returns nil if unknown.
- (nullable NSArray<CTRLPeerInfo *> *)peersForInfoHash:(NSString *)infoHash;

/// Returns per-file info: array of dictionaries with keys "name" (NSString), "size" (NSNumber/int64), "priority" (NSNumber/int)
- (nullable NSArray<NSDictionary *> *)fileInfoForInfoHash:(NSString *)infoHash;

// MARK: Listen port control (the #1 feature)

/// Change the listen port at runtime. Updates libtorrent's
/// listen_interfaces setting and re-binds. Safe to call repeatedly.
- (void)setListenPort:(uint16_t)port;

/// Directly set libtorrent's `listen_interfaces` string.
/// Use this to bind to a specific network interface, e.g.
/// `@"10.0.0.1:6881"` to listen only on a VPN adapter.
- (void)setListenInterfacesString:(NSString *)interfaces;

/// Set the `outgoing_interfaces` setting so libtorrent sends all
/// peer and tracker traffic through a specific network interface.
/// Pass an interface name like `@"utun4"` or an IP like `@"10.0.0.1"`.
/// Pass empty string to unbind (revert to OS default routing).
- (void)setOutgoingInterface:(NSString *)interfaceName;

/// Set global download/upload rate limits in KiB/s. 0 = unlimited.
- (void)setRateLimitsDownloadKBps:(int)downKBps uploadKBps:(int)upKBps;

/// Toggle the DHT / PeX / LSD peer-discovery mechanisms at runtime.
/// PeX is controlled by loading (or not loading) the ut_pex extension,
/// which libtorrent enables by default when the session is constructed;
/// runtime toggling applies on next session restart for PeX. DHT and LSD
/// apply immediately via settings_pack.
- (void)setPeerDiscoveryDHT:(BOOL)dht pex:(BOOL)pex lsd:(BOOL)lsd;

/// Connection-count ceilings. Pass 0 to leave libtorrent's default in place.
- (void)setConnectionLimitsGlobalConnections:(int)globalConnections
                        connectionsPerTorrent:(int)perTorrentConnections
                                globalUploads:(int)globalUploads
                             uploadsPerTorrent:(int)perTorrentUploads;

/// Turn libtorrent's built-in torrent queueing on or off. When enabled,
/// auto-managed torrents beyond the active caps get queued (paused
/// automatically); libtorrent promotes the next queued one whenever a
/// running torrent finishes/pauses/is removed. When disabled (default),
/// all active caps are raised to 10,000 so queueing never triggers.
/// Passing 0 for any cap falls back to the qBittorrent-like default
/// (3 / 5 / 15).
- (void)setQueueingEnabled:(BOOL)enabled
           activeDownloads:(int)activeDownloads
               activeSeeds:(int)activeSeeds
               activeLimit:(int)activeLimit;

/// Force a re-announce to all trackers on all torrents.
- (void)forceReannounceAll;

// MARK: Alerts

/// Drain the libtorrent alert queue, NSLog'ing any error-category messages.
/// Phase 1 still keeps this simple — Phase 2 will route alerts into a
/// structured log viewer.
- (void)drainAlerts;

// MARK: Lifecycle

/// Tell the session where to write per-torrent recovery metadata
/// (`<infohash>.magnet`, `<infohash>.torrent`, `<infohash>.path`).
/// These sidecars are written synchronously at add-time and used as a
/// fallback on restart when a `.fastresume` is missing or unreadable
/// (e.g. force-quit before libtorrent could emit resume data).
- (void)setMetadataDirectory:(NSString *)directory;

/// Ask libtorrent to serialize resume data for every torrent and write it
/// under `directory` as `<infohash>.fastresume`. Safe to call periodically.
- (void)saveResumeDataTo:(NSString *)directory;

/// Load any `<infohash>.fastresume` files found under `directory` and
/// re-add the torrents. Then scan the metadata directory for `.magnet`
/// and `.torrent` sidecars and re-add any torrent whose info hash did
/// not come back via fastresume. Counterpart to -saveResumeDataTo:.
- (void)loadResumeDataFrom:(NSString *)directory;

- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
