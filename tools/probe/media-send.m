// One MediaRemote command to the Now Playing app, from inside /usr/bin/perl like reader.m. MR_CMD: 0 play, 1 pause, 2 toggle, 4 next.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
__attribute__((constructor)) static void start(void) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    Boolean (*send)(int, id) = mr ? dlsym(mr, "MRMediaRemoteSendCommand") : NULL;
    if (!send) { fprintf(stderr, "no MRMediaRemoteSendCommand\n"); exit(2); }
    const char *c = getenv("MR_CMD");
    printf("sent=%d\n", send(c ? atoi(c) : 2, nil));
    fflush(stdout);
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    exit(0);
}
