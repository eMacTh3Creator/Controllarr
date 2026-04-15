//
//  LibtorrentShim.h
//  Controllarr — Phase 0 PoC
//
//  Small Objective-C surface that Swift imports. Everything C++ / libtorrent
//  is hidden behind this wall so the Swift side never sees <libtorrent/*>.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Simplified torrent state for the Swift side. Mirrors libtorrent's
/// state_t but reshaped to a stable Obj-C enum — we own the ABI here.
typedef NS_ENUM(NSInteger, CTRLTorrentState) {
    CTRLTorrentStateUnknown         = 0,
    CTRLTorrentStateCheckingFiles   = 1,
    CTRLTorrentStateDownloadingMetadata = 2,
    CTRLTorrentStateDownloading     = 3,
    CTRLTorrentStateFinished        = 4,
    CTRLTorrentStateSeeding         = 5,
    CTRLTorrentStateCheckingResume  = 6,
};

/// Snapshot of one torrent at the moment `pollStats` was called.
@interface CTRLTorrentStats : NSObject
@property (nonatomic, readonly, copy)   NSString *name;
@property (nonatomic, readonly, copy)   NSString *infoHash;
@property (nonatomic, readonly)         float      progress;      // 0.0 – 1.0
@property (nonatomic, readonly)         CTRLTorrentState state;
@property (nonatomic, readonly)         int64_t    downloadRate;  // bytes/sec
@property (nonatomic, readonly)         int64_t    uploadRate;    // bytes/sec
@property (nonatomic, readonly)         int64_t    totalWanted;   // bytes
@property (nonatomic, readonly)         int64_t    totalDone;     // bytes
@property (nonatomic, readonly)         int        numPeers;
@property (nonatomic, readonly)         int        numSeeds;
@end

/// Owning handle on a libtorrent session. One per process for the PoC.
@interface CTRLSession : NSObject

/// Bring up a session listening on `port`, saving new torrents under
/// `savePath`. `savePath` must exist.
- (instancetype)initWithSavePath:(NSString *)savePath
                      listenPort:(uint16_t)port NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/// Add a magnet URI. Returns NO and fills `error` on failure.
- (BOOL)addMagnet:(NSString *)magnetURI error:(NSError * _Nullable *)error;

/// Add a `.torrent` file by path.
- (BOOL)addTorrentFile:(NSString *)path error:(NSError * _Nullable *)error;

/// Snapshot every currently-known torrent. Safe to call from any thread.
- (NSArray<CTRLTorrentStats *> *)pollStats;

/// Drain the alert queue and forward any error-category alerts as NSLog
/// lines. Phase 0 just wants visibility — structured handling comes later.
- (void)drainAlerts;

/// Gracefully shut down the session.
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
