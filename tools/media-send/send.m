// One MediaRemote command to macOS's Now Playing app, for the music popup's buttons and keys. Loaded into
// /usr/bin/perl like tools/media-reader (only Apple-signed processes may talk to MediaRemote); MusicSource passes
// the command in MR_CMD: 0 play, 1 pause, 2 toggle, 4 next, 5 previous. macOS takes it only for the Now Playing app.
#import <Foundation/Foundation.h>
#import <dlfcn.h>

__attribute__((constructor)) static void start(void) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    Boolean (*send)(int, id) = mr ? dlsym(mr, "MRMediaRemoteSendCommand") : NULL;
    if (!send) { fprintf(stderr, "no MRMediaRemoteSendCommand\n"); exit(2); }
    const char *c = getenv("MR_CMD");
    if (!send(c ? atoi(c) : 2, nil)) { fprintf(stderr, "MediaRemote refused the command\n"); exit(3); }
    // The command goes out asynchronously; a moment on the run loop lets it leave before the process ends.
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    exit(0);
}
