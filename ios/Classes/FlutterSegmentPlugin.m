#import "SEGAppsFlyerIntegrationFactory.h"
#import "FlutterSegmentPlugin.h"
#import <Segment/SEGAnalytics.h>
#import <Segment/SEGContext.h>
#import <Segment/SEGMiddleware.h>
#import <Segment_Amplitude/SEGAmplitudeIntegrationFactory.h>

@implementation FlutterSegmentPlugin
// Contents to be appended to the context
static NSDictionary *_appendToContextMiddleware;
static BOOL wasSetupFromFile = NO;

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"flutter_segment_analytics"
      binaryMessenger:[registrar messenger]];
    FlutterSegmentPlugin* instance = [[FlutterSegmentPlugin alloc] init];
    
    SEGAnalyticsConfiguration *configuration = [FlutterSegmentPlugin createConfigFromFile];
    if(configuration) {
        [instance setup:configuration];
        wasSetupFromFile = YES;
    }
    
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)setup:(SEGAnalyticsConfiguration*) configuration  {
    @try {
        // This middleware is responsible for manipulating only the context part of the request,
        // leaving all other fields as is.
        SEGMiddlewareBlock contextMiddleware = ^(SEGContext *_Nonnull context, SEGMiddlewareNext _Nonnull next) {
          // Do not execute if there is nothing to append
          if (_appendToContextMiddleware == nil) {
            next(context);
            return;
          }

          // Avoid overriding the context if there is none to override
          // (see different payload types here: https://github.com/segmentio/analytics-ios/tree/master/Analytics/Classes/Integrations)
          if (![context.payload isKindOfClass:[SEGTrackPayload class]]
            && ![context.payload isKindOfClass:[SEGScreenPayload class]]
            && ![context.payload isKindOfClass:[SEGGroupPayload class]]
            && ![context.payload isKindOfClass:[SEGIdentifyPayload class]]) {
            next(context);
            return;
          }

          next([context
            modify: ^(id<SEGMutableContext> _Nonnull ctx) {
              if (_appendToContextMiddleware == nil) {
                return;
              }

              // do not touch it if no payload is present
              if (ctx.payload == nil) {
                NSLog(@"Cannot update segment context when the current context payload is empty.");
                return;
              }

              @try {
                // We need to perform a deep merge to not lose any sub-dictionary
                // that is already set. [contextToAppend] has precedence over [ctx.payload.context] values
                NSDictionary *combinedContext = [FlutterSegmentPlugin
                  mergeDictionary: ctx.payload.context == nil
                    ? [[NSDictionary alloc] init]
                    : [ctx.payload.context copy]
                  with: _appendToContextMiddleware];

                // SEGPayload does not offer copyWith* methods, so we have to
                // manually test and re-create it for each of its type.
                if ([ctx.payload isKindOfClass:[SEGTrackPayload class]]) {
                  ctx.payload = [[SEGTrackPayload alloc]
                    initWithEvent: ((SEGTrackPayload*)ctx.payload).event
                    properties: ((SEGTrackPayload*)ctx.payload).properties
                    context: combinedContext
                    integrations: ((SEGTrackPayload*)ctx.payload).integrations
                  ];
                } else if ([ctx.payload isKindOfClass:[SEGScreenPayload class]]) {
                  ctx.payload = [[SEGScreenPayload alloc]
                    initWithName: ((SEGScreenPayload*)ctx.payload).name
                    category: ((SEGScreenPayload*)ctx.payload).category
                    properties: ((SEGScreenPayload*)ctx.payload).properties
                    context: combinedContext
                    integrations: ((SEGScreenPayload*)ctx.payload).integrations
                  ];
                } else if ([ctx.payload isKindOfClass:[SEGGroupPayload class]]) {
                  ctx.payload = [[SEGGroupPayload alloc]
                    initWithGroupId: ((SEGGroupPayload*)ctx.payload).groupId
                    traits: ((SEGGroupPayload*)ctx.payload).traits
                    context: combinedContext
                    integrations: ((SEGGroupPayload*)ctx.payload).integrations
                  ];
                } else if ([ctx.payload isKindOfClass:[SEGIdentifyPayload class]]) {
                  ctx.payload = [[SEGIdentifyPayload alloc]
                    initWithUserId: ((SEGIdentifyPayload*)ctx.payload).userId
                    anonymousId: ((SEGIdentifyPayload*)ctx.payload).anonymousId
                    traits: ((SEGIdentifyPayload*)ctx.payload).traits
                    context: combinedContext
                    integrations: ((SEGIdentifyPayload*)ctx.payload).integrations
                  ];
                }
              }
              @catch (NSException *exception) {
                NSLog(@"Could not update segment context: %@", [exception reason]);
              }
            }]
          );
        };
        
        configuration.sourceMiddleware = @[
          [[SEGBlockMiddleware alloc] initWithBlock:contextMiddleware]
        ];
        [SEGAnalytics setupWithConfiguration:configuration];
    }
    @catch (NSException *exception) {
      NSLog(@"%@", [exception reason]);
    }
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"config" isEqualToString:call.method] && !wasSetupFromFile) {
    [self config:call result:result];
  } else if ([@"identify" isEqualToString:call.method]) {
    [self identify:call result:result];
  } else if ([@"track" isEqualToString:call.method]) {
    [self track:call result:result];
  } else if ([@"screen" isEqualToString:call.method]) {
    [self screen:call result:result];
  } else if ([@"group" isEqualToString:call.method]) {
    [self group:call result:result];
  } else if ([@"alias" isEqualToString:call.method]) {
    [self alias:call result:result];
  } else if ([@"getAnonymousId" isEqualToString:call.method]) {
    [self anonymousId:result];
  } else if ([@"reset" isEqualToString:call.method]) {
    [self reset:result];
  } else if ([@"disable" isEqualToString:call.method]) {
    [self disable:result];
  } else if ([@"enable" isEqualToString:call.method]) {
    [self enable:result];
  } else if ([@"flush" isEqualToString:call.method]) {
    [self flush:result];
  } else if ([@"debug" isEqualToString:call.method]) {
    [self debug:call result:result];
  } else if ([@"setContext" isEqualToString:call.method]) {
    [self setContext:call result:result];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)config:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    NSDictionary *options = call.arguments[@"options"];
    SEGAnalyticsConfiguration *configuration = [FlutterSegmentPlugin createConfigFromDict:options];
    [self setup:configuration];
    if(!wasSetupFromFile) {
        [self trackInstalledEvent];
    }
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError
      errorWithCode:@"FlutterSegmentException"
      message:[exception reason]
      details: [NSThread  callStackSymbols].description]);
  }

}

