/* PTProfile + PTProfileStore on macOS (Foundation only). Store root is a temp folder, never ~/Library. */
#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include "pt_test.h"
#import "../../ios/src/PTProfile.h"
#import "../../ios/src/PTProfileStore.h"

static NSString *tempDir(void) {
    char t[] = "build/tmp-profile-XXXXXX";
    return [NSString stringWithUTF8String:mkdtemp(t)];
}
static NSData *testKey(void) { return [NSData dataWithContentsOfFile:@"build/e2e-sshd/client_ed25519"]; }
static int fileMode(NSString *path) { struct stat st; return stat(path.fileSystemRepresentation, &st) == 0 ? (int)(st.st_mode & 0777) : -1; }

PT_TEST(profile_validation, "AC-PROFILE-1 EF-LAUNCH-2") {
    @autoreleasepool {
        PTProfile *p = [PTProfile newProfile];
        CHECK(p.uid.length == 36); CHECK_INT(p.port, 22);
        CHECK([[p validationError] isEqualToString:@"Enter a name."]);
        p.name = @"vps"; p.host = @"example.com"; p.user = @"me";
        CHECK([p validationError] == nil);
        p.port = 0; CHECK([p validationError] != nil); p.port = 65536; CHECK([p validationError] != nil); p.port = 2222;
        p.directory = @"~/a\nb"; CHECK([[p validationError] rangeOfString:@"directory"].location != NSNotFound);
        p.directory = @"~bob/x"; CHECK([p validationError] != nil);
        p.directory = @"~/src"; CHECK([p validationError] == nil);
    }
}

PT_TEST(profile_store_round_trip_and_delete, "AC-PROFILE-1") {
    @autoreleasepool {
        NSString *root = tempDir();
        PTProfileStore *st = [[PTProfileStore alloc] initWithRoot:root importDir:root];
        PTProfile *p = [PTProfile newProfile];
        p.name = @"vps"; p.host = @"example.com"; p.user = @"me"; p.directory = @"~/src"; p.pinnedFingerprint = @"SHA256:abc";
        [st saveProfile:p];
        CHECK([st setKey:testKey() forProfile:p] == nil);
        PTProfileStore *again = [[PTProfileStore alloc] initWithRoot:root importDir:root]; /* reads from disk */
        CHECK_INT([again profiles].count, 1);
        PTProfile *q = [again profiles][0];
        CHECK([q.uid isEqualToString:p.uid]); CHECK([q.host isEqualToString:@"example.com"]);
        CHECK([q.pinnedFingerprint isEqualToString:@"SHA256:abc"]); CHECK([q.directory isEqualToString:@"~/src"]);
        CHECK([[again keyForProfile:q] isEqualToData:testKey()]);
        q.host = @"other.example"; [again saveProfile:q];
        CHECK_INT([again profiles].count, 1);
        [again deleteProfile:q];
        CHECK_INT([again profiles].count, 0);
        CHECK([again keyForProfile:q] == nil); /* the key file goes with the profile */
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }
}

PT_TEST(profile_store_refuses_bad_key, "EF-CONNECT-3 AC-PROFILE-1") {
    @autoreleasepool {
        NSString *root = tempDir();
        PTProfileStore *st = [[PTProfileStore alloc] initWithRoot:root importDir:root];
        PTProfile *p = [PTProfile newProfile];
        NSString *err = [st setKey:[@"not a key" dataUsingEncoding:NSUTF8StringEncoding] forProfile:p];
        CHECK(err != nil);
        CHECK([st keyForProfile:p] == nil);
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }
}

PT_TEST(profile_files_mode_0600, "BR-PROFILE-1") {
    @autoreleasepool {
        NSString *root = tempDir();
        PTProfileStore *st = [[PTProfileStore alloc] initWithRoot:root importDir:root];
        PTProfile *p = [PTProfile newProfile];
        p.name = @"n"; p.host = @"h"; p.user = @"u";
        [st saveProfile:p];
        CHECK([st setKey:testKey() forProfile:p] == nil);
        CHECK_INT(fileMode([root stringByAppendingPathComponent:@"profiles.plist"]), 0600);
        CHECK_INT(fileMode([root stringByAppendingFormat:@"/keys/%@.key", p.uid]), 0600);
        CHECK_INT(fileMode([root stringByAppendingPathComponent:@"keys"]), 0700);
        NSNumber *excluded = nil;
        [[NSURL fileURLWithPath:[root stringByAppendingFormat:@"/keys/%@.key", p.uid]] getResourceValue:&excluded forKey:NSURLIsExcludedFromBackupKey error:NULL];
        CHECK(excluded.boolValue); /* BR-PROFILE-1: no device backup holds the key */
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }
}

PT_TEST(profile_key_import_by_name, "AC-PROFILE-2") {
    @autoreleasepool {
        NSString *root = tempDir(), *imports = tempDir();
        [testKey() writeToFile:[imports stringByAppendingPathComponent:@"vps.key"] atomically:YES];
        PTProfileStore *st = [[PTProfileStore alloc] initWithRoot:root importDir:imports];
        CHECK([[st importableKeyForName:@"vps"] isEqualToData:testKey()]);
        CHECK([st importableKeyForName:@"missing"] == nil);
        CHECK([st importableKeyForName:@"../vps"] == nil); /* no path walk out of the import folder */
        CHECK([st importableKeyForName:@""] == nil);
        [st removeImportableKeyForName:@"../vps"]; /* refused: the file stays */
        CHECK([st importableKeyForName:@"vps"] != nil);
        [st removeImportableKeyForName:@"vps"];    /* no key copy left in the shared folder */
        CHECK([st importableKeyForName:@"vps"] == nil);
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:imports error:NULL];
    }
}

