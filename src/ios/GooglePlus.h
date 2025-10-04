#import <Cordova/CDVPlugin.h>
// Rely on the umbrella GoogleSignIn header instead of importing GIDAuthentication directly.
#import <GoogleSignIn/GoogleSignIn.h>

@interface GooglePlus : CDVPlugin

@property (nonatomic, copy) NSString* callbackId;
@property (nonatomic, assign) BOOL isSigningIn;

- (void) login:(CDVInvokedUrlCommand*)command;
- (void) logout:(CDVInvokedUrlCommand*)command;
- (void) disconnect:(CDVInvokedUrlCommand*)command;

@end
