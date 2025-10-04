#import "AppDelegate.h"
#import "objc/runtime.h"
#import "GooglePlus.h"

#if __has_include(<GoogleSignIn/GIDSignInResult.h>)
#import <GoogleSignIn/GIDSignInResult.h>
#endif

@implementation GooglePlus

- (void)pluginInitialize
{
    NSLog(@"GooglePlus pluginInitizalize");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOpenURL:) name:CDVPluginHandleOpenURLNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOpenURLWithAppSourceAndAnnotation:) name:CDVPluginHandleOpenURLWithAppSourceAndAnnotationNotification object:nil];
}

- (void)handleOpenURL:(NSNotification*)notification
{
    // no need to handle this handler, we dont have an sourceApplication here, which is required by GIDSignIn handleURL
}

- (void)handleOpenURLWithAppSourceAndAnnotation:(NSNotification*)notification
{
    NSMutableDictionary * options = [notification object];

    NSURL* url = options[@"url"];

    NSString* possibleReversedClientId = [url.absoluteString componentsSeparatedByString:@":"].firstObject;

    if ([possibleReversedClientId isEqualToString:self.getreversedClientId] && self.isSigningIn) {
        self.isSigningIn = NO;
        [GIDSignIn.sharedInstance handleURL:url];
    }
}


- (NSDictionary *)dictionaryForUser:(GIDGoogleUser *)user idToken:(NSString *)idToken
{
    NSString *email = user.profile.email;
    NSString *userId = user.userID;
    NSURL *imageUrl = [user.profile imageURLWithDimension:120]; // TODO pass in img size as param, and try to sync with Android

    return @{
        @"email"      : email ?: [NSNull null],
        @"userId"     : userId ?: [NSNull null],
        @"idToken"    : idToken ?: [NSNull null],
        @"displayName": user.profile.name       ? : [NSNull null],
        @"givenName"  : user.profile.givenName  ? : [NSNull null],
        @"familyName" : user.profile.familyName ? : [NSNull null],
        @"imageUrl"   : imageUrl ? imageUrl.absoluteString : [NSNull null],
    };
}

- (void)sendPluginResultWithUser:(GIDGoogleUser *)user
                           error:(NSError *)error
{
    if (error) {
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self->_callbackId];
        return;
    }

    if (!user) {
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"User information not available."];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self->_callbackId];
        return;
    }

    NSString *idToken = nil;

#if __has_include(<GoogleSignIn/GIDSignInResult.h>)
    if ([user respondsToSelector:@selector(idToken)]) {
        idToken = user.idToken.tokenString;
    }
#endif

    if (idToken == nil && [user respondsToSelector:@selector(authentication)]) {
        idToken = user.authentication.idToken;
    }

    NSDictionary *result = [self dictionaryForUser:user idToken:idToken];

    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self->_callbackId];
}

- (void) login:(CDVInvokedUrlCommand*)command {
    _callbackId = command.callbackId;
    NSDictionary* options = command.arguments[0];
    NSString *reversedClientId = [self getreversedClientId];

    if (reversedClientId == nil) {
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Could not find REVERSED_CLIENT_ID url scheme in app .plist"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
        return;
    }

    NSString *clientId = [self reverseUrlScheme:reversedClientId];

    NSString* serverClientId = options[@"webClientId"];
    BOOL offline = [options[@"offline"] boolValue];

    GIDConfiguration *config = nil;

    if (serverClientId != nil && offline) {
        config = [[GIDConfiguration alloc] initWithClientID:clientId serverClientID:serverClientId];
    } else {
        config = [[GIDConfiguration alloc] initWithClientID:clientId];
    }

    GIDSignIn *signIn = GIDSignIn.sharedInstance;

#if __has_include(<GoogleSignIn/GIDSignInResult.h>)
    [signIn signInWithConfiguration:config presentingViewController:self.viewController completion:^(GIDSignInResult * _Nullable signInResult, NSError * _Nullable error) {
        [self sendPluginResultWithUser:signInResult.user error:error];
    }];
#else
    [signIn signInWithConfiguration:config presentingViewController:self.viewController callback:^(GIDGoogleUser * _Nullable user, NSError * _Nullable error) {
        [self sendPluginResultWithUser:user error:error];
    }];
#endif
}


- (NSString*) reverseUrlScheme:(NSString*)scheme {
    NSArray* originalArray = [scheme componentsSeparatedByString:@"."];
    NSArray* reversedArray = [[originalArray reverseObjectEnumerator] allObjects];
    NSString* reversedString = [reversedArray componentsJoinedByString:@"."];
    return reversedString;
}

- (NSString*) getreversedClientId {
    NSArray* URLTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleURLTypes"];

    if (URLTypes != nil) {
        for (NSDictionary* dict in URLTypes) {
            NSString *urlName = dict[@"CFBundleURLName"];
            if ([urlName isEqualToString:@"REVERSED_CLIENT_ID"]) {
                NSArray* URLSchemes = dict[@"CFBundleURLSchemes"];
                if (URLSchemes != nil) {
                    return URLSchemes[0];
                }
            }
        }
    }
    return nil;
}

- (void) logout:(CDVInvokedUrlCommand*)command {
    [GIDSignIn.sharedInstance signOut];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"logged out"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) disconnect:(CDVInvokedUrlCommand*)command {
    [GIDSignIn.sharedInstance disconnectWithCallback:^(NSError * _Nullable error) {
        if(error == nil) {
            CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"disconnected"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } else {
            CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }];
}

- (void) isSignedIn:(CDVInvokedUrlCommand*)command {
    bool isSignedIn = [GIDSignIn.sharedInstance currentUser] != nil;
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:isSignedIn];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

#pragma mark - GIDSignInDelegate
- (void)signIn:(GIDSignIn *)signIn didSignInForUser:(GIDGoogleUser *)user withError:(NSError *)error {

}

- (void)signIn:(GIDSignIn *)signIn presentViewController:(UIViewController *)viewController {
    self.isSigningIn = YES;
    [self.viewController presentViewController:viewController animated:YES completion:nil];
}

- (void)signIn:(GIDSignIn *)signIn dismissViewController:(UIViewController *)viewController {
    [self.viewController dismissViewControllerAnimated:YES completion:nil];
}

@end
