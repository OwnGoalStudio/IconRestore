#import <Foundation/Foundation.h>
#import <Preferences/PSSpecifier.h>

#import <notify.h>
#import <stdlib.h>
#import <sys/sysctl.h>

#import "IconRestoreRootListController.h"

void IconRestoreEnumerateProcessesUsingBlock(void (^enumerator)(pid_t pid, NSString *executablePath, BOOL *stop)) {
    static int kMaximumArgumentSize = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      size_t valSize = sizeof(kMaximumArgumentSize);
      if (sysctl((int[]){CTL_KERN, KERN_ARGMAX}, 2, &kMaximumArgumentSize, &valSize, NULL, 0) < 0) {
          perror("sysctl argument size");
          kMaximumArgumentSize = 4096;
      }
    });

    size_t procInfoLength = 0;
    if (sysctl((int[]){CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0}, 3, NULL, &procInfoLength, NULL, 0) < 0) {
        return;
    }

    static struct kinfo_proc *procInfo = NULL;
    procInfo = (struct kinfo_proc *)realloc(procInfo, procInfoLength + 1);
    if (!procInfo) {
        return;
    }

    bzero(procInfo, procInfoLength + 1);
    if (sysctl((int[]){CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0}, 3, procInfo, &procInfoLength, NULL, 0) < 0) {
        return;
    }

    static char *argBuffer = NULL;
    int procInfoCnt = (int)(procInfoLength / sizeof(struct kinfo_proc));
    for (int i = 0; i < procInfoCnt; i++) {

        pid_t pid = procInfo[i].kp_proc.p_pid;
        if (pid <= 1) {
            continue;
        }

        size_t argSize = kMaximumArgumentSize;
        if (sysctl((int[]){CTL_KERN, KERN_PROCARGS2, pid, 0}, 3, NULL, &argSize, NULL, 0) < 0) {
            continue;
        }

        argBuffer = (char *)realloc(argBuffer, argSize + 1);
        if (!argBuffer) {
            continue;
        }

        bzero(argBuffer, argSize + 1);
        if (sysctl((int[]){CTL_KERN, KERN_PROCARGS2, pid, 0}, 3, argBuffer, &argSize, NULL, 0) < 0) {
            continue;
        }

        BOOL stop = NO;
        @autoreleasepool {
            enumerator(pid, [NSString stringWithUTF8String:(argBuffer + sizeof(int))], &stop);
        }

        if (stop) {
            break;
        }
    }
}

void IconRestoreKillAll(NSString *processName, BOOL softly) {
    IconRestoreEnumerateProcessesUsingBlock(^(pid_t pid, NSString *executablePath, BOOL *stop) {
      if ([executablePath.lastPathComponent isEqualToString:processName]) {
          if (softly) {
              kill(pid, SIGTERM);
          } else {
              kill(pid, SIGKILL);
          }
      }
    });
}

void IconRestoreBatchKillAll(NSArray<NSString *> *processNames, BOOL softly) {
    IconRestoreEnumerateProcessesUsingBlock(^(pid_t pid, NSString *executablePath, BOOL *stop) {
      if ([processNames containsObject:executablePath.lastPathComponent]) {
          if (softly) {
              kill(pid, SIGTERM);
          } else {
              kill(pid, SIGKILL);
          }
      }
    });
}

@interface LSPlugInKitProxy : NSObject
@property(nonatomic, readonly, copy) NSString *pluginIdentifier;
@end

@interface LSApplicationProxy : NSObject
@property(nonatomic, readonly) NSArray<LSPlugInKitProxy *> *plugInKitPlugins;
+ (LSApplicationProxy *)applicationProxyForIdentifier:(NSString *)bundleIdentifier;
@end

@implementation IconRestoreRootListController {
    NSArray<NSDictionary *> *_savepoints;
    PSSpecifier *_savepointsGroupSpecifier;
    NSString *_cachedSelectedSavepoint;
    NSString *_iconStatePath;
}

