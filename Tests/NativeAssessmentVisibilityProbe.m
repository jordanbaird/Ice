//
//  NativeAssessmentVisibilityProbe.m
//  Ice diagnostic only; not part of the application target.
//
// Runtime-only MenuBarClientCore bridge derived from Thaw's GPLv3 macOS 27
// compatibility implementation, as preserved in Ice/MacOS27AssessmentModeHiding.m.
// This test uses only the menu-bar configuration/assertion API. It does not
// enter whole-computer assessment mode, suspend screen updates, intercept input,
// forward clicks, change permissions or modify any application's preferences.

#import <Cocoa/Cocoa.h>
#import <dlfcn.h>

@interface MBAssessmentModeConfiguration : NSObject
- (instancetype)initWithAllowedSystemItems:(NSArray<NSNumber *> *)systemItems
                  allowedBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers;
@end

@interface MBAssessmentModeAssertion : NSObject
- (void)activateWithConfiguration:(id)configuration
               completionHandler:(void (^)(NSError *error))completionHandler;
- (void)invalidate;
@end

static NSString * const ProbeBundleID = @"local.ice.AssessmentVisibilityProbe";
static NSString * const VictimBundleID = @"local.ice.DynamicStatusItemProbe";
static NSString * const VictimBundlePath = @"/tmp/ice-dynamic-status-probe/IceDynamicProbe.app";

static BOOL ProbeAPIAvailable(void) {
    static BOOL loaded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        loaded = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore",
                        RTLD_NOW | RTLD_LOCAL) != NULL;
    });
    Class configuration = NSClassFromString(@"MBAssessmentModeConfiguration");
    Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
    return loaded &&
        [configuration instancesRespondToSelector:@selector(initWithAllowedSystemItems:allowedBundleIdentifiers:)] &&
        [assertion instancesRespondToSelector:@selector(activateWithConfiguration:completionHandler:)] &&
        [assertion instancesRespondToSelector:@selector(invalidate)];
}

// All activation/invalidation calls run on the main queue. A late completion
// may invalidate again; never assume pending activation completed synchronously.
@interface ProbeAssertionLease : NSObject
@property(nonatomic, strong) MBAssessmentModeAssertion *assertion;
- (void)invalidate;
@end

@implementation ProbeAssertionLease
- (void)invalidate {
    @try {
        [self.assertion invalidate];
    } @catch (NSException *exception) {
        NSLog(@"[AssessmentVisibilityProbe] invalidate exception: %@", exception);
    }
}
@end

@interface AssessmentVisibilityProbe : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *diagnostic;
@property(nonatomic, strong) NSButton *hideButton;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) ProbeAssertionLease *lease;
@property(nonatomic, strong) NSMutableArray *workspaceObservers;
@property(nonatomic) NSUInteger generation;
@end

@implementation AssessmentVisibilityProbe

- (NSRunningApplication *)runningVictim {
    NSArray *matches = [NSRunningApplication runningApplicationsWithBundleIdentifier:VictimBundleID];
    if (matches.count != 1) { return nil; }
    NSRunningApplication *victim = matches.firstObject;
    if (![victim.bundleURL.URLByStandardizingPath.path isEqualToString:VictimBundlePath]) { return nil; }
    return victim;
}

- (void)updateDiagnostic:(NSString *)message {
    self.diagnostic.stringValue = message;
    NSLog(@"[AssessmentVisibilityProbe] generation=%lu %@", (unsigned long)self.generation, message);
}

- (void)refreshAvailability {
    self.hideButton.enabled = ProbeAPIAvailable() && [self runningVictim] != nil;
}

- (void)invalidateCurrent:(NSString *)reason {
    self.generation += 1;
    ProbeAssertionLease *oldLease = self.lease;
    self.lease = nil;
    [oldLease invalidate];
    [self updateDiagnostic:reason];
    [self refreshAvailability];
}