- (void)setContext:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    NSDictionary *context = call.arguments[@"context"];
    _appendToContextMiddleware = context;
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError
      errorWithCode:@"FlutterSegmentException"
      message:[exception reason]
      details: [NSThread  callStackSymbols].description]);
  }

}

- (void)identify:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    NSString *userId = call.arguments[@"userId"];
    NSDictionary *traits = call.arguments[@"traits"];
    NSDictionary *options = call.arguments[@"options"];

    userId = [userId isEqual:[NSNull null]]? nil: userId;

    [[SEGAnalytics sharedAnalytics] identify: userId
                      traits: traits
                     options: options];

    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError
      errorWithCode:@"FlutterSegmentException"
      message:[exception reason]
      details: @"[NSThread  callStackSymbols].description"]);
  }
}

- (void)track:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    NSString *eventName = call.arguments[@"eventName"];
    NSDictionary *properties = call.arguments[@"properties"];
    NSDictionary *options = call.arguments[@"options"];
    [[SEGAnalytics sharedAnalytics] track: eventName
                    properties: properties
                    options: options];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError
      errorWithCode:@"FlutterSegmentException"
      message:[exception reason]
      details: [NSThread  callStackSymbols].description]);
  }
}

- (void)screen:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    NSString *screenName = call.arguments[@"screenName"];
    NSDictionary *properties = call.arguments[@"properties"];
    NSDictionary *options = call.arguments[@"options"];
    [[SEGAnalytics sharedAnalytics] screen: screenName
                  properties: properties
                     options: options];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError
      errorWithCode:@"FlutterSegmentException"
      message:[exception reason]
      details: [NSThread  callStackSymbols].description]);
  }
}

