#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Interfaces.h"
#import <objc/runtime.h>
#import <objc/message.h>

%config(generator=internal);

// MARK: - Preferences
//
// Domain matches the pane at /Library/PreferenceBundles/dockpidPrefs.bundle.
// CFPreferences rather than NSUserDefaults so cfprefsd's cache can be dropped
// explicitly when the pane posts its change notification -- Dock is long-lived
// and would otherwise serve a stale value for the rest of its life.

static NSString * const kDockPidDomain = @"com.doraorak.dockpid";

static BOOL gEnabled = YES;
static NSString *gStyle = @"parens";

// Every tile we have decorated, held weakly. Dock caches labels and will not
// call -label again just because a preference changed, so this is how a style
// or enable change is applied to what is already on screen -- without the
// sledgehammer of relaunching Dock.
static NSHashTable *gTiles;

static NSString *DockPidDecoratedLabel(id tile);   // defined below

/// Removes any suffix this tweak previously appended, in any style.
///
/// This is what stops a pid getting welded into a label permanently. -label stores
/// what Dock hands back as "the original", but Dock keeps its own copy of the label
/// we pushed via -setLabel:stripAppSuffix:. If a tile object is recreated -- Dock
/// rebuilds them on layout changes, app launches and quits -- the association is
/// gone while Dock's copy is still decorated, so the next capture takes
/// "Safari (123)" to BE the original. From then on the pid never goes away, it
/// survives the app quitting, and each cycle appends another one.
///
/// Stripping on capture makes the decoration idempotent and self-healing: whatever
/// state Dock is in, the original is recovered.
static NSString *DockPidStripSuffix(NSString *label) {
    if (![label isKindOfClass:[NSString class]] || label.length == 0) return label;

    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
                 @"(\\s\\(\\d+\\)|\\s\\[\\d+\\]|\\s\\u2014\\s\\d+)$"
                                                       options:0 error:NULL];
    });
    if (!re) return label;

    NSString *out = label;
    // Loop: a label may already carry more than one, from before this existed.
    while (1) {
        NSRange full = NSMakeRange(0, out.length);
        NSTextCheckingResult *m = [re firstMatchInString:out options:0 range:full];
        if (!m || m.range.location == NSNotFound || m.range.length == 0) break;
        out = [out substringToIndex:m.range.location];
    }
    return out;
}

/// Puts every tile we have touched back to its undecorated label.
static void DockPidRestoreTiles(void) {
    if (!gTiles) return;
    for (id tile in gTiles.allObjects) {
        NSString *orig = objc_getAssociatedObject(tile, @selector(label));
        if (orig && [tile respondsToSelector:@selector(setLabel:stripAppSuffix:)]) {
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(tile, @selector(setLabel:stripAppSuffix:), orig, YES);
        }
    }
}

static void DockPidRefreshTiles(void) {
    if (!gTiles) return;
    for (id tile in gTiles.allObjects) {
        NSString *lbl = DockPidDecoratedLabel(tile);
        if (lbl && [tile respondsToSelector:@selector(setLabel:stripAppSuffix:)]) {
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(tile, @selector(setLabel:stripAppSuffix:), lbl, YES);
        }
    }
}

static void DockPidLoadPrefs(void) {
    CFStringRef domain = (__bridge CFStringRef)kDockPidDomain;
    CFPreferencesAppSynchronize(domain);

    Boolean valid = false;
    Boolean enabled = CFPreferencesGetAppBooleanValue(CFSTR("enabled"), domain, &valid);
    gEnabled = valid ? (BOOL)enabled : YES;   // absent key means on, not off

    id style = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("style"), domain));
    gStyle = ([style isKindOfClass:[NSString class]]) ? (NSString *)style : @"parens";
}

/// Running pid for a Dock tile's bundle identifier, or 0.
///
/// The guard is the whole point. The AppKit lookup raises
/// NSInvalidArgumentException for nil OR EMPTY input, and a folder / Trash / stack
/// tile answers `bundleIdentifier` with an empty string rather than nil — so a
/// nil-only check passes it straight through and aborts Dock (which then crash-loops
/// into safe mode). This lives in one place so the two call sites cannot drift apart
/// again: they previously did, and only one of them carried the full guard.
static pid_t DockPidRunningPID(NSString *bid) {
    if (![bid isKindOfClass:[NSString class]] || bid.length == 0) return 0;
    NSArray *arr = [NSRunningApplication runningApplicationsWithBundleIdentifier:bid];
    if (arr.count == 0) return 0;
    return [[arr objectAtIndex:0] processIdentifier];
}

