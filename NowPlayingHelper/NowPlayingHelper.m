#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef void (*GetInfoFunction)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetIsPlayingFunction)(dispatch_queue_t, void (^)(Boolean));
typedef Boolean (*SendCommandFunction)(int, NSDictionary *);

static void *mediaRemoteSymbol(const char *name) {
    static void *handle;
    if (!handle) handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    return handle ? dlsym(handle, name) : NULL;
}

static void emit(NSDictionary *object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil] ?: [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    fwrite(data.bytes, 1, data.length, stdout);
    fflush(stdout);
}

static NSString *argument(void) {
    const char *value = getenv("NP_ARG");
    return value ? @(value) : @"";
}

static double currentElapsed(NSDictionary *info, BOOL playing) {
    double elapsed = [info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] doubleValue];
    NSDate *timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    if (!playing || ![timestamp isKindOfClass:NSDate.class]) return elapsed;
    NSNumber *rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
    return elapsed - timestamp.timeIntervalSinceNow * (rate ? rate.doubleValue : 1);
}

void np_info(void) {
    GetInfoFunction getInfo = mediaRemoteSymbol("MRMediaRemoteGetNowPlayingInfo");
    GetIsPlayingFunction getIsPlaying = mediaRemoteSymbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    if (!getInfo || !getIsPlaying) return emit(@{});

    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    dispatch_group_t group = dispatch_group_create();
    __block NSDictionary *info = nil;
    __block BOOL playing = NO;
    dispatch_group_enter(group);
    getIsPlaying(queue, ^(Boolean value) {
        playing = value;
        dispatch_group_leave(group);
    });
    dispatch_group_enter(group);
    getInfo(queue, ^(NSDictionary *value) {
        info = value;
        dispatch_group_leave(group);
    });
    if (dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) != 0) return emit(@{});

    NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
    if (![title isKindOfClass:NSString.class] || title.length == 0) return emit(@{});

    NSMutableDictionary *payload = [@{ @"title": title, @"playing": @(playing) } mutableCopy];
    NSDictionary *textKeys = @{ @"artist": @"kMRMediaRemoteNowPlayingInfoArtist", @"album": @"kMRMediaRemoteNowPlayingInfoAlbum" };
    for (NSString *key in textKeys) {
        NSString *value = info[textKeys[key]];
        if ([value isKindOfClass:NSString.class] && value.length > 0) payload[key] = value;
    }
    NSNumber *duration = info[@"kMRMediaRemoteNowPlayingInfoDuration"];
    if ([duration isKindOfClass:NSNumber.class]) {
        payload[@"duration"] = duration;
        payload[@"elapsed"] = @(MAX(0, MIN(currentElapsed(info, playing), duration.doubleValue)));
    }
    NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    if ([artwork isKindOfClass:NSData.class] && artwork.length > 0) {
        NSString *identifier = info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"];
        payload[@"artworkId"] = [identifier isKindOfClass:NSString.class]
            ? identifier
            : [NSString stringWithFormat:@"%@|%@|%lu", title, payload[@"album"] ?: @"", (unsigned long)artwork.length];
        payload[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
    }
    emit(payload);
}

void np_command(void) {
    SendCommandFunction send = mediaRemoteSymbol("MRMediaRemoteSendCommand");
    emit(@{ @"ok": @(send != NULL && send(argument().intValue, nil)) });
}

void np_seek(void) {
    SendCommandFunction send = mediaRemoteSymbol("MRMediaRemoteSendCommand");
    NSDictionary *options = @{ @"kMRMediaRemoteOptionPlaybackPosition": @(argument().doubleValue) };
    emit(@{ @"ok": @(send != NULL && send(24, options)) });
}