- (void)group:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    NSString *groupId = call.arguments[@"groupId"];
    NSDictionary *traits = call.arguments[@"traits"];
    NSDictionary *options = call.arguments[@"options"];
    [[SEGAnalytics sharedAnalytics] group: groupId
                     traits: traits
                    options: options];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FlutterSegmentException"
      message:[exception reason]
      details: [NSThread  callStackSymbols].description]);
  }
}

- (void)alias:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    NSString *alias = call.arguments[@"alias"];
    NSDictionary *options = call.arguments[@"options"];
    [[SEGAnalytics sharedAnalytics] alias: alias
                    options: options];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FlutterSegmentException"
      message:[exception reason]
      details: [NSThread  callStackSymbols].description]);
  }
}

- (void)anonymousId:(FlutterResult)result {
  @try {
    NSString *anonymousId = [[SEGAnalytics sharedAnalytics] getAnonymousId];
    result(anonymousId);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FlutterSegmentException"
      message:[exception reason]
      details: [NSThread  callStackSymbols].description]);
  }
}

- (void)reset:(FlutterResult)result {
  @try {
    [[SEGAnalytics sharedAnalytics] reset];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FlutterSegmentException"
      message:[exception reason]
      details: [NSThread  callStackSymbols].description]);
  }
}

- (void)disable:(FlutterResult)result {
  @try {
    [[SEGAnalytics sharedAnalytics] disable];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FlutterSegmentException"
      message:[exception reason]
      details: [NSThread  callStackSymbols].description]);
  }
}

- (void)enable:(FlutterResult)result {
  @try {
    [[SEGAnalytics sharedAnalytics] enable];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FlutterSegmentException"
      message:[exception reason]
      details: [NSThread  callStackSymbols].description]);
  }
}

- (void)flush:(FlutterResult)result {
  @try {
    [[SEGAnalytics sharedAnalytics] flush];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FlutterSegmentException"
      message:[exception reason]
      details: [NSThread  callStackSymbols].description]);
  }
}

- (void)debug:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    BOOL enabled = call.arguments[@"debug"];
    [SEGAnalytics debug: enabled];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FlutterSegmentException"
      message:[exception reason]
      details: [NSThread  callStackSymbols].description]);
  }
}