- (void)hideVictim:(id)sender {
    (void)sender;
    // Every activation attempt starts by releasing any previous assertion.
    [self invalidateCurrent:@"Preparing one bounded test; previous assertion released."];
    if (!ProbeAPIAvailable() || ![self runningVictim]) {
        [self updateDiagnostic:@"Inactive: API unavailable or the exact victim app is not running. Hide disabled."];
        return;
    }

    NSMutableSet<NSString *> *allowed = [NSMutableSet set];
    for (NSRunningApplication *application in NSWorkspace.sharedWorkspace.runningApplications) {
        NSString *bundleID = application.bundleIdentifier;
        if (bundleID.length > 0 && ![bundleID isEqualToString:VictimBundleID]) {
            [allowed addObject:bundleID];
        }
    }
    // Preserve every running Apple bundle plus the hosts which may be brought
    // up by native system-item clicks. A new application launch also invalidates
    // the test immediately instead of extending a stale allowlist.
    // Keep the broad AppKit/system-services hosts allowed even if doing so
    // prevents selective hiding of the victim: that is a failed test, not a
    // reason to broaden its scope by removing these native-input protections.
    [allowed addObjectsFromArray:@[
        ProbeBundleID, @"com.jordanbaird.Ice", @"com.apple.MenuBarAgent",
        @"com.apple.appkit.status-items", @"com.apple.MenuBarAgent.systemservices",
        @"com.apple.controlcenter", @"com.apple.systemuiserver",
        @"com.apple.notificationcenterui", @"com.apple.TextInputMenuAgent",
        @"com.apple.loginwindow", @"com.apple.Spotlight"
    ]];
    [allowed removeObject:VictimBundleID];
    NSArray<NSNumber *> *systemItems = @[@0, @1, @2, @3, @4, @5, @6, @7, @8];
    NSArray<NSString *> *bundleIDs = [allowed.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger generation = self.generation;
    ProbeAssertionLease *lease = [ProbeAssertionLease new];
    self.lease = lease;

    __weak AssessmentVisibilityProbe *weakSelf = self;
    __weak ProbeAssertionLease *weakLease = lease;
    // This watchdog never starts a new assertion. It invalidates its exact
    // lease after 45 seconds, even if a newer generation has superseded it.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        [lease invalidate];
        AssessmentVisibilityProbe *owner = weakSelf;
        if (owner && owner.generation == generation && owner.lease == lease) {
            [owner invalidateCurrent:@"REVEALED: 45-second fail-open watchdog expired."];
        }
    });

    @try {
        MBAssessmentModeConfiguration *configuration =
            [[NSClassFromString(@"MBAssessmentModeConfiguration") alloc]
                initWithAllowedSystemItems:systemItems allowedBundleIdentifiers:bundleIDs];
        lease.assertion = [[NSClassFromString(@"MBAssessmentModeAssertion") alloc] init];
        if (!configuration || !lease.assertion) {
            [self invalidateCurrent:@"REVEALED: configuration/assertion creation failed."];
            return;
        }
        [self updateDiagnostic:[NSString stringWithFormat:
            @"ACTIVATING: only %@ excluded; %lu allowed bundles; system IDs 0…8.\n"
             "45-second watchdog armed. Clock/native clicks remain UNVERIFIED.",
             VictimBundleID, (unsigned long)bundleIDs.count]];
        [lease.assertion activateWithConfiguration:configuration completionHandler:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                AssessmentVisibilityProbe *owner = weakSelf;
                ProbeAssertionLease *completedLease = weakLease;
                if (!owner || owner.generation != generation || owner.lease != completedLease) {
                    [completedLease invalidate];
                    return;
                }
                if (error) {
                    [owner invalidateCurrent:[NSString stringWithFormat:@"REVEALED: activation error: %@", error]];
                    return;
                }
                if (![owner runningVictim]) {
                    [owner invalidateCurrent:@"REVEALED: victim disappeared during activation."];
                    return;
                }
                [owner updateDiagnostic:@"ACTIVE (API completion only): inspect victim visibility and native clicks manually.\n"
                                        "No click proxy exists. Reveal/AV/Quit releases the assertion; watchdog set for 45 s."];
            });
        }];
    } @catch (NSException *exception) {
        [self invalidateCurrent:[NSString stringWithFormat:@"REVEALED: activation exception: %@", exception]];
    }
}

