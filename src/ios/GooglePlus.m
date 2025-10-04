#import "AppDelegate.h"
#import "objc/message.h"
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
        [[GIDSignIn sharedInstance] handleURL:url];
    }
}

// If this returns false, you better not call the login function because of likely app rejection by Apple,
// see https://code.google.com/p/google-plus-platform/issues/detail?id=900
// Update: should be fine since we use the GoogleSignIn framework instead of the GooglePlus framework
- (void) isAvailable:(CDVInvokedUrlCommand*)command {
  CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) login:(CDVInvokedUrlCommand*)command {
    [self startSignInWithCommand:command silently:NO];
}

/** Get Google Sign-In object
 @date July 19, 2015
 */
- (void) trySilentLogin:(CDVInvokedUrlCommand*)command {
    [self startSignInWithCommand:command silently:YES];
}

/** Get Google Sign-In object
 @date July 19, 2015
 @date updated March 15, 2015 (@author PointSource,LLC)
 */
- (GIDSignIn*) getGIDSignInObject:(CDVInvokedUrlCommand*)command {
    _callbackId = command.callbackId;
    NSDictionary* options = command.arguments.count > 0 ? command.arguments[0] : @{};
    NSString *reversedClientId = [self getreversedClientId];

    if (reversedClientId == nil) {
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Could not find REVERSED_CLIENT_ID url scheme in app .plist"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
        return nil;
    }

    NSString *clientId = [self reverseUrlScheme:reversedClientId];

    NSString* scopesString = options[@"scopes"];
    NSString* serverClientId = options[@"webClientId"];
    NSString *loginHint = options[@"loginHint"];
    BOOL offline = [options[@"offline"] boolValue];
    NSString* hostedDomain = options[@"hostedDomain"];

    GIDSignIn *signIn = [GIDSignIn sharedInstance];

    if ([signIn respondsToSelector:@selector(setClientID:)]) {
        [signIn setClientID:clientId];
    }

    if ([signIn respondsToSelector:@selector(setServerClientID:)] && serverClientId != nil && offline) {
        [signIn setServerClientID:serverClientId];
    }

    if (hostedDomain != nil && [signIn respondsToSelector:@selector(setHostedDomain:)]) {
        [signIn setHostedDomain:hostedDomain];
    }

    if ([signIn respondsToSelector:@selector(setLoginHint:)]) {
        [signIn setLoginHint:loginHint];
    }

    if ([signIn respondsToSelector:@selector(setPresentingViewController:)]) {
        [signIn setPresentingViewController:self.viewController];
    }

    if ([signIn respondsToSelector:@selector(setDelegate:)]) {
        [signIn setDelegate:self];
    }

    if (scopesString != nil) {
        NSArray* scopes = [scopesString componentsSeparatedByString:@" "];
        if ([signIn respondsToSelector:@selector(setScopes:)]) {
            [signIn setScopes:scopes];
        }
    }

    [self updateConfigurationWithSignIn:signIn clientId:clientId serverClientId:(serverClientId != nil && offline) ? serverClientId : nil hostedDomain:hostedDomain];

    return signIn;
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
  [[GIDSignIn sharedInstance] signOut];
  CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"logged out"];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) disconnect:(CDVInvokedUrlCommand*)command {
    GIDSignIn *signIn = [GIDSignIn sharedInstance];
    SEL disconnectSelector = NSSelectorFromString(@"disconnectWithCompletion:");

    if ([signIn respondsToSelector:disconnectSelector]) {
        void (^completionBlock)(NSError * _Nullable) = ^(NSError * _Nullable error) {
            if (error) {
                CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            } else {
                CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"disconnected"];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }
        };

        void (^completionCopy)(NSError * _Nullable) = [completionBlock copy];
        ((void (*)(id, SEL, void (^)(NSError * _Nullable)))[signIn methodForSelector:disconnectSelector])(signIn, disconnectSelector, completionCopy);
    } else {
        [signIn disconnect];
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"disconnected"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void) share_unused:(CDVInvokedUrlCommand*)command {
  // for a rainy day.. see for a (limited) example https://github.com/vleango/GooglePlus-PhoneGap-iOS/blob/master/src/ios/GPlus.m
}

#pragma mark - GIDSignInDelegate
/** Google Sign-In SDK
 @date July 19, 2015
 */
- (void)signIn:(GIDSignIn *)signIn didSignInForUser:(GIDGoogleUser *)user withError:(NSError *)error {
    [self handleSignInForUser:user error:error];
}

