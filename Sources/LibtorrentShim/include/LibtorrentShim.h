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

// MARK: Mutating torrents

/// Pause a torrent by info hash (hex, lowercase). Returns NO if not found.
- (BOOL)pauseTorrent:(NSString *)infoHash;
- (BOOL)resumeTorrent:(NSString *)infoHash;

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

/// Set global download/upload rate limits in KiB/s. 0 = unlimited.
- (void)setRateLimitsDownloadKBps:(int)downKBps uploadKBps:(int)upKBps;

/// Force a re-announce to all trackers on all torrents.
- (void)forceReannounceAll;

// MARK: Alerts

/// Drain the libtorrent alert queue, NSLog'ing any error-category messages.
/// Phase 1 still keeps this simple — Phase 2 will route alerts into a
/// structured log viewer.
- (void)drainAlerts;

// MARK: Lifecycle

/// Ask libtorrent to serialize resume data for every torrent and write it
/// under `directory` as `<infohash>.fastresume`. Safe to call periodically.
- (void)saveResumeDataTo:(NSString *)directory;

/// Load any `<infohash>.fastresume` files found under `directory` and
/// re-add the torrents. Counterpart to -saveResumeDataTo:.
- (void)loadResumeDataFrom:(NSString *)directory;

- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
