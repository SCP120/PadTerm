#import "PTSessionLister.h"
#import "PTProfileStore.h"
#include "pt_error.h"
#include "pt_session.h"
#include "pt_ssh.h"
#include <unistd.h>

/* AC-SESSION-4: a changed name shows within this time. One read costs about 26 ms on the Mac mini (2 sessions,
 * measured 2026-11-04), so this is under 0.2% of one core while a list is on screen. */
enum { PT_LIST_INTERVAL_S = 15 };
/* The same bound as a terminal connection (PT_CONNECT_TIMEOUT_MS). */
enum { PT_LIST_TIMEOUT_MS = 15000 };
/* 50 rows x 4 KiB: a title record is far below 1 KiB in every transcript on the owner's Mac. */
enum { PT_LIST_MAX_BYTES = 200 * 1024 };

@implementation PTSessionLister {
    PTProfile *_profile;
    NSData *_key;
    __weak id<PTSessionListerDelegate> _delegate;
    dispatch_queue_t _q;
    int _cancel[2];
    pt_ssh *_ssh;           /* queue only */
    NSUInteger _generation; /* queue only: a tick of an older generation is dropped */
    volatile BOOL _stopped;
    NSInteger _pendingRemoves; /* main thread only */
}

- (instancetype)initWithProfile:(PTProfile *)profile delegate:(id<PTSessionListerDelegate>)delegate {
    if ((self = [super init])) {
        _profile = [PTProfile fromDictionary:[profile dictionary]]; /* the queue reads it while the main thread can edit the original */
        _key = [[PTProfileStore shared] keyForProfile:profile];
        _delegate = delegate;
        _q = dispatch_queue_create("padterm.sessions", DISPATCH_QUEUE_SERIAL);
        if (pipe(_cancel) != 0) { _cancel[0] = _cancel[1] = -1; }
    }
    return self;
}

- (void)dealloc {
    if (_cancel[0] >= 0) { close(_cancel[0]); close(_cancel[1]); }
}

- (void)start { [self refreshNow]; }

- (void)refreshNow {
    dispatch_async(_q, ^{
        self->_generation++;
        [self tick:self->_generation];
    });
}

- (void)reconnectNow {
    dispatch_async(_q, ^{
        [self closeSSH];
        self->_generation++;
        [self tick:self->_generation];
    });
}

- (void)stop {
    _stopped = YES;
    /* A running SSH step ends at once, unless a Delete still has to reach the server. */
    if (_pendingRemoves == 0 && _cancel[1] >= 0) { char c = 1; (void)!write(_cancel[1], &c, 1); }
    dispatch_async(_q, ^{ [self closeSSH]; });
}

- (void)closeSSH {
    pt_ssh_close(_ssh);
    _ssh = NULL;
}

- (void)report:(NSArray *)sessions failure:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        id<PTSessionListerDelegate> d = self->_delegate;
        if (self->_stopped || !d) return;
        if (sessions) [d lister:self didGetSessions:sessions];
        else [d lister:self didFail:message];
    });
}

/* NULL if the connection is ready, else the reason. */
- (NSString *)ensureConnection {
    if (_ssh) return nil;
    if (!_key) return @"This server has no private key.";
    if (!_profile.pinnedFingerprint.length) return @"Open a session once to trust this server. The list then shows here.";
    pt_ssh *s = NULL;
    int st = pt_ssh_connect(_profile.host.UTF8String, (int)_profile.port, PT_LIST_TIMEOUT_MS, _cancel[0], &s);
    if (st != PT_OK) return [NSString stringWithFormat:@"Cannot reach the server: %s.", pt_status_text(st)];
    char fp[128];
    st = pt_ssh_host_fingerprint(s, fp, sizeof fp);
    if (st != PT_OK || strcmp(fp, _profile.pinnedFingerprint.UTF8String) != 0) { /* BR-CONNECT-2: no login before this */
        pt_ssh_close(s);
        return @"The server's host key does not match.";
    }
    st = pt_ssh_auth_key(s, _profile.user.UTF8String, _key.bytes, _key.length);
    if (st != PT_OK) {
        pt_ssh_close(s);
        return [NSString stringWithFormat:@"Login failed: %s.", pt_status_text(st)];
    }
    _ssh = s;
    return nil;
}

- (void)tick:(NSUInteger)generation {
    if (_stopped || generation != _generation) return;
    NSString *failure = [self ensureConnection];
    if (!failure) {
        char cmd[16384];
        int n = pt_session_list_command(cmd, sizeof cmd);
        NSMutableData *out = [NSMutableData dataWithLength:PT_LIST_MAX_BYTES];
        size_t len = 0;
        int st = n < 0 ? n : pt_ssh_exec_capture(_ssh, cmd, out.mutableBytes, out.length, &len);
        if (st == PT_OK) {
            out.length = len;
            [self report:[PTSession sessionsFromListing:out] failure:nil];
        } else {
            [self closeSSH]; /* the next tick connects again */
            failure = [NSString stringWithFormat:@"The list stopped: %s.", pt_status_text(st)];
        }
    }
    if (failure) [self report:nil failure:failure];
    if (_stopped) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, PT_LIST_INTERVAL_S * NSEC_PER_SEC), _q, ^{ [self tick:generation]; });
}

- (void)removeSession:(PTSession *)session {
    NSString *key = session.key;
    _pendingRemoves++;
    dispatch_async(_q, ^{
        NSString *failure = [self ensureConnection];
        if (!failure) {
            char cmd[2048], out[256];
            size_t len;
            int n = pt_session_remove_command(key.UTF8String, cmd, sizeof cmd);
            int st = n < 0 ? n : pt_ssh_exec_capture(self->_ssh, cmd, out, sizeof out, &len);
            if (st != PT_OK) {
                [self closeSSH];
                failure = [NSString stringWithFormat:@"Could not remove the session: %s.", pt_status_text(st)];
            }
        }
        if (failure) [self report:nil failure:failure];
        dispatch_async(dispatch_get_main_queue(), ^{ self->_pendingRemoves--; });
        if (self->_stopped) [self closeSSH];
        else [self refreshNow];
    });
}
@end