static NSString *DockPidSuffix(pid_t pid) {
    if ([gStyle isEqualToString:@"brackets"]) return [NSString stringWithFormat:@" [%d]", pid];
    if ([gStyle isEqualToString:@"dash"])     return [NSString stringWithFormat:@" — %d", pid];
    return [NSString stringWithFormat:@" (%d)", pid];
}

/// Rebuild a tile's label from its stored original using the current prefs.
static NSString *DockPidDecoratedLabel(id tile) {
    NSString *origlbl = objc_getAssociatedObject(tile, @selector(label));
    if (!origlbl) return nil;
    if (!gEnabled) return origlbl;

    NSString *bid = [tile respondsToSelector:@selector(bundleIdentifier)]
                  ? ((id (*)(id, SEL))objc_msgSend)(tile, @selector(bundleIdentifier)) : nil;

    pid_t pid = DockPidRunningPID(bid);
    if (pid == 0) return origlbl;

    return [origlbl stringByAppendingString:DockPidSuffix(pid)];
}

static void DockPidPrefsChanged(CFNotificationCenterRef center, void *observer,
                                CFStringRef name, const void *object,
                                CFDictionaryRef userInfo) {
    DockPidLoadPrefs();

    // Push the new labels straight onto the tiles we already know about. No
    // relaunch: the whole point of the preference is to change live.
    dispatch_async(dispatch_get_main_queue(), ^{ DockPidRefreshTiles(); });
}

%hook DOCKFileTile

-(NSString*) label {
    // Retrieve the original label if already stored
    NSString* origlbl = objc_getAssociatedObject(self, @selector(label));

    // If not stored, get it from %orig and save it
    if (!origlbl) {
        // Strip first: Dock's copy may already carry a suffix we pushed before this
        // tile object was rebuilt, and capturing that would weld the pid in for good.
        // %orig assigned first: Logos mis-expands it nested inside another call.
        NSString *raw = %orig;
        origlbl = DockPidStripSuffix(raw);
        objc_setAssociatedObject(self, @selector(label), origlbl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (!gTiles) gTiles = [NSHashTable weakObjectsHashTable];
    [gTiles addObject:self];   // so prefs changes and app launch/terminate can reach this tile later

    if (!gEnabled) return origlbl;   // pass the untouched label straight through

    NSMutableString *lbl = [origlbl mutableCopy];
    NSString *bid = [self respondsToSelector:@selector(bundleIdentifier)] ? [self bundleIdentifier] : nil;
    pid_t pid = DockPidRunningPID(bid);
    if (pid > 0) {
        lbl = [[origlbl stringByAppendingString:DockPidSuffix(pid)] mutableCopy];
    }

    // Pushing it back is what makes the label stick -- returning it from the
    // getter alone is not enough, because Dock keeps its own copy.
    [self setLabel:lbl stripAppSuffix:YES];

    return [lbl copy];  // Ensure returning an immutable string
}

-(void) setLabel:(NSString*)arg1 stripAppSuffix:(BOOL)arg2{
    %orig(arg1, arg2);
}

%end

%ctor {
    DockPidLoadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL, DockPidPrefsChanged,
                                    CFSTR("com.doraorak.dockpid/prefsChanged"),
                                    NULL, CFNotificationSuspensionBehaviorCoalesce);
    
    // Live reactive updates when apps launch or terminate
    NSNotificationCenter *wsCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
    [wsCenter addObserverForName:NSWorkspaceDidLaunchApplicationNotification
                          object:nil
                           queue:[NSOperationQueue mainQueue]
                      usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DockPidRefreshTiles();
        });
    }];
    
    // Leave Dock's labels as we found them when it quits, so nothing is left
    // decorated for a Dock that comes back without this tweak loaded -- which is
    // exactly what happens after uninstalling it.
    //
    // A SIGTERM handler would be the wrong tool here even though safeMode does not
    // claim that signal: a handler may only call async-signal-safe functions, and
    // restoring labels means messaging Objective-C objects on the main thread.
    [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillTerminateNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        DockPidRestoreTiles();
    }];

    [wsCenter addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                          object:nil
                           queue:[NSOperationQueue mainQueue]
                      usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DockPidRefreshTiles();
        });
    }];
}

%dtor {
    // Was: kill(getpid(), SIGKILL), to stop a graceful quit leaving decorated
    // labels behind. It worked, but it also meant Dock never got to save ANY
    // state on quit -- rearranging your Dock and then quitting it lost the
    // change. Putting the labels back is the thing that was actually needed.
    DockPidRestoreTiles();
}