- (void)viewDidLoad {
    [super viewDidLoad];
#ifdef IPHONE_SIMULATOR_ROOT
    _iconStatePath = @IPHONE_SIMULATOR_ROOT "/var/mobile/Library/SpringBoard/IconState.plist";
#else
    _iconStatePath = @"/var/mobile/Library/SpringBoard/IconState.plist";
#endif
    [self notifyTweakToSaveLayout];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)didBecomeActive:(NSNotification *)notification {
    [self notifyTweakToSaveLayout];
}

- (void)notifyTweakToSaveLayout {
    notify_post("com.82flex.iconrestoreprefs/save-layout");
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSArray *specs = [self loadSpecifiersFromPlistName:@"Root" target:self];
        NSMutableArray *mutableSpecs = [NSMutableArray arrayWithArray:specs];
        NSInteger insertIndex = 0;
        for (PSSpecifier *specifier in mutableSpecs) {
            insertIndex++;
            NSString *specKey = [specifier propertyForKey:@"key"];
            if ([specKey isEqualToString:@"__savepoints__"]) {
                _savepointsGroupSpecifier = specifier;
                break;
            }
        }
        NSMutableArray<PSSpecifier *> *savepointSpecifiers = [NSMutableArray array];
        [self readSavepoints];
        for (NSDictionary *savepoint in _savepoints) {
            PSSpecifier *specifier = [self _specifierForSavepoint:savepoint];
            [savepointSpecifiers addObject:specifier];
        }
        [mutableSpecs
            insertObjects:savepointSpecifiers
                atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(insertIndex, savepointSpecifiers.count)]];
        _specifiers = mutableSpecs;
        _cachedSelectedSavepoint = [self selectedSavepoint];
    }
    return _specifiers;
}

- (void)saveCurrentLayout {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Create New Layout", @"Root", self.bundle, nil)
                         message:NSLocalizedStringFromTableInBundle(@"Enter a name for this layout, or leave it blank.",
                                                                    @"Root", self.bundle, nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
      textField.placeholder = NSLocalizedStringFromTableInBundle(@"Layout Name", @"Root", self.bundle, nil);
    }];
    [alert addAction:[UIAlertAction
                         actionWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"Root", self.bundle, nil)
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];
    [alert
        addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Save", @"Root", self.bundle, nil)
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *action) {
                                           NSString *alias = alert.textFields.firstObject.text;
                                           [self saveCurrentLayoutWithAlias:alias];
                                         }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveCurrentLayoutWithAlias:(NSString *)alias {
    NSData *iconStateData = [NSData dataWithContentsOfFile:_iconStatePath];
    if (!iconStateData) {
        return;
    }
    NSMutableDictionary *newSavepoint = [@{
        @"created" : @(NSDate.date.timeIntervalSince1970),
        @"payload" : iconStateData,
        @"uuid" : NSUUID.UUID.UUIDString,
    } mutableCopy];
    if (alias.length) {
        newSavepoint[@"alias"] = alias;
    }
    NSMutableArray<NSDictionary *> *savepoints = [NSMutableArray arrayWithArray:_savepoints];
    [savepoints insertObject:newSavepoint atIndex:0];
    _savepoints = savepoints;
    [self writeSavepoints];
    if (_cachedSelectedSavepoint) {
        NSArray<PSSpecifier *> *allSpecifiers = [self specifiersInGroup:1];
        for (PSSpecifier *specifier in allSpecifiers) {
            NSString *key = [specifier propertyForKey:@"key"];
            NSString *uuid = [key componentsSeparatedByString:@"."].lastObject;
            if ([uuid isEqualToString:_cachedSelectedSavepoint]) {
                [self reloadSpecifier:specifier animated:YES];
                break;
            }
        }
    }
    [self selectSavepoint:newSavepoint[@"uuid"]];
    PSSpecifier *newSpecifier = [self _specifierForSavepoint:newSavepoint];
    [self insertSpecifier:newSpecifier afterSpecifier:_savepointsGroupSpecifier animated:YES];
}

