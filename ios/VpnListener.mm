#import "VpnListener.h"
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>
#import <netdb.h>
#import <sys/socket.h>
#import <TargetConditionals.h>
#import <TargetConditionals.h>

@implementation VpnListener {
  dispatch_source_t _timer;
  BOOL _hasListeners;
  BOOL _eventEmitterReady;
  NSDictionary *_pendingInitialSnapshot;
  NSDictionary *_lastEmittedSnapshot;
}

RCT_EXPORT_MODULE()

#pragma mark - Init


- (instancetype)init
{
  if ((self = [super init])) {
    _hasListeners = NO;
    _timer = NULL;
    _eventEmitterReady = NO;
    _pendingInitialSnapshot = nil;
    _lastEmittedSnapshot = nil;
    [self startTimerIfNeeded];
    // Precompute initial snapshot; will be emitted once the emitter is ready and JS subscribed
    _pendingInitialSnapshot = [self buildVpnInfo];
  }
  return self;
}

#pragma mark - TurboModule plumbing

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeVpnListenerSpecJSI>(params);
}

- (void)dealloc {
  // Cleanup background timer
  [self stopTimer];
}

// Called by the runtime when the JS event emitter is ready. We then flush
// any pending initial snapshot to JS on the main thread.
- (void)setEventEmitterCallback:(EventEmitterCallbackWrapper *)eventEmitterCallbackWrapper
{
  [super setEventEmitterCallback:eventEmitterCallbackWrapper];
  _eventEmitterReady = YES;
  if (_pendingInitialSnapshot != nil) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self emitIfMeaningful:_pendingInitialSnapshot];
    });
    _pendingInitialSnapshot = nil;
  }
}

#pragma mark - Public API (Promises)

// Promise<boolean>
// Returns whether a VPN-like interface is currently up according to heuristics.
- (void)isVpnActive:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject
{
  resolve(@([self isVpnUp]));
}

// Promise<map>
// Returns a detailed snapshot (active/type/interface/localAddress/timestamp/platform).
- (void)getVpnInfo:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject
{
  resolve([self buildVpnInfo]);
}

#pragma mark - Event wiring (NativeEventEmitter semantics)

// JS subscribed. Start timer if needed and emit an initial snapshot when ready.
- (void)addListener:(NSString *)eventName
{
  _hasListeners = YES;
  [self startTimerIfNeeded];
  NSDictionary *snapshot = [self buildVpnInfo];
  if (_eventEmitterReady) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self emitIfMeaningful:snapshot];
    });
  } else {
    _pendingInitialSnapshot = snapshot;
  }
}

- (void)removeListeners:(double)count
{
  _hasListeners = NO;
  // Keep monitor running; it's lightweight. If you want to stop, uncomment:
  // [self stopMonitor];
}

#pragma mark - Timer-based updates

// Starts a periodic GCD timer (~2s) to sample current VPN info and emit
// to JS if the emitter is ready and a meaningful change is detected.
- (void)startTimerIfNeeded
{
  if (_timer != NULL) return;
  dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
  _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
  if (_timer == NULL) return;
  uint64_t intervalNs = (uint64_t)(2.0 * NSEC_PER_SEC);
  dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, intervalNs), intervalNs, (uint64_t)(0.2 * NSEC_PER_SEC));
  __weak __typeof(self) weakSelf = self;
  dispatch_source_set_event_handler(_timer, ^{
    __strong __typeof(weakSelf) self = weakSelf;
    if (!self || !self->_eventEmitterReady) return;
    NSDictionary *snap = [self buildVpnInfo];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self emitIfMeaningful:snap];
    });
  });
  dispatch_resume(_timer);
}

- (void)stopTimer
{
  if (_timer != NULL) {
    dispatch_source_cancel(_timer);
    _timer = NULL;
  }
}

#pragma mark - Helpers

