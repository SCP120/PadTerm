#import <Foundation/Foundation.h>
#include "pt_launch.h"

/* One Claude or Codex session on a server (UC-SESSION). The server holds the record; this is a copy for the screen. */
@interface PTSession : NSObject
@property (nonatomic, copy) NSString *key;       /* UUID; tmux session pc-<key> */
@property (nonatomic, assign) pt_agent agent;    /* PT_AGENT_CLAUDE or PT_AGENT_CODEX */
@property (nonatomic, copy) NSString *title;     /* the agent's name for it; nil until the agent gives one */
@property (nonatomic, copy) NSString *directory; /* on the server */
@property (nonatomic, strong) NSDate *lastActive;
@property (nonatomic, assign) BOOL running;      /* tmux still runs it */

+ (PTSession *)newSessionWithAgent:(pt_agent)agent directory:(NSString *)directory;
/* Output of pt_session_list_command, newest activity first. Rows with a bad key or agent are dropped (BR-SESSION-3). */
+ (NSArray *)sessionsFromListing:(NSData *)listing;
/* "just now", "5 min ago", "3 hr ago", "yesterday", "4 days ago", then the date. */
+ (NSString *)ageOfDate:(NSDate *)date now:(NSDate *)now;
- (BOOL)sameRowAs:(PTSession *)other; /* what a list row shows is the same */
- (NSString *)displayTitle; /* the title, or "New session" */
- (NSString *)agentName;    /* "Claude" or "Codex" */
@end
