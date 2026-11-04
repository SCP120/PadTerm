#import "PTSession.h"
#include "pt_session.h"

@implementation PTSession

+ (PTSession *)newSessionWithAgent:(pt_agent)agent directory:(NSString *)directory {
    PTSession *s = [[PTSession alloc] init];
    CFUUIDRef u = CFUUIDCreate(NULL);
    s.key = [(NSString *)CFBridgingRelease(CFUUIDCreateString(NULL, u)) lowercaseString];
    CFRelease(u);
    s.agent = agent;
    s.directory = directory;
    s.lastActive = [NSDate date];
    return s;
}

/* Claude: customTitle or aiTitle. Codex: thread_name. A record is data from the server: anything else is no title. */
static NSString *titleFromRecord(NSString *json) {
    NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
    id o = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if (![o isKindOfClass:[NSDictionary class]]) return nil;
    for (NSString *k in @[@"customTitle", @"aiTitle", @"thread_name"]) {
        id v = o[k];
        if ([v isKindOfClass:[NSString class]] && [v length]) return v;
    }
    return nil;
}

+ (NSArray *)sessionsFromListing:(NSData *)listing {
    NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
    const char *bytes = listing.bytes;
    NSUInteger n = listing.length, start = 0;
    for (NSUInteger i = 0; i <= n; i++) {
        if (i < n && bytes[i] != '\n') continue;
        /* Line by line: one directory name in another encoding must not lose the whole list. */
        NSString *line = [[NSString alloc] initWithBytes:bytes + start length:i - start encoding:NSUTF8StringEncoding];
        start = i + 1;
        if (!line) continue;
        NSArray *f = [line componentsSeparatedByString:@"\t"];
        if (f.count < 2 || !pt_session_key_valid([f[1] UTF8String])) continue;
        NSString *kind = f[0], *key = f[1];
        if ([kind isEqualToString:@"S"] && f.count >= 5) {
            pt_agent a;
            if ([f[2] isEqualToString:@"claude"]) a = PT_AGENT_CLAUDE;
            else if ([f[2] isEqualToString:@"codex"]) a = PT_AGENT_CODEX;
            else continue;
            PTSession *s = [[PTSession alloc] init];
            s.key = key;
            s.agent = a;
            s.lastActive = [NSDate dateWithTimeIntervalSince1970:[f[3] doubleValue]];
            s.directory = [[f subarrayWithRange:NSMakeRange(4, f.count - 4)] componentsJoinedByString:@"\t"];
            byKey[key] = s;
        } else if ([kind isEqualToString:@"T"] && f.count >= 3) {
            PTSession *s = byKey[key];
            s.title = titleFromRecord([[f subarrayWithRange:NSMakeRange(2, f.count - 2)] componentsJoinedByString:@"\t"]);
        } else if ([kind isEqualToString:@"R"]) {
            PTSession *s = byKey[key];
            s.running = YES;
        }
    }
    return [byKey.allValues sortedArrayUsingComparator:^NSComparisonResult(PTSession *a, PTSession *b) {
        NSComparisonResult r = [b.lastActive compare:a.lastActive];
        return r != NSOrderedSame ? r : [a.key compare:b.key]; /* a stable order for equal times */
    }];
}

+ (NSString *)ageOfDate:(NSDate *)date now:(NSDate *)now {
    long s = (long)[now timeIntervalSinceDate:date];
    if (s < 60) return @"just now";
    if (s < 3600) return [NSString stringWithFormat:@"%ld min ago", s / 60];
    if (s < 86400) return [NSString stringWithFormat:@"%ld hr ago", s / 3600];
    if (s < 2 * 86400) return @"yesterday";
    if (s < 7 * 86400) return [NSString stringWithFormat:@"%ld days ago", s / 86400];
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateStyle = NSDateFormatterMediumStyle;
    f.timeStyle = NSDateFormatterNoStyle;
    return [f stringFromDate:date];
}

- (BOOL)sameRowAs:(PTSession *)o {
    return [self.key isEqualToString:o.key] && self.running == o.running && [self.displayTitle isEqualToString:o.displayTitle]
        && [self.directory isEqualToString:o.directory] && [self.lastActive isEqualToDate:o.lastActive];
}

- (NSString *)displayTitle { return self.title.length ? self.title : @"New session"; }
- (NSString *)agentName { return self.agent == PT_AGENT_CODEX ? @"Codex" : @"Claude"; }
@end
