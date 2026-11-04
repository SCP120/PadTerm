#import <Foundation/Foundation.h>
#import "PTProfile.h"
#import "PTSession.h"

@class PTSessionLister;
/* Called on the main thread. */
@protocol PTSessionListerDelegate <NSObject>
- (void)lister:(PTSessionLister *)lister didGetSessions:(NSArray *)sessions;
- (void)lister:(PTSessionLister *)lister didFail:(NSString *)message;
@end

/* Keeps one SSH connection on a serial queue and reads the session list every 15 s, while a list is on screen.
 * Use a new object after stop. */
@interface PTSessionLister : NSObject
- (instancetype)initWithProfile:(PTProfile *)profile delegate:(id<PTSessionListerDelegate>)delegate;
- (void)start;
- (void)refreshNow;
- (void)reconnectNow; /* after a wake the socket can be dead with no error yet */
- (void)removeSession:(PTSession *)session; /* AC-SESSION-7, then a refresh */
- (void)stop;
@end
