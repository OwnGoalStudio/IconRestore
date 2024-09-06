#import <UIKit/UIKit.h>
#import <HBLog.h>

#import <notify.h>

@protocol SBIconModelStore
@end

@interface SBIconModelPropertyListFileStore : NSObject <SBIconModelStore>
@property (nonatomic, assign) BOOL ir_disableSave;
@end

@interface SBIconModelMemoryStore : NSObject <SBIconModelStore>
- (void)setDesiredState:(NSDictionary *)arg1;
@end

@interface SBIconModelReadOnlyMemoryStore : SBIconModelMemoryStore <SBIconModelStore>
@end

@interface SBHIconModel : NSObject
@property (nonatomic, strong) NSTimer *autosaveTimer;
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
- (void)autosaveTimerDidFire:(id)arg1;
@end

@interface SBHIconModel (IconRestore)
@property (nonatomic, assign) BOOL ir_disableSave;
@end

static SBHIconModel *_globalIconModel = nil;
static SBIconModelPropertyListFileStore *_globalFileStore = nil;

%group IconRestoreSpringBoard

%hook SBHIconModel

%property (nonatomic, assign) BOOL ir_disableSave;

- (id)initWithStore:(id)arg1 {
    SBHIconModel *iconModel = %orig;
    iconModel.ir_disableSave = NO;
    _globalIconModel = iconModel;
    return iconModel;
}

// iOS 15
- (id)initWithStore:(id)arg1 applicationDataSource:(id)arg2 {
    SBHIconModel *iconModel = %orig;
    iconModel.ir_disableSave = NO;
    _globalIconModel = iconModel;
    return iconModel;
}

- (void)_saveIconState {
    if (self.ir_disableSave) {
        HBLogDebug(@"Skip saving icon layout");
        return;
    }
    %orig;
}

// iOS 14.4+
- (BOOL)_saveIconStateWithError:(NSError * __autoreleasing *)arg1 {
    if (self.ir_disableSave) {
        HBLogDebug(@"Skip saving icon layout");
        return YES;
    }
    return %orig;
}

// iOS 15.2+
- (BOOL)_saveIconState:(NSDictionary *)arg1 error:(NSError * __autoreleasing *)arg2 {
    if (self.ir_disableSave) {
        HBLogDebug(@"Skip saving icon layout");
        return YES;
    }
    return %orig;
}

- (void)autosaveTimerDidFire:(id)arg1 {
    if (self.ir_disableSave) {
        HBLogDebug(@"Skip saving icon layout");
        return;
    }
    %orig;
}

%end

%hook SBIconModelPropertyListFileStore

%property (nonatomic, assign) BOOL ir_disableSave;

- (id)init {
    SBIconModelPropertyListFileStore *fileStore = %orig;
    fileStore.ir_disableSave = NO;
    _globalFileStore = fileStore;
    return fileStore;
}

- (id)initWithIconStateURL:(id)arg1 desiredIconStateURL:(id)arg2 {
    SBIconModelPropertyListFileStore *fileStore = %orig;
    fileStore.ir_disableSave = NO;
    _globalFileStore = fileStore;
    return fileStore;
}

- (BOOL)saveCurrentIconState:(id)arg1 error:(id*)arg2 {
    if (self.ir_disableSave) {
        HBLogDebug(@"Skip saving icon layout");
        return YES;
    }
    return %orig;
}

- (BOOL)_save:(id)arg1 url:(id)arg2 error:(id*)arg3 {
    if (self.ir_disableSave) {
        HBLogDebug(@"Skip saving icon layout");
        return YES;
    }
    return %orig;
}

%end

%end

%ctor {
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        %init(IconRestoreSpringBoard);
        int triggerToken = 0;
        notify_register_dispatch("com.82flex.iconrestoreprefs/save-layout", &triggerToken, dispatch_get_main_queue(), ^(int token) {
            if ([_globalIconModel respondsToSelector:@selector(autosaveTimerDidFire:)]) {
                [_globalIconModel autosaveTimerDidFire:_globalIconModel.autosaveTimer];
                HBLogDebug(@"Force saving icon layout");
            }
        });
        int forbiddenToken = 0;
        notify_register_dispatch("com.82flex.iconrestoreprefs/will-respring", &forbiddenToken, dispatch_get_main_queue(), ^(int token) {
            _globalIconModel.ir_disableSave = YES;
            _globalFileStore.ir_disableSave = YES;
            HBLogDebug(@"Disable saving icon layout");
        });
    }
}