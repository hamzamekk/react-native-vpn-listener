#import "VpnListener.h"
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>
#import <netdb.h>
#import <sys/socket.h>
#import <Network/Network.h>
#import <TargetConditionals.h>

@implementation VpnListener {
  nw_path_monitor_t _pathMonitor;
  dispatch_queue_t _monitorQueue;
  BOOL _eventEmitterReady;
  NSDictionary *_pendingInitialSnapshot;
  NSDictionary *_lastEmittedSnapshot;
}

RCT_EXPORT_MODULE()

#pragma mark - Init

- (instancetype)init
{
  if ((self = [super init])) {
    _pathMonitor = NULL;
    _monitorQueue = NULL;
    _eventEmitterReady = NO;
    _pendingInitialSnapshot = nil;
    _lastEmittedSnapshot = nil;
    [self startMonitorIfNeeded];
    // Precompute initial snapshot; will be emitted once the emitter is ready
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
  [self stopMonitor];
}

// Called by the runtime when the JS event emitter is ready. We then flush
// any pending initial snapshot to JS on the main thread.
- (void)setEventEmitterCallback:(EventEmitterCallbackWrapper *)eventEmitterCallbackWrapper
{
  [super setEventEmitterCallback:eventEmitterCallbackWrapper];
  _eventEmitterReady = YES;
  if (_pendingInitialSnapshot != nil) {
    NSDictionary *snapshot = _pendingInitialSnapshot;
    _pendingInitialSnapshot = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self emitIfMeaningful:snapshot];
    });
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

#pragma mark - Event-driven updates (NWPathMonitor)

// Starts an NWPathMonitor that fires whenever the network path changes
// (VPN up/down, interface changes). No polling.
- (void)startMonitorIfNeeded
{
  if (_pathMonitor != NULL) return;
  _monitorQueue = dispatch_queue_create("com.vpnlistener.pathmonitor", DISPATCH_QUEUE_SERIAL);
  _pathMonitor = nw_path_monitor_create();
  if (_pathMonitor == NULL) return;
  __weak __typeof(self) weakSelf = self;
  nw_path_monitor_set_update_handler(_pathMonitor, ^(nw_path_t path) {
    __strong __typeof(weakSelf) self = weakSelf;
    if (!self || !self->_eventEmitterReady) return;
    NSDictionary *snap = [self buildVpnInfo];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self emitIfMeaningful:snap];
    });
  });
  nw_path_monitor_set_queue(_pathMonitor, _monitorQueue);
  nw_path_monitor_start(_pathMonitor);
}

- (void)stopMonitor
{
  if (_pathMonitor != NULL) {
    nw_path_monitor_cancel(_pathMonitor);
    _pathMonitor = NULL;
    _monitorQueue = NULL;
  }
}

#pragma mark - Helpers

// Heuristic: active only if a VPN-ish interface (utun/ppp/ipsec) is UP+RUNNING
// and carries a routable address: private/CGNAT IPv4, or any non-link-local
// IPv6 (idle system utuns only hold fe80:: link-local addresses).
- (BOOL)isVpnUp
{
#if TARGET_OS_SIMULATOR
  return NO; // Simulator uses virtual interfaces (e.g., utun) that can look like VPN
#endif
  return [[[self buildVpnInfo] objectForKey:@"active"] boolValue];
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
      if (!ifa->ifa_name || !ifa->ifa_addr) continue;
      NSString *name = [NSString stringWithUTF8String:ifa->ifa_name];
      BOOL isVpnName = ([name hasPrefix:@"utun"] || [name hasPrefix:@"ppp"] || [name hasPrefix:@"ipsec"]);
      if (!isVpnName) continue;
      // Require interface is up and running
      if (!(ifa->ifa_flags & IFF_UP) || !(ifa->ifa_flags & IFF_RUNNING)) continue;

      NSString *ip = [self numericAddressFor:ifa];
      if (ip != nil && [self isVpnTunnelAddress:ip]) {
        iface = name;
        localAddress = ip;
        active = YES;
        break;
      }
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

// Returns the numeric string form of an interface address (IPv4 or IPv6),
// or nil for other families / conversion failures.
- (NSString *)numericAddressFor:(struct ifaddrs *)ifa
{
  sa_family_t family = ifa->ifa_addr->sa_family;
  if (family != AF_INET && family != AF_INET6) return nil;
  socklen_t len = (family == AF_INET) ? sizeof(struct sockaddr_in) : sizeof(struct sockaddr_in6);
  char host[NI_MAXHOST];
  if (getnameinfo(ifa->ifa_addr, len, host, sizeof(host), NULL, 0, NI_NUMERICHOST) != 0) {
    return nil;
  }
  NSString *ip = [NSString stringWithUTF8String:host];
  // Strip scope suffix from scoped IPv6 addresses (e.g. "fe80::1%utun0")
  NSRange scope = [ip rangeOfString:@"%"];
  if (scope.location != NSNotFound) {
    ip = [ip substringToIndex:scope.location];
  }
  return ip;
}

// Returns YES for addresses that indicate a real VPN tunnel:
// private/CGNAT IPv4, or any non-link-local IPv6 (ULA or global).
// Idle system utuns only carry fe80:: link-local addresses, which are excluded.
- (BOOL)isVpnTunnelAddress:(NSString *)ip
{
  if (ip == nil) return NO;
  if ([ip hasPrefix:@"169.254."]) return NO; // IPv4 link-local
  if ([ip hasPrefix:@"fe80:"]) return NO;    // IPv6 link-local
  if ([ip containsString:@":"]) return YES;  // routable IPv6 (ULA/global)
  return [self isPrivateIPv4:ip];
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
