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

static NSMutableArray<SBHIconModel *> *_globalIconModels = nil;
static NSMutableArray<SBIconModelPropertyListFileStore *> *_globalFileStores = nil;

%group IconRestoreSpringBoard

%hook SBHIconModel

%property (nonatomic, assign) BOOL ir_disableSave;

- (id)initWithStore:(id)arg1 {
    SBHIconModel *iconModel = %orig;
    if (iconModel) {
        iconModel.ir_disableSave = NO;
        [_globalIconModels addObject:iconModel];
    } 
    return iconModel;
}

// iOS 15
- (id)initWithStore:(id)arg1 applicationDataSource:(id)arg2 {
    SBHIconModel *iconModel = %orig;
    if (iconModel) {
        iconModel.ir_disableSave = NO;
        [_globalIconModels addObject:iconModel];
    }
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
    if (fileStore) {
        fileStore.ir_disableSave = NO;
        [_globalFileStores addObject:fileStore];
    }
    return fileStore;
}

- (id)initWithIconStateURL:(id)arg1 desiredIconStateURL:(id)arg2 {
    SBIconModelPropertyListFileStore *fileStore = %orig;
    if (fileStore) {
        fileStore.ir_disableSave = NO;
        [_globalFileStores addObject:fileStore];
    }
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
            for (SBHIconModel *iconModel in _globalIconModels) {
                if ([iconModel respondsToSelector:@selector(autosaveTimerDidFire:)]) {
                    [iconModel autosaveTimerDidFire:iconModel.autosaveTimer];
                    HBLogDebug(@"Force saving icon layout");
                }
            }
        });
        int forbiddenToken = 0;
        notify_register_dispatch("com.82flex.iconrestoreprefs/will-respring", &forbiddenToken, dispatch_get_main_queue(), ^(int token) {
            for (SBHIconModel *iconModel in _globalIconModels) {
                iconModel.ir_disableSave = YES;
            }
            for (SBIconModelPropertyListFileStore *fileStore in _globalFileStores) {
                fileStore.ir_disableSave = YES;
            }
            HBLogDebug(@"Disable saving icon layout");
        });
    }
}