// Heuristic: active only if a VPN-ish interface (utun/ppp/ipsec) is UP+RUNNING
// and has a private IPv4 address (avoids iCloud Private Relay / generic utun IPv6).
- (BOOL)isVpnUp
{
#if TARGET_OS_SIMULATOR
  return NO; // Simulator uses virtual interfaces (e.g., utun) that can look like VPN
#endif
  struct ifaddrs *interfaces = NULL;
  BOOL active = NO;
  if (getifaddrs(&interfaces) == 0) {
    for (struct ifaddrs *ifa = interfaces; ifa != NULL; ifa = ifa->ifa_next) {
      if (!ifa->ifa_name) continue;
      NSString *name = [NSString stringWithUTF8String:ifa->ifa_name];
      if (!([name hasPrefix:@"utun"] || [name hasPrefix:@"ppp"] || [name hasPrefix:@"ipsec"])) continue;
      // Require interface is up and running
      if (!(ifa->ifa_flags & IFF_UP) || !(ifa->ifa_flags & IFF_RUNNING)) continue;
      // Require a private IPv4 address to avoid iCloud Private Relay / generic utun IPv6
      if (ifa->ifa_addr && (ifa->ifa_addr->sa_family == AF_INET)) {
        char host[NI_MAXHOST];
        int result = getnameinfo(ifa->ifa_addr,
                                 sizeof(struct sockaddr_in),
                                 host, sizeof(host),
                                 NULL, 0, NI_NUMERICHOST);
        if (result == 0) {
          NSString *ip = [NSString stringWithUTF8String:host];
          if ([self isNonLinkLocalAddress:ip] && [self isPrivateIPv4:ip]) { active = YES; break; }
        }
      }
    }
    freeifaddrs(interfaces);
  }
  return active;
}

// Builds a dictionary describing current VPN info for JS consumption. On
// Simulator, always reports inactive to avoid virtual utun false positives.
- (NSDictionary *)buildVpnInfo
{
#if TARGET_OS_SIMULATOR
  return @{
    @"active": @(NO),
    @"type": @"none",
    @"interfaceName": (id)kCFNull,
    @"localAddress": (id)kCFNull,
    @"remoteAddress": (id)kCFNull,
    @"dns": @[],
    @"timestamp": @([[NSDate date] timeIntervalSince1970] * 1000.0),
    @"platform": @"ios",
  };
#endif
  BOOL active = NO;
  NSString *iface = nil;
  NSString *localAddress = nil;

  struct ifaddrs *interfaces = NULL;
  if (getifaddrs(&interfaces) == 0) {
    for (struct ifaddrs *ifa = interfaces; ifa != NULL; ifa = ifa->ifa_next) {
      if (!ifa->ifa_name) continue;
      NSString *name = [NSString stringWithUTF8String:ifa->ifa_name];
      BOOL isVpnName = ([name hasPrefix:@"utun"] || [name hasPrefix:@"ppp"] || [name hasPrefix:@"ipsec"]);
      if (!isVpnName) continue;
      // Require interface is up and running
      if (!(ifa->ifa_flags & IFF_UP) || !(ifa->ifa_flags & IFF_RUNNING)) continue;
      iface = name;

      // Capture first IPv4/IPv6 address for that interface
      if (ifa->ifa_addr && (ifa->ifa_addr->sa_family == AF_INET)) {
        char host[NI_MAXHOST];
        int result = getnameinfo(ifa->ifa_addr,
                                 sizeof(struct sockaddr_in),
                                 host, sizeof(host),
                                 NULL, 0, NI_NUMERICHOST);
        if (result == 0) {
          NSString *ip = [NSString stringWithUTF8String:host];
          if ([self isNonLinkLocalAddress:ip] && [self isPrivateIPv4:ip]) {
            localAddress = ip;
            active = YES;
          }
        }
      }
      if (active) { break; }
    }
    freeifaddrs(interfaces);
  }

  NSString *type = [self inferTypeFromInterface:iface];
  NSArray *dnsArray = @[]; // iOS doesn't expose DNS easily without private APIs; leave empty

  return @{
    @"active": @(active),
    @"type": active ? type : @"none",
    @"interfaceName": (iface ?: (id)kCFNull),
    @"localAddress": (localAddress ?: (id)kCFNull),
    @"remoteAddress": (id)kCFNull,
    @"dns": dnsArray,
    @"timestamp": @([[NSDate date] timeIntervalSince1970] * 1000.0),
    @"platform": @"ios",
  };
}

// Emits onStatusChanged only when something meaningful changed compared to
// the last emission (ignores timestamp-only changes).
- (void)emitIfMeaningful:(NSDictionary *)snapshot
{
  // If we never emitted before, emit now
  if (_lastEmittedSnapshot == nil) {
    _lastEmittedSnapshot = snapshot;
    [self emitOnStatusChanged:snapshot];
    return;
  }

  // Avoid emitting if nothing relevant changed to reduce noise (like timestamp only)
  BOOL prevActive = [[_lastEmittedSnapshot objectForKey:@"active"] boolValue];
  BOOL currActive = [[snapshot objectForKey:@"active"] boolValue];

  NSString *prevType = [self stringOrEmpty:[_lastEmittedSnapshot objectForKey:@"type"]];
  NSString *currType = [self stringOrEmpty:[snapshot objectForKey:@"type"]];

  NSString *prevIface = [self stringOrEmpty:[_lastEmittedSnapshot objectForKey:@"interfaceName"]];
  NSString *currIface = [self stringOrEmpty:[snapshot objectForKey:@"interfaceName"]];

  NSString *prevLocal = [self stringOrEmpty:[_lastEmittedSnapshot objectForKey:@"localAddress"]];
  NSString *currLocal = [self stringOrEmpty:[snapshot objectForKey:@"localAddress"]];

  BOOL sameActive = (prevActive == currActive);
  BOOL sameType = ([prevType isEqualToString:currType]);
  BOOL sameIface = ([prevIface isEqualToString:currIface]);
  BOOL sameLocal = ([prevLocal isEqualToString:currLocal]);

  if (sameActive && sameType && sameIface && sameLocal) {
    return; // no meaningful change; drop
  }

  _lastEmittedSnapshot = snapshot;
  [self emitOnStatusChanged:snapshot];
}

// Returns NO for link-local IPv4 (169.254.0.0/16) and IPv6 (fe80::/10)
- (BOOL)isNonLinkLocalAddress:(NSString *)ip
{
  if (ip == nil) return NO;
  if ([ip hasPrefix:@"169.254."]) return NO; // IPv4 link-local
  if ([ip hasPrefix:@"fe80:"]) return NO;    // IPv6 link-local
  return YES;
}

// Returns YES if the IPv4 address is private (RFC1918) or CGNAT (100.64/10)
- (BOOL)isPrivateIPv4:(NSString *)ip
{
  if (ip == nil) return NO;
  if ([ip hasPrefix:@"10."]) return YES;
  if ([ip hasPrefix:@"192.168."]) return YES;
  if ([ip hasPrefix:@"172."]) {
    NSArray *parts = [ip componentsSeparatedByString:@"."];
    if (parts.count > 1) {
      NSInteger second = [parts[1] integerValue];
      if (second >= 16 && second <= 31) return YES; // 172.16.0.0/12
    }
  }
  if ([ip hasPrefix:@"100."]) { // CGNAT 100.64.0.0/10
    NSArray *parts = [ip componentsSeparatedByString:@"."];
    if (parts.count > 1) {
      NSInteger second = [parts[1] integerValue];
      if (second >= 64 && second <= 127) return YES;
    }
  }
  return NO;
}

// Converts id to NSString* or empty string for safe comparisons
- (NSString *)stringOrEmpty:(id)val
{
  if ([val isKindOfClass:[NSString class]]) {
    return (NSString *)val;
  }
  return @"";
}

// Roughly infers VPN type from interface name prefix, otherwise "unknown".
- (NSString *)inferTypeFromInterface:(NSString *)ifName
{
  if (ifName == nil) return @"unknown";
  NSString *n = [ifName lowercaseString];
  if ([n hasPrefix:@"wg"]) return @"wireguard";
  if ([n hasPrefix:@"tun"] || [n hasPrefix:@"tap"]) return @"openvpn";
  if ([n hasPrefix:@"ppp"]) return @"l2tp"; // or pptp on old stacks
  if ([n hasPrefix:@"ipsec"]) return @"ipsec";
  if ([n hasPrefix:@"ike"]) return @"ikev2";
  if ([n hasPrefix:@"utun"]) return @"unknown"; // generic on iOS
  return @"unknown";
}

@end
