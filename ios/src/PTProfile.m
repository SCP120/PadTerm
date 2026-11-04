#import "PTProfile.h"
#include "pt_quote.h"

enum { PT_DEFAULT_SSH_PORT = 22 }; /* RFC 4253 */

static NSString *str(id v) { return [v isKindOfClass:[NSString class]] ? v : @""; }

@implementation PTProfile

+ (PTProfile *)newProfile {
    PTProfile *p = [[PTProfile alloc] init];
    CFUUIDRef u = CFUUIDCreate(NULL);
    p.uid = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, u);
    CFRelease(u);
    p.name = @""; p.host = @""; p.user = @""; p.directory = @"~"; p.pinnedFingerprint = @"";
    p.port = PT_DEFAULT_SSH_PORT;
    return p;
}

+ (PTProfile *)fromDictionary:(NSDictionary *)d {
    PTProfile *p = [[PTProfile alloc] init];
    p.uid = str(d[@"uid"]); p.name = str(d[@"name"]); p.host = str(d[@"host"]);
    p.user = str(d[@"user"]); p.directory = str(d[@"directory"]); p.pinnedFingerprint = str(d[@"pin"]);
    p.port = [d[@"port"] respondsToSelector:@selector(integerValue)] ? [d[@"port"] integerValue] : PT_DEFAULT_SSH_PORT;
    return p;
}

- (NSDictionary *)dictionary {
    return @{@"uid": self.uid, @"name": self.name, @"host": self.host, @"port": @(self.port),
             @"user": self.user, @"directory": self.directory, @"pin": self.pinnedFingerprint ?: @""};
}

- (NSString *)validationError {
    if (!self.name.length) return @"Enter a name.";
    if (!self.host.length) return @"Enter a host.";
    if (self.port < 1 || self.port > 65535) return @"The port must be 1 to 65535.";
    if (!self.user.length) return @"Enter a user name.";
    char buf[1024];
    if (pt_quote_dir(self.directory.UTF8String, buf, sizeof buf) < 0)
        return @"The directory has a control character or uses ~user.";
    return nil;
}
@end
