#import <UIKit/UIKit.h>
#import <HBLog.h>

#import <notify.h>

@protocol SBIconModelStore
@end

@interface SBIconModelPropertyListFileStore : NSObject <SBIconModelStore>
@end

@interface SBIconModelMemoryStore : NSObject <SBIconModelStore>
- (void)setDesiredState:(NSDictionary *)arg1;
@end

@interface SBIconModelReadOnlyMemoryStore : SBIconModelMemoryStore <SBIconModelStore>
@end

@interface SBHIconModel : NSObject
@property (nonatomic, strong, readonly) id<SBIconModelStore> store;
- (void)importIconState:(NSDictionary *)arg1;
- (void)importDesiredIconState:(NSDictionary *)arg1;
- (void)markIconStateDirty;
- (void)markIconStateClean;
- (void)reloadIcons;
- (void)layout;
- (void)clearDesiredIconState;
- (void)_saveIconState;
- (BOOL)_saveIconState:(NSDictionary *)arg1 error:(NSError * __autoreleasing *)arg2;
@end

static SBHIconModel *_globalIconModel = nil;

%group IconRestoreSpringBoard

%hook SBHIconModel

- (id)initWithStore:(id)arg1 {
    SBHIconModel *iconModel = %orig;
    _globalIconModel = iconModel;
    return iconModel;
}

// iOS 15
- (id)initWithStore:(id)arg1 applicationDataSource:(id)arg2 {
    SBHIconModel *iconModel = %orig;
    _globalIconModel = iconModel;
    return iconModel;
}

%end

%end

%ctor {
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        %init(IconRestoreSpringBoard);
        int triggerToken = 0;
        notify_register_dispatch("com.82flex.iconrestoreprefs/save-layout", &triggerToken, dispatch_get_main_queue(), ^(int token) {
            if ([_globalIconModel respondsToSelector:@selector(_saveIconState)]) {
                [_globalIconModel _saveIconState];
                HBLogDebug(@"Force saving icon layout");
            }
        });
    }
}