- (void)removedSpecifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *uuid = [key componentsSeparatedByString:@"."].lastObject;
    NSMutableArray<NSDictionary *> *savepoints = [NSMutableArray arrayWithArray:_savepoints];
    [savepoints
        filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *savepoint, NSDictionary *bindings) {
          return ![savepoint[@"uuid"] isEqualToString:uuid];
        }]];
    _savepoints = savepoints;
    [self writeSavepoints];
    [self readSavepoints];
}

- (id)valueForSpecifier:(PSSpecifier *)specifier {
#if DEBUG
    return [specifier propertyForKey:@"value"];
#else
    return nil;
#endif
}

- (PSSpecifier *)_specifierForSavepoint:(NSDictionary *)savepoint {
    NSString *key = [NSString stringWithFormat:@"savepoint.%@", savepoint[@"uuid"]];
    NSString *value = [savepoint[@"uuid"] substringToIndex:6];
    NSDate *created = [NSDate dateWithTimeIntervalSince1970:[savepoint[@"created"] doubleValue]];
    static NSDateFormatter *dateFormatter = nil;
    if (!dateFormatter) {
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateStyle = NSDateFormatterMediumStyle;
        dateFormatter.timeStyle = NSDateFormatterMediumStyle;
    }
    NSString *dateString = [dateFormatter stringFromDate:created];
    NSString *alias = savepoint[@"alias"];
    NSString *displayName = alias ?: dateString;
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:displayName
                                                            target:self
                                                               set:nil
                                                               get:@selector(valueForSpecifier:)
                                                            detail:nil
                                                              cell:PSTitleValueCell
                                                              edit:nil];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:value forKey:@"value"];
    [specifier setProperty:@"com.82flex.iconrestoreprefs" forKey:@"defaults"];
    [specifier setProperty:NSStringFromSelector(@selector(removedSpecifier:)) forKey:PSDeletionActionKey];
    return specifier;
}

- (PSSpecifier *)_selectedSavepointSpecifier {
    static PSSpecifier *stubSpecifier = nil;
    if (!stubSpecifier) {
        stubSpecifier = [PSSpecifier preferenceSpecifierNamed:@"Selected Savepoint"
                                                       target:self
                                                          set:@selector(setPreferenceValue:specifier:)
                                                          get:@selector(readPreferenceValue:)
                                                       detail:nil
                                                         cell:PSLinkListCell
                                                         edit:nil];
        [stubSpecifier setProperty:@"SelectedSavepoint" forKey:@"key"];
        [stubSpecifier setProperty:@"com.82flex.iconrestoreprefs" forKey:@"defaults"];
    }
    return stubSpecifier;
}

- (PSSpecifier *)_savepointsSpecifier {
    static PSSpecifier *stubSpecifier = nil;
    if (!stubSpecifier) {
        stubSpecifier = [PSSpecifier preferenceSpecifierNamed:@"All Layouts"
                                                       target:self
                                                          set:@selector(setPreferenceValue:specifier:)
                                                          get:@selector(readPreferenceValue:)
                                                       detail:nil
                                                         cell:PSLinkListCell
                                                         edit:nil];
        [stubSpecifier setProperty:@"All Layouts" forKey:@"key"];
        [stubSpecifier setProperty:@"com.82flex.iconrestoreprefs" forKey:@"defaults"];
    }
    return stubSpecifier;
}

- (void)readSavepoints {
    _savepoints = [super readPreferenceValue:[self _savepointsSpecifier]];
}

- (void)writeSavepoints {
    [super setPreferenceValue:(_savepoints ?: @[]) specifier:[self _savepointsSpecifier]];
}

- (NSString *)selectedSavepoint {
    return [super readPreferenceValue:[self _selectedSavepointSpecifier]];
}

