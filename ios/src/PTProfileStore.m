#import "PTProfileStore.h"
#include <sys/stat.h>
#include "pt_ssh.h"

@implementation PTProfileStore {
    NSMutableArray *_profiles;
    NSString *_root, *_importDir;
}

+ (PTProfileStore *)shared {
    static PTProfileStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES)[0];
        /* Documents: a key can arrive there without root (iTunes File Sharing, scripts/ipad_install_key.sh). */
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        s = [[PTProfileStore alloc] initWithRoot:[lib stringByAppendingPathComponent:@"PadTerm"] importDir:docs];
    });
    return s;
}

- (instancetype)initWithRoot:(NSString *)root importDir:(NSString *)importDir {
    if ((self = [super init])) { _root = [root copy]; _importDir = [importDir copy]; }
    return self;
}

- (NSString *)dir {
    NSString *d = _root;
    NSDictionary *attrs = @{NSFilePosixPermissions: @0700};
    [[NSFileManager defaultManager] createDirectoryAtPath:[d stringByAppendingPathComponent:@"keys"]
                              withIntermediateDirectories:YES attributes:attrs error:NULL];
    return d;
}

- (NSString *)plistPath { return [[self dir] stringByAppendingPathComponent:@"profiles.plist"]; }
- (NSString *)keyPath:(PTProfile *)p {
    return [[[self dir] stringByAppendingPathComponent:@"keys"] stringByAppendingPathComponent:[p.uid stringByAppendingString:@".key"]];
}

static BOOL writeSecure(NSData *data, NSString *path) {
    NSError *err = nil;
#if TARGET_OS_IPHONE
    BOOL ok = [data writeToFile:path options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:&err];
    if (!ok && err.code == NSFileWriteNoPermissionError) {
        /* Seen on a jailbroken iPad mini, iOS 6.1.3: the data partition refuses protection classes with EPERM
         * (installd logs the same for the app container). Mode 0600 below is then the only protection. */
        NSLog(@"PadTerm: no file protection on this device for %@; using mode 0600 only", path.lastPathComponent);
        err = nil;
        ok = [data writeToFile:path options:NSDataWritingAtomic error:&err];
    }
#else
    BOOL ok = [data writeToFile:path options:NSDataWritingAtomic error:&err]; /* macOS host tests */
#endif
    if (!ok) {
        NSLog(@"PadTerm: cannot write %@: %@", path.lastPathComponent, err); /* the data is never logged */
        return NO;
    }
    chmod(path.fileSystemRepresentation, 0600);
    return YES;
}

- (NSMutableArray *)loaded {
    if (!_profiles) {
        _profiles = [NSMutableArray array];
        for (NSDictionary *d in [NSArray arrayWithContentsOfFile:[self plistPath]] ?: @[])
            if ([d isKindOfClass:[NSDictionary class]]) [_profiles addObject:[PTProfile fromDictionary:d]];
    }
    return _profiles;
}

- (void)persist {
    NSMutableArray *a = [NSMutableArray array];
    for (PTProfile *p in [self loaded]) [a addObject:[p dictionary]];
    NSData *d = [NSPropertyListSerialization dataWithPropertyList:a format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    writeSecure(d, [self plistPath]);
}

- (NSArray *)profiles { return [[self loaded] copy]; }

- (void)saveProfile:(PTProfile *)profile {
    NSMutableArray *a = [self loaded];
    NSUInteger i = [a indexOfObjectPassingTest:^BOOL(PTProfile *p, NSUInteger idx, BOOL *stop) { return [p.uid isEqualToString:profile.uid]; }];
    if (i == NSNotFound) [a addObject:profile]; else a[i] = profile;
    [self persist];
}

- (void)deleteProfile:(PTProfile *)profile {
    [[self loaded] filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PTProfile *p, NSDictionary *b) { return ![p.uid isEqualToString:profile.uid]; }]];
    [[NSFileManager defaultManager] removeItemAtPath:[self keyPath:profile] error:NULL];
    [self persist];
}

- (NSData *)keyForProfile:(PTProfile *)profile { return [NSData dataWithContentsOfFile:[self keyPath:profile]]; }

- (NSString *)setKey:(NSData *)key forProfile:(PTProfile *)profile {
    if (!pt_ssh_key_valid(key.bytes, key.length))
        return @"This is not an unencrypted OpenSSH Ed25519 private key. Make one with: ssh-keygen -t ed25519 -N \"\"";
    NSString *path = [self keyPath:profile];
    if (!writeSecure(key, path)) return @"The key could not be saved.";
    /* A device backup must not carry the unencrypted key. An atomic write makes a new file, so this follows each write. */
    NSError *err = nil;
    if (![[NSURL fileURLWithPath:path] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&err])
        NSLog(@"PadTerm: cannot exclude the key from backups: %@", err.localizedDescription);
    return nil;
}

- (NSString *)importPath:(NSString *)name {
    if (!name.length || [name rangeOfString:@"/"].location != NSNotFound) return nil;
    return [_importDir stringByAppendingPathComponent:[name stringByAppendingString:@".key"]];
}

- (NSArray *)leftoverKeyFiles {
    NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_importDir error:NULL];
    return [all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pathExtension == 'key'"]];
}

- (NSData *)importableKeyForName:(NSString *)name {
    NSString *path = [self importPath:name];
    return path ? [NSData dataWithContentsOfFile:path] : nil;
}

- (void)removeImportableKeyForName:(NSString *)name {
    NSString *path = [self importPath:name];
    if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}
@end
