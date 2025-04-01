#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Interfaces.h"
#import <objc/runtime.h>

%config(generator=internal);

%hook DOCKFileTile


-(NSString*) label {
    // Retrieve the original label if already stored
    NSString* origlbl = objc_getAssociatedObject(self, @selector(label));
    
    // If not stored, get it from %orig and save it
    if (!origlbl) {
        origlbl = %orig;
        objc_setAssociatedObject(self, @selector(label), origlbl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (!origlbl) return nil;  // Handle nil case safely

    NSMutableString* lbl = [origlbl mutableCopy];
    NSArray* arr = [NSRunningApplication runningApplicationsWithBundleIdentifier:[self bundleIdentifier]];
    
    NSLog(@"[dockpid] arrcount : %lu", arr.count);

    if (arr.count > 0) {
        lbl = [[origlbl stringByAppendingFormat:@" (%d)", [[arr objectAtIndex:0] processIdentifier]] mutableCopy];
    }

    NSLog(@"[dockpid] get label : %@", lbl);
    [self setLabel:lbl stripAppSuffix:YES];

    return [lbl copy];  // Ensure returning an immutable string
}


-(void) setLabel:(NSString*)arg1 stripAppSuffix:(BOOL)arg2{
    
    NSLog(@"[dockpid] set label : %@", arg1);
    %orig(arg1, arg2);

}

%end

%dtor{ //fixes the issue where rebooting or quitting (not force quit) the dock.app causes pid additions to get stuck on the name labels permamently
    pid_t pid = getpid(); 
    kill(pid, SIGKILL); //idk if this has side effects
}