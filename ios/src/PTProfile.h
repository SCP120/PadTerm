#import <Foundation/Foundation.h>

/* One server profile (AC-PROFILE-1). The private key is stored apart from the profile (PTProfileStore). */
@interface PTProfile : NSObject
@property (nonatomic, copy) NSString *uid;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, copy) NSString *user;
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, copy) NSString *pinnedFingerprint; /* "" until the first connection is accepted */

+ (PTProfile *)newProfile;
+ (PTProfile *)fromDictionary:(NSDictionary *)d;
- (NSDictionary *)dictionary;
/* nil if valid, else a message for the user. */
- (NSString *)validationError;
@end