- (void)tableView:(UITableView *)tableView
    selectSavepoint:(PSSpecifier *)specifier
        atIndexPath:(NSIndexPath *)indexPath {
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *uuid = [key componentsSeparatedByString:@"."].lastObject;
    if (_cachedSelectedSavepoint && [uuid isEqualToString:_cachedSelectedSavepoint]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Restore Layout", @"Root", self.bundle, nil)
                         message:NSLocalizedStringFromTableInBundle(
                                     @"Are you sure you want to restore to this icon layout?", @"Root",
                                     self.bundle, nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction
                         actionWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"Root", self.bundle, nil)
                                   style:UIAlertActionStyleCancel
                                 handler:^(UIAlertAction *action) {
                                   [tableView deselectRowAtIndexPath:indexPath animated:YES];
                                 }]];
    [alert
        addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Apply", @"Root", self.bundle, nil)
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *action) {
                                           [tableView deselectRowAtIndexPath:indexPath animated:YES];
                                           [self applySavepoint:uuid];
                                         }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)applySavepoint:(NSString *)uuid {
    BOOL saved = [self selectSavepoint:uuid];
    if (!saved) {
        return;
    }
    BOOL applied = [self _applySelectedSavepoint];
    if (applied) {
        [self respring];
    }
}

- (BOOL)selectSavepoint:(NSString *)uuid {
    BOOL saved = [self _saveSelectedSavepoint];
    if (!saved) {
        return NO;
    }
    [super setPreferenceValue:uuid specifier:[self _selectedSavepointSpecifier]];
    _cachedSelectedSavepoint = uuid;
    return YES;
}

- (BOOL)_saveSelectedSavepoint {
    NSString *uuid = [self selectedSavepoint];
    if (!uuid) {
        return YES;
    }
    NSInteger replaceIndex = NSNotFound;
    NSInteger index = 0;
    for (NSDictionary *savepoint in _savepoints) {
        if ([savepoint[@"uuid"] isEqualToString:uuid]) {
            replaceIndex = index;
            break;
        }
        index++;
    }
    if (replaceIndex == NSNotFound) {
        return YES;
    }
    NSData *iconStateData = [NSData dataWithContentsOfFile:_iconStatePath];
    if (!iconStateData) {
        return NO;
    }
    NSMutableDictionary *savepoint = [NSMutableDictionary dictionaryWithDictionary:_savepoints[replaceIndex]];
    savepoint[@"payload"] = iconStateData;
    NSMutableArray<NSDictionary *> *savepoints = [NSMutableArray arrayWithArray:_savepoints];
    [savepoints replaceObjectAtIndex:replaceIndex withObject:savepoint];
    _savepoints = savepoints;
    [self writeSavepoints];
    return YES;
}

- (BOOL)_applySelectedSavepoint {
    NSString *uuid = [self selectedSavepoint];
    if (!uuid) {
        return NO;
    }
    NSDictionary *savepoint =
        [_savepoints filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"uuid = %@", uuid]].firstObject;
    if (!savepoint) {
        return NO;
    }
    NSData *iconStateData = savepoint[@"payload"];
    if (!iconStateData) {
        return NO;
    }
    BOOL wrote = [iconStateData writeToFile:_iconStatePath atomically:YES];
    if (!wrote) {
        return NO;
    }
    return YES;
}

- (void)respring {
    notify_post("com.82flex.iconrestoreprefs/will-respring");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self reloadSpecifiers];
      IconRestoreBatchKillAll(@[ @"SpringBoard" ], YES);
    });
}

- (void)support {
    NSURL *url = [NSURL URLWithString:@"https://havoc.app/search/82Flex"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

#pragma mark - Table View

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        return UITableViewCellEditingStyleDelete;
    }
    return UITableViewCellEditingStyleNone;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
        NSString *key = [specifier propertyForKey:@"key"];
        NSString *uuid = [key componentsSeparatedByString:@"."].lastObject;
        if (_cachedSelectedSavepoint && [uuid isEqualToString:_cachedSelectedSavepoint]) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        } else {
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
        return cell;
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
        [self tableView:tableView selectSavepoint:specifier atIndexPath:indexPath];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

@end