- (void)reveal:(id)sender {
    (void)sender;
    [self invalidateCurrent:@"REVEALED: no active test assertion."];
}

- (void)toggleFromOwnButton:(id)sender {
    if (self.lease) { [self reveal:sender]; } else { [self hideVictim:sender]; }
}

- (void)quit:(id)sender {
    (void)sender;
    [self invalidateCurrent:@"REVEALED: quitting probe."];
    [NSApp terminate:nil];
}

- (NSButton *)button:(NSString *)title action:(SEL)action x:(CGFloat)x {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.frame = NSMakeRect(x, 24, 180, 32);
    [self.window.contentView addSubview:button];
    return button;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    // AppKit operations below create/activate only this probe's own window,
    // menu and AV status item. No other app is launched or controlled here.
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 300)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Menu-bar assertion diagnostic — NOT Ice";
    self.window.releasedWhenClosed = NO;
    NSTextField *summary = [NSTextField wrappingLabelWithString:
        @"ISOLATED TEST: only DynamicStatusItemProbe may be hidden.\n"
         "Startup does not activate anything. All running apps and system IDs 0…8 are allowed.\n"
         "Native clock/right-click behavior must be physically checked; abandon if affected."];
    summary.frame = NSMakeRect(24, 198, 592, 76);
    [self.window.contentView addSubview:summary];
    self.diagnostic = [NSTextField wrappingLabelWithString:@""];
    self.diagnostic.frame = NSMakeRect(24, 78, 592, 104);
    self.diagnostic.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    [self.window.contentView addSubview:self.diagnostic];
    self.hideButton = [self button:@"Hide victim (45 s test)" action:@selector(hideVictim:) x:24];
    [self button:@"Reveal now" action:@selector(reveal:) x:230];
    [self button:@"Reveal and Quit" action:@selector(quit:) x:436];
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"AV";
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(toggleFromOwnButton:);
    [self.statusItem.button setAccessibilityIdentifier:@"AssessmentProbe.Toggle"];
    self.statusItem.button.toolTip = @"Independent diagnostic: toggle victim / release assertion";

    self.workspaceObservers = [NSMutableArray array];
    __weak AssessmentVisibilityProbe *weakSelf = self;
    for (NSNotificationName name in @[NSWorkspaceDidLaunchApplicationNotification,
                                     NSWorkspaceDidTerminateApplicationNotification]) {
        id observer = [NSWorkspace.sharedWorkspace.notificationCenter
            addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *event) {
                AssessmentVisibilityProbe *owner = weakSelf;
                if (!owner) { return; }
                if (owner.lease) {
                    [owner invalidateCurrent:[NSString stringWithFormat:
                        @"REVEALED: application lifecycle changed (%@); allowlist must be rebuilt.", event.name]];
                } else {
                    [owner refreshAvailability];
                }
            }];
        [self.workspaceObservers addObject:observer];
    }
    [self invalidateCurrent:@"INACTIVE: no assertion activated. Launch exact victim separately, then manually click Hide."];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activate];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self invalidateCurrent:@"REVEALED: application termination."];
    for (id observer in self.workspaceObservers) {
        [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:observer];
    }
    [NSStatusBar.systemStatusBar removeStatusItem:self.statusItem];
}
@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        application.activationPolicy = NSApplicationActivationPolicyRegular;
        __attribute__((objc_precise_lifetime)) AssessmentVisibilityProbe *delegate = [AssessmentVisibilityProbe new];
        application.delegate = delegate;
        NSMenu *menu = [NSMenu new];
        NSMenuItem *applicationItem = [NSMenuItem new];
        NSMenu *applicationMenu = [NSMenu new];
        NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Reveal and Quit Probe"
                                                   action:@selector(quit:) keyEquivalent:@"q"];
        quit.target = delegate;
        [applicationMenu addItem:quit];
        applicationItem.submenu = applicationMenu;
        [menu addItem:applicationItem];
        application.mainMenu = menu;
        [application run];
    }
    return 0;
}
