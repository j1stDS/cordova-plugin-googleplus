#import "AppDelegate.h"
#import "objc/runtime.h"
#import "GooglePlus.h"

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

    SEL idTokenSelector = NSSelectorFromString(@"idToken");
    if ([user respondsToSelector:idTokenSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id tokenObject = [user performSelector:idTokenSelector];
#pragma clang diagnostic pop

        SEL tokenStringSelector = NSSelectorFromString(@"tokenString");
        if ([tokenObject respondsToSelector:tokenStringSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id tokenString = [tokenObject performSelector:tokenStringSelector];
#pragma clang diagnostic pop
            if ([tokenString isKindOfClass:[NSString class]]) {
                idToken = (NSString *)tokenString;
            }
        } else if ([tokenObject isKindOfClass:[NSString class]]) {
            idToken = (NSString *)tokenObject;
        }
    }

    if (idToken == nil) {
        SEL authenticationSelector = NSSelectorFromString(@"authentication");
        if ([user respondsToSelector:authenticationSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id authentication = [user performSelector:authenticationSelector];
#pragma clang diagnostic pop

            SEL legacyTokenSelector = NSSelectorFromString(@"idToken");
            if ([authentication respondsToSelector:legacyTokenSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id legacyToken = [authentication performSelector:legacyTokenSelector];
#pragma clang diagnostic pop
                if ([legacyToken isKindOfClass:[NSString class]]) {
                    idToken = (NSString *)legacyToken;
                }
            }
        }
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

    SEL modernSignInSelector = NSSelectorFromString(@"signInWithConfiguration:presentingViewController:completion:");
    if ([signIn respondsToSelector:modernSignInSelector]) {
        void (^completion)(id _Nullable, NSError * _Nullable) = ^(id _Nullable signInResult, NSError * _Nullable error) {
            GIDGoogleUser *user = nil;
            if ([signInResult respondsToSelector:@selector(user)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id possibleUser = [signInResult performSelector:@selector(user)];
#pragma clang diagnostic pop
                if ([possibleUser isKindOfClass:[GIDGoogleUser class]]) {
                    user = (GIDGoogleUser *)possibleUser;
                }
            } else if ([signInResult isKindOfClass:[GIDGoogleUser class]]) {
                user = (GIDGoogleUser *)signInResult;
            }

            [self sendPluginResultWithUser:user error:error];
        };

        typedef void (*SignInWithCompletionType)(id, SEL, GIDConfiguration *, UIViewController *, void (^)(id _Nullable, NSError * _Nullable));
        SignInWithCompletionType implementation = (SignInWithCompletionType)[signIn methodForSelector:modernSignInSelector];
        implementation(signIn, modernSignInSelector, config, self.viewController, completion);
    } else {
        [signIn signInWithConfiguration:config presentingViewController:self.viewController callback:^(GIDGoogleUser * _Nullable user, NSError * _Nullable error) {
            [self sendPluginResultWithUser:user error:error];
        }];
    }
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
    GIDSignIn *signIn = GIDSignIn.sharedInstance;

    void (^handleResult)(NSError * _Nullable) = ^(NSError * _Nullable error) {
        if (error == nil) {
            CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"disconnected"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } else {
            CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    };

    SEL modernDisconnectSelector = NSSelectorFromString(@"disconnectWithCompletion:");
    if ([signIn respondsToSelector:modernDisconnectSelector]) {
        typedef void (*DisconnectWithCompletionType)(id, SEL, void (^ _Nullable)(NSError * _Nullable));
        DisconnectWithCompletionType implementation = (DisconnectWithCompletionType)[signIn methodForSelector:modernDisconnectSelector];
        implementation(signIn, modernDisconnectSelector, ^(NSError * _Nullable error) {
            handleResult(error);
        });
    } else {
        [signIn disconnectWithCallback:^(NSError * _Nullable error) {
            handleResult(error);
        }];
    }
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
