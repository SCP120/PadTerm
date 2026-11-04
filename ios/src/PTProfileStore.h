#import <Foundation/Foundation.h>
#import "PTProfile.h"

/* Profiles in Library/PadTerm/profiles.plist; keys in Library/PadTerm/keys/<uid>.key.
 * Files are mode 0600, with NSFileProtectionComplete if the device allows it (BR-PROFILE-1). */
@interface PTProfileStore : NSObject
+ (PTProfileStore *)shared; /* Library/PadTerm of the app; imports from the app's Documents (File Sharing) */
/* root: folder for profiles.plist and keys/; importDir: folder for <name>.key imports. */
- (instancetype)initWithRoot:(NSString *)root importDir:(NSString *)importDir;
- (NSArray *)profiles;
- (void)saveProfile:(PTProfile *)profile;
- (void)deleteProfile:(PTProfile *)profile;
- (NSData *)keyForProfile:(PTProfile *)profile;
/* Returns nil on success, else a message. The key must be a valid unencrypted Ed25519 key. */
- (NSString *)setKey:(NSData *)key forProfile:(PTProfile *)profile;
/* AC-PROFILE-2: <importDir>/<name>.key, if that file exists. */
- (NSData *)importableKeyForName:(NSString *)name;
/* Delete that file: after an import the key must not stay in a folder that File Sharing shows. */
- (void)removeImportableKeyForName:(NSString *)name;
- (NSArray *)leftoverKeyFiles; /* .key files still in the File Sharing folder */
@end