+ (SEGAnalyticsConfiguration*)createConfigFromFile {
    NSString *path = [[NSBundle mainBundle] pathForResource: @"Info" ofType: @"plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile: path];
    NSString *writeKey = [dict objectForKey: @"com.claimsforce.segment.WRITE_KEY"];
    BOOL trackApplicationLifecycleEvents = [[dict objectForKey: @"com.claimsforce.segment.TRACK_APPLICATION_LIFECYCLE_EVENTS"] boolValue];
    BOOL isAmplitudeIntegrationEnabled = [[dict objectForKey: @"com.claimsforce.segment.ENABLE_AMPLITUDE_INTEGRATION"] boolValue];
    if(!writeKey) {
        return nil;
    }
    SEGAnalyticsConfiguration *configuration = [SEGAnalyticsConfiguration configurationWithWriteKey:writeKey];
    configuration.trackApplicationLifecycleEvents = trackApplicationLifecycleEvents;

    if (isAmplitudeIntegrationEnabled) {
      [configuration use:[SEGAmplitudeIntegrationFactory instance]];
    }

    return configuration;
}

+ (SEGAnalyticsConfiguration*)createConfigFromDict:(NSDictionary*) dict {
    NSString *writeKey = [dict objectForKey: @"writeKey"];
    BOOL trackApplicationLifecycleEvents = [[dict objectForKey: @"trackApplicationLifecycleEvents"] boolValue];
    BOOL isAmplitudeIntegrationEnabled = [[dict objectForKey: @"amplitudeIntegrationEnabled"] boolValue];
    BOOL isAppsflyerIntegrationEnabled = [[dict objectForKey: @"appsflyerIntegrationEnabled"] boolValue];
    SEGAnalyticsConfiguration *configuration = [SEGAnalyticsConfiguration configurationWithWriteKey:writeKey];
    configuration.trackApplicationLifecycleEvents = trackApplicationLifecycleEvents;

    if (isAmplitudeIntegrationEnabled) {
      [configuration use:[SEGAmplitudeIntegrationFactory instance]];
    }

    if (isAppsflyerIntegrationEnabled) {
      [configuration use:[SEGAppsFlyerIntegrationFactory instance]];
    }

    return configuration;
}

+ (NSDictionary *) mergeDictionary: (NSDictionary *) first with: (NSDictionary *) second {
  NSMutableDictionary *result = [first mutableCopy];
  [second enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
    id contained = [result objectForKey:key];
    if (!contained) {
      [result setObject:value forKey:key];
    } else if ([value isKindOfClass:[NSDictionary class]]) {
      [result setObject:[FlutterSegmentPlugin mergeDictionary:result[key] with:value]
        forKey:key];
    }
  }];
  return result;
}


#pragma mark Work around for Firing Installed / Updated events
// See https://github.com/segmentio/analytics-ios/blob/fc64997865619f73bbab196c164f7845a13da110/Segment/Classes/SEGAnalytics.m#L163

NSString *const SEGVersionKey = @"SEGVersionKey";
NSString *const SEGBuildKeyV1 = @"SEGBuildKey";
NSString *const SEGBuildKeyV2 = @"SEGBuildKeyV2";

- (void)trackInstalledEvent
{
    // Previously SEGBuildKey was stored an integer. This was incorrect because the CFBundleVersion
    // can be a string. This migrates SEGBuildKey to be stored as a string.
    NSInteger previousBuildV1 = [[NSUserDefaults standardUserDefaults] integerForKey:SEGBuildKeyV1];
    if (previousBuildV1) {
        [[NSUserDefaults standardUserDefaults] setObject:[@(previousBuildV1) stringValue] forKey:SEGBuildKeyV2];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:SEGBuildKeyV1];
    }

    NSString *previousVersion = [[NSUserDefaults standardUserDefaults] stringForKey:SEGVersionKey];
    NSString *previousBuildV2 = [[NSUserDefaults standardUserDefaults] stringForKey:SEGBuildKeyV2];

    NSString *currentVersion = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"];
    NSString *currentBuild = [[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"];

    if (!previousBuildV2) {
        [[SEGAnalytics sharedAnalytics] track:@"Application Installed" properties:@{
            @"version" : currentVersion ?: @"",
            @"build" : currentBuild ?: @"",
        }];
    } else if (![currentBuild isEqualToString:previousBuildV2]) {
        [[SEGAnalytics sharedAnalytics] track:@"Application Updated" properties:@{
            @"previous_version" : previousVersion ?: @"",
            @"previous_build" : previousBuildV2 ?: @"",
            @"version" : currentVersion ?: @"",
            @"build" : currentBuild ?: @"",
        }];
    }

    [[SEGAnalytics sharedAnalytics] track:@"Application Opened" properties:@{
        @"from_background" : @NO,
        @"version" : currentVersion ?: @"",
        @"build" : currentBuild ?: @"",
        @"referring_application" : @"",
        @"url" : @"",
    }];

    [[NSUserDefaults standardUserDefaults] setObject:currentVersion forKey:SEGVersionKey];
    [[NSUserDefaults standardUserDefaults] setObject:currentBuild forKey:SEGBuildKeyV2];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
