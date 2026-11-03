// What plays, for the music pill: macOS's Now Playing plus every other app with a media session.
// Since macOS 15.4 only Apple-signed processes may read MediaRemote, so MusicSource loads this into /usr/bin/perl
// (`require DynaLoader; DynaLoader::dl_load_file(<this>, 0)`), the way mediaremote-adapter does. The constructor never
// returns: once a second it prints a JSON line when anything changed, in the shape `nowPlayingLine` reads, with
// "others" for the apps that are not Now Playing. macOS steers only the Now Playing app (sending to another needs
// com.apple.mediaremote.send-commands, Control Center's), so the others can only be gone to (checked on 27.0.1).
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <unistd.h>

typedef void (^ArrayBlock)(NSArray *);
typedef void (^InfoBlock)(id);
static void (*getClients)(dispatch_queue_t, ArrayBlock);
static Class Request, PlayerPath, Player;
static dispatch_queue_t queue;

static NSString *const K = @"kMRMediaRemoteNowPlayingInfo";
static id value(NSDictionary *info, NSString *key) { return info[[K stringByAppendingString:key]]; }

static NSString *appOf(id client) {
    NSString *parent = [client valueForKey:@"parentApplicationBundleIdentifier"];
    return parent.length ? parent : ([client valueForKey:@"bundleIdentifier"] ?: @"");
}

static NSArray *clients(void) {
    __block NSArray *found = @[];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    getClients(queue, ^(NSArray *a) { if (a) found = a; dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    return found;
}

/// One app's own now playing info, asked by its player path; nil when it does not answer in time.
static NSDictionary *infoOf(id client) {
    id origin = [[Request valueForKey:@"localNowPlayingPlayerPath"] valueForKey:@"origin"];
    id (*initPath)(id, SEL, id, id, id) = (void *)objc_msgSend;
    id path = initPath([PlayerPath alloc], NSSelectorFromString(@"initWithOrigin:client:player:"), origin, client,
                       [Player valueForKey:@"defaultPlayer"]);
    id (*initRequest)(id, SEL, id) = (void *)objc_msgSend;
    id request = initRequest([Request alloc], NSSelectorFromString(@"initWithPlayerPath:"), path);
    __block NSDictionary *info = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    void (*ask)(id, SEL, InfoBlock) = (void *)objc_msgSend;
    ask(request, NSSelectorFromString(@"requestNowPlayingInfoWithCompletion:"), ^(id i) {
        if ([i isKindOfClass:NSDictionary.class]) info = i;
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    return info;
}

static void say(NSDictionary *d) {
    NSData *json = d ? [NSJSONSerialization dataWithJSONObject:d options:0 error:nil] : [@"null" dataUsingEncoding:NSUTF8StringEncoding];
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void run(void) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    getClients = mr ? dlsym(mr, "MRMediaRemoteGetNowPlayingClients") : NULL;
    Request = NSClassFromString(@"MRNowPlayingRequest");
    PlayerPath = NSClassFromString(@"MRPlayerPath");
    Player = NSClassFromString(@"MRPlayer");
    if (!getClients || !Request || !PlayerPath || !Player) { fprintf(stderr, "MediaRemote is not what it was\n"); exit(2); }
    queue = dispatch_queue_create("gzyms.media-reader", 0);
    NSData *last = nil;
    BOOL first = YES;  // the first line always goes out, so MusicSource knows the reader works
    while (getppid() != 1) {  // Gzyms gone (killed, crashed): launchd adopts us, so do not linger.
        @autoreleasepool {
            id path = [Request valueForKey:@"localNowPlayingPlayerPath"];
            id current = [path valueForKey:@"client"];
            NSDictionary *info = [[Request valueForKey:@"localNowPlayingItem"] valueForKey:@"nowPlayingInfo"];
            NSMutableDictionary *s = nil;
            if (current && info) {
                NSDate *at = value(info, @"Timestamp");
                s = [@{ @"title": value(info, @"Title") ?: @"", @"artist": value(info, @"Artist") ?: @"",
                        @"album": value(info, @"Album") ?: @"", @"app": appOf(current),
                        @"appName": [current valueForKey:@"displayName"] ?: @"",
                        @"playing": [Request valueForKey:@"localIsPlaying"] ?: @NO,
                        @"elapsed": value(info, @"ElapsedTime") ?: @0, @"duration": value(info, @"Duration") ?: @0,
                        @"at": @((at ?: NSDate.date).timeIntervalSince1970), @"rate": value(info, @"PlaybackRate") ?: @0 } mutableCopy];
                NSMutableArray *others = [NSMutableArray array];
                pid_t currentPid = [[current valueForKey:@"processIdentifier"] intValue];
                for (id c in clients()) {
                    if ([[c valueForKey:@"processIdentifier"] intValue] == currentPid) continue;
                    NSDictionary *i = infoOf(c);
                    NSString *title = value(i, @"Title");
                    if (!title.length) continue;
                    [others addObject:@{ @"app": appOf(c), @"appName": [c valueForKey:@"displayName"] ?: @"", @"title": title,
                                         @"artist": value(i, @"Artist") ?: @"",
                                         @"playing": [value(i, @"PlaybackRate") doubleValue] > 0 ? @YES : @NO }];
                }
                s[@"others"] = others;
            }
            NSData *line = s ? [NSJSONSerialization dataWithJSONObject:s options:NSJSONWritingSortedKeys error:nil] : nil;
            if (first || (![line isEqual:last] && !(line == nil && last == nil))) {
                first = NO;
                last = line;
                say(s);
            }
        }
        sleep(1);
    }
    exit(0);
}

__attribute__((constructor)) static void start(void) { run(); }