/* ---- UC-SESSION: the list text, frozen from the output of pt_session_list_command ---- */
#import "PTSession.h"
#include "pt_session.h"

#define KA "11111111-1111-4111-8111-111111111111"
#define KB "22222222-2222-4222-8222-222222222222"
#define KC "33333333-3333-4333-8333-333333333333"

PT_TEST(session_listing_parse_and_sort, "AC-SESSION-2 AC-SESSION-3 BR-SESSION-3") {
    @autoreleasepool {
        NSString *text = @"S\t" KA "\tclaude\t1000\t/work/a b\n"
                         @"T\t" KA "\t{\"type\":\"custom-title\",\"customTitle\":\"My name\",\"sessionId\":\"" KA "\"}\n"
                         @"R\t" KA "\n"
                         @"S\t" KB "\tcodex\t3000\t/work/b\n"
                         @"T\t" KB "\t{\"id\":\"x\",\"thread_name\":\"Reply probe\",\"updated_at\":\"t\"}\n"
                         @"S\t" KC "\tclaude\t2000\t/work/c\n"
                         @"T\t" KC "\tnot json\n"
                         @"S\t../../x\tclaude\t9000\t/bad\n"
                         @"S\t44444444-4444-4444-8444-444444444444\tvim\t9000\t/bad\n"
                         @"garbage line\n";
        NSArray *a = [PTSession sessionsFromListing:[text dataUsingEncoding:NSUTF8StringEncoding]];
        CHECK_INT(a.count, 3);
        PTSession *first = a[0], *second = a[1], *third = a[2];
        CHECK_STR(first.key.UTF8String, KB);
        CHECK_STR(first.displayTitle.UTF8String, "Reply probe");
        CHECK_STR(first.agentName.UTF8String, "Codex");
        CHECK_INT(first.running, 0);
        CHECK_STR(second.displayTitle.UTF8String, "New session"); /* a record that is not JSON is no title */
        CHECK_STR(third.displayTitle.UTF8String, "My name");
        CHECK_STR(third.directory.UTF8String, "/work/a b");
        CHECK_INT(third.running, 1);
        CHECK_INT((long long)third.lastActive.timeIntervalSince1970, 1000);
    }
}

PT_TEST(session_empty_listing_and_new_key, "AC-SESSION-1") {
    @autoreleasepool {
        CHECK_INT([PTSession sessionsFromListing:[NSData data]].count, 0);
        PTSession *s = [PTSession newSessionWithAgent:PT_AGENT_CLAUDE directory:@"~"];
        CHECK_INT(s.key.length, 36);
        CHECK(pt_session_key_valid(s.key.UTF8String));
        CHECK([s.key isEqualToString:s.key.lowercaseString]); /* claude --session-id takes this form */
        CHECK(![s.key isEqualToString:[PTSession newSessionWithAgent:PT_AGENT_CLAUDE directory:@"~"].key]);
    }
}

PT_TEST(session_age_text, "AC-SESSION-2") {
    @autoreleasepool {
        NSDate *now = [NSDate dateWithTimeIntervalSince1970:1000000];
        NSString *(^age)(int) = ^(int s) { return [PTSession ageOfDate:[now dateByAddingTimeInterval:-s] now:now]; };
        CHECK_STR(age(59).UTF8String, "just now");
        CHECK_STR(age(60).UTF8String, "1 min ago");
        CHECK_STR(age(3599).UTF8String, "59 min ago");
        CHECK_STR(age(3600).UTF8String, "1 hr ago");
        CHECK_STR(age(86399).UTF8String, "23 hr ago");
        CHECK_STR(age(86400).UTF8String, "yesterday");
        CHECK_STR(age(2 * 86400).UTF8String, "2 days ago");
    }
}

PT_TEST(session_listing_keeps_good_lines_around_bad_bytes, "AC-SESSION-2") {
    @autoreleasepool {
        NSMutableData *d = [[@"S\t" KA "\tclaude\t1000\t/ok\n" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        const char latin[] = "S\t" KB "\tclaude\t2000\t/caf\xE9\n"; /* Latin-1: not valid UTF-8 */
        [d appendBytes:latin length:sizeof latin - 1];
        [d appendData:[@"S\t" KC "\tcodex\t3000\t/last" dataUsingEncoding:NSUTF8StringEncoding]]; /* no final newline */
        NSArray *a = [PTSession sessionsFromListing:d];
        CHECK_INT(a.count, 2);
        CHECK_STR([a[0] directory].UTF8String, "/last");
        CHECK_STR([a[1] directory].UTF8String, "/ok");
    }
}

PT_TEST(session_same_row, "AC-SESSION-2") {
    @autoreleasepool {
        NSData *one = [@"S\t" KA "\tclaude\t1000\t/w\n" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *running = [@"S\t" KA "\tclaude\t1000\t/w\nR\t" KA "\n" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *named = [@"S\t" KA "\tclaude\t1000\t/w\nT\t" KA "\t{\"aiTitle\":\"n\"}\n" dataUsingEncoding:NSUTF8StringEncoding];
        PTSession *a = [PTSession sessionsFromListing:one][0];
        CHECK([a sameRowAs:[PTSession sessionsFromListing:one][0]]);
        CHECK(![a sameRowAs:[PTSession sessionsFromListing:running][0]]);
        CHECK(![a sameRowAs:[PTSession sessionsFromListing:named][0]]);
    }
}