/** Google Sign-In SDK
 @date July 19, 2015
 */
- (void)signIn:(GIDSignIn *)signIn presentViewController:(UIViewController *)viewController {
    self.isSigningIn = YES;
    [self.viewController presentViewController:viewController animated:YES completion:nil];
}

/** Google Sign-In SDK
 @date July 19, 2015
 */
- (void)signIn:(GIDSignIn *)signIn dismissViewController:(UIViewController *)viewController {
    [self.viewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)startSignInWithCommand:(CDVInvokedUrlCommand*)command silently:(BOOL)silently {
    GIDSignIn *signIn = [self getGIDSignInObject:command];

    if (signIn == nil) {
        return;
    }

    NSDictionary* options = command.arguments.count > 0 ? command.arguments[0] : @{};
    NSString *loginHint = options[@"loginHint"];

    if (!silently) {
        self.isSigningIn = YES;
    }

    if (silently) {
        SEL restoreSelector = NSSelectorFromString(@"restorePreviousSignInWithCompletion:");
        if ([signIn respondsToSelector:restoreSelector]) {
            void (^completionBlock)(id, NSError *) = ^(id result, NSError *error) {
                GIDGoogleUser *user = [self extractUserFromResult:result];
                [self handleSignInForUser:user error:error];
            };

            void (^completionCopy)(id, NSError *) = [completionBlock copy];
            ((void (*)(id, SEL, void (^)(id, NSError *)))[signIn methodForSelector:restoreSelector])(signIn, restoreSelector, completionCopy);
        } else {
            [signIn restorePreviousSignIn];
        }
        return;
    }

    SEL hintSelector = NSSelectorFromString(@"signInWithConfiguration:presentingViewController:hint:completion:");
    SEL completionSelector = NSSelectorFromString(@"signInWithConfiguration:presentingViewController:completion:");
    SEL callbackSelector = NSSelectorFromString(@"signInWithConfiguration:presentingViewController:callback:");

    id configuration = [self configurationForSignIn:signIn];
    if (!configuration) {
        configuration = self.currentSignInConfiguration;
    }
    UIViewController *presentingController = self.viewController;

    void (^completionBlock)(id, NSError *) = ^(id result, NSError *error) {
        GIDGoogleUser *user = [self extractUserFromResult:result];
        [self handleSignInForUser:user error:error];
    };

    void (^completionCopy)(id, NSError *) = [completionBlock copy];

    if (configuration && [signIn respondsToSelector:hintSelector]) {
        ((void (*)(id, SEL, id, UIViewController *, NSString *, void (^)(id, NSError *)))[signIn methodForSelector:hintSelector])(signIn, hintSelector, configuration, presentingController, loginHint, completionCopy);
        return;
    }

    if (configuration && [signIn respondsToSelector:completionSelector]) {
        ((void (*)(id, SEL, id, UIViewController *, void (^)(id, NSError *)))[signIn methodForSelector:completionSelector])(signIn, completionSelector, configuration, presentingController, completionCopy);
        return;
    }

    if (configuration && [signIn respondsToSelector:callbackSelector]) {
        ((void (*)(id, SEL, id, UIViewController *, void (^)(id, NSError *)))[signIn methodForSelector:callbackSelector])(signIn, callbackSelector, configuration, presentingController, completionCopy);
        return;
    }

    [signIn signIn];
}

- (void)updateConfigurationWithSignIn:(GIDSignIn *)signIn clientId:(NSString *)clientId serverClientId:(NSString *)serverClientId hostedDomain:(NSString *)hostedDomain {
    Class configurationClass = NSClassFromString(@"GIDConfiguration");
    if (!configurationClass) {
        self.currentSignInConfiguration = nil;
        return;
    }

    id configuration = [configurationClass alloc];

    SEL initWithClientIDServerSelector = NSSelectorFromString(@"initWithClientID:serverClientID:");
    SEL initWithClientIDSelector = NSSelectorFromString(@"initWithClientID:");

    if (serverClientId != nil && [configuration respondsToSelector:initWithClientIDServerSelector]) {
        configuration = ((id (*)(id, SEL, NSString *, NSString *))objc_msgSend)(configuration, initWithClientIDServerSelector, clientId, serverClientId);
    } else if ([configuration respondsToSelector:initWithClientIDSelector]) {
        configuration = ((id (*)(id, SEL, NSString *))objc_msgSend)(configuration, initWithClientIDSelector, clientId);
    } else {
        configuration = nil;
    }

    if (!configuration) {
        self.currentSignInConfiguration = nil;
        return;
    }

    SEL setHostedDomainSelector = NSSelectorFromString(@"setHostedDomain:");
    if (hostedDomain != nil && [configuration respondsToSelector:setHostedDomainSelector]) {
        ((void (*)(id, SEL, NSString *))objc_msgSend)(configuration, setHostedDomainSelector, hostedDomain);
    }

    SEL setConfigurationSelector = NSSelectorFromString(@"setConfiguration:");
    if ([signIn respondsToSelector:setConfigurationSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(signIn, setConfigurationSelector, configuration);
    }

    self.currentSignInConfiguration = configuration;
}

- (id)configurationForSignIn:(GIDSignIn *)signIn {
    SEL configurationSelector = NSSelectorFromString(@"configuration");
    if ([signIn respondsToSelector:configurationSelector]) {
        return ((id (*)(id, SEL))objc_msgSend)(signIn, configurationSelector);
    }
    return nil;
}

- (GIDGoogleUser *)extractUserFromResult:(id)result {
    if (!result) {
        return nil;
    }

    if ([result isKindOfClass:[GIDGoogleUser class]]) {
        return (GIDGoogleUser *)result;
    }

    SEL userSelector = NSSelectorFromString(@"user");
    if ([result respondsToSelector:userSelector]) {
        return ((GIDGoogleUser * (*)(id, SEL))objc_msgSend)(result, userSelector);
    }

    return nil;
}

- (void)handleSignInForUser:(GIDGoogleUser *)user error:(NSError *)error {
    if (error) {
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
        self.isSigningIn = NO;
        return;
    }

    if (!user) {
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No user returned from Google Sign-In."];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
        self.isSigningIn = NO;
        return;
    }

    NSString *email = user.profile.email;
    NSString *idToken = [self tokenStringFromUser:user selectorName:@"idToken"];
    NSString *accessToken = [self tokenStringFromUser:user selectorName:@"accessToken"];
    NSString *refreshToken = [self tokenStringFromUser:user selectorName:@"refreshToken"];
    NSString *userId = user.userID;
    NSString *serverAuthCode = user.serverAuthCode != nil ? user.serverAuthCode : @"";
    NSURL *imageUrl = [user.profile imageURLWithDimension:120];

    NSDictionary *result = @{
        @"email" : email ? : [NSNull null],
        @"idToken" : idToken ? : [NSNull null],
        @"serverAuthCode" : serverAuthCode ? : [NSNull null],
        @"accessToken" : accessToken ? : [NSNull null],
        @"refreshToken" : refreshToken ? : [NSNull null],
        @"userId" : userId ? : [NSNull null],
        @"displayName" : user.profile.name ? : [NSNull null],
        @"givenName" : user.profile.givenName ? : [NSNull null],
        @"familyName" : user.profile.familyName ? : [NSNull null],
        @"imageUrl" : imageUrl ? imageUrl.absoluteString : [NSNull null]
    };

    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
    self.isSigningIn = NO;
}

- (NSString *)tokenStringFromUser:(GIDGoogleUser *)user selectorName:(NSString *)selectorName {
    if (!user) {
        return nil;
    }

    SEL directSelector = NSSelectorFromString(selectorName);
    SEL tokenStringSelector = NSSelectorFromString(@"tokenString");

    if ([user respondsToSelector:directSelector]) {
        id tokenObject = ((id (*)(id, SEL))objc_msgSend)(user, directSelector);
        if ([tokenObject isKindOfClass:[NSString class]]) {
            return (NSString *)tokenObject;
        }
        if ([tokenObject respondsToSelector:tokenStringSelector]) {
            id tokenString = ((id (*)(id, SEL))objc_msgSend)(tokenObject, tokenStringSelector);
            if ([tokenString isKindOfClass:[NSString class]]) {
                return (NSString *)tokenString;
            }
        }
    }

    SEL authenticationSelector = NSSelectorFromString(@"authentication");
    if ([user respondsToSelector:authenticationSelector]) {
        id authentication = ((id (*)(id, SEL))objc_msgSend)(user, authenticationSelector);
        if ([authentication respondsToSelector:directSelector]) {
            id tokenObject = ((id (*)(id, SEL))objc_msgSend)(authentication, directSelector);
            if ([tokenObject isKindOfClass:[NSString class]]) {
                return (NSString *)tokenObject;
            }
        }
    }

    return nil;
}

@end
