# react-native-vpn-listener

Reliable, event‑driven VPN detection for React Native — on **both** platforms. Know instantly when your users connect or disconnect a VPN, with connection details, not just a boolean.

![npm](https://img.shields.io/npm/v/react-native-vpn-listener) ![license](https://img.shields.io/npm/l/react-native-vpn-listener) ![platforms](https://img.shields.io/badge/platforms-ios%20%7C%20android-blue)

Built for apps where VPN state actually matters:

- 🎬 **Streaming / media** — geo‑licensing compliance
- 💳 **Fintech & payments** — fraud signals, risk scoring
- 🎰 **Betting / gambling** — regulatory geo‑fencing
- 🏢 **Security & MDM** — enforce or verify VPN posture

## ✨ Features

- 🔔 Truly event‑driven on both platforms (`NWPathMonitor` on iOS, `ConnectivityManager` callbacks on Android — no polling, no battery drain)
- 🪝 `useVpnStatus()` React hook for one‑line integration
- 📱 One JS API, both platforms — including iOS, where most alternatives fall short
- 🔍 Details, not just a boolean: interface, addresses, DNS (best‑effort, honestly typed per platform)
- ⚡ New Architecture TurboModule (fast, typed, codegen‑driven)
- 🛡 Public APIs only — no private API risk for App Store review

## 🥊 Comparison

|                                     | react-native-vpn-listener | @react-native-community/netinfo | react-native-vpn-detector | react-native-vpn-status |
| ----------------------------------- | ------------------------- | ------------------------------- | ------------------------- | ----------------------- |
| VPN detection on Android            | ✅                        | ✅                              | ✅                        | ✅                      |
| VPN detection on iOS                | ✅                        | ❌                              | ✅                        | ✅                      |
| Live change events                  | ✅ event‑driven           | ✅                              | ❌ one‑shot check         | ✅                      |
| Connection details (interface, IPs) | ✅                        | ❌                              | ❌ boolean only           | ❌                      |
| React hook                          | ✅ `useVpnStatus()`       | ✅                              | ❌                        | ❌                      |
| New Architecture (TurboModule)      | ✅ native                 | ➖ interop                      | ❌ old architecture       | ❌ old architecture     |

## ✅ Requirements

| Runtime      | Minimum                                         |
| ------------ | ----------------------------------------------- |
| React Native | 0.80+ (New Architecture required; tested on 0.86) |
| iOS          | 13.4+                                           |
| Android      | minSdk 24+                                      |
| Expo         | Dev Client / EAS builds (not Expo Go)           |

## 📦 Installation

```bash
npm install react-native-vpn-listener
# or
yarn add react-native-vpn-listener
```

### iOS

```bash
cd ios && pod install
```

### Expo

- Supported via Expo Dev Client and EAS builds.
- Use `npx expo run:ios` / `npx expo run:android` for development builds.

## 🚀 Quick Start

```tsx
import { Text, View } from 'react-native';
import { useVpnStatus } from 'react-native-vpn-listener';

export default function App() {
  const vpn = useVpnStatus(); // null until the first snapshot arrives

  return (
    <View>
      <Text>Active: {vpn?.active ? 'yes' : 'no'}</Text>
      <Text>Type: {vpn?.type}</Text>
      <Text>Interface: {vpn?.interfaceName ?? '-'}</Text>
      <Text>Local IP: {vpn?.localAddress ?? '-'}</Text>
    </View>
  );
}
```

Prefer imperative APIs? `isVpnActive()`, `getVpnInfo()`, and `onChange()` are also exported:

```ts
import { isVpnActive, getVpnInfo, onChange } from 'react-native-vpn-listener';

const active = await isVpnActive();
const info = await getVpnInfo();
const sub = onChange((next) => console.log('VPN changed:', next));
// later: sub.remove();
```

## 📖 API Reference

### Methods

- `useVpnStatus(): VpnInfo | null`
  - React hook returning the current VPN status; re‑renders on every change. `null` until the first snapshot arrives.
- `isVpnActive(): Promise<boolean>`
  - Returns whether a VPN‑like interface is currently active.
- `getVpnInfo(): Promise<VpnInfo>`
  - Returns a snapshot with details (see Types).
- `onChange(cb: (info: VpnInfo) => void): { remove(): void }`
  - Subscribes to status changes; call `remove()` to unsubscribe.

### Events (semantics)

- Android: fires on `ConnectivityManager` network callbacks (VPN networks and default‑network changes), de‑duplicated so unrelated Wi‑Fi↔cellular transitions don't emit.
- iOS: fires on `NWPathMonitor` path updates (no polling) and de‑noised (emits only when fields other than `timestamp` change). Sends one initial snapshot after subscription.

## 🧾 Types

```ts
export type VpnType =
  | 'none'
  | 'ipsec'
  | 'ikev2'
  | 'openvpn'
  | 'wireguard'
  | 'l2tp'
  | 'pptp'
  | 'unknown';

export type VpnInfo = {
  active: boolean;
  type: VpnType; // heuristic (see notes)
  interfaceName: string | null; // e.g., utun4 (iOS), tun0 (Android); null when inactive
  localAddress: string | null; // local tunnel IP; null when inactive
  remoteAddress: string | null; // Android best‑effort; always null on iOS
  dns: string[]; // Android best‑effort; always empty on iOS
  timestamp: number; // ms since epoch
  platform: 'ios' | 'android';
};
```

Notes:

- iOS never populates `dns` or `remoteAddress` (public APIs do not expose them).
- On iOS, `type` is almost always `'unknown'` when active — every VPN appears as a generic `utun` interface.
- Android may omit fields depending on device/OS.

## 🔧 Configuration

### iOS

- No Info.plist changes or special entitlements.
- Uses `getifaddrs` to enumerate interfaces.

### Android

- Requires `ACCESS_NETWORK_STATE`. Declared by the library and merged automatically.

## 🧭 Platform Support

| Platform | Status | Notes                                                                 |
| -------- | ------ | --------------------------------------------------------------------- |
| iOS      | ✅     | `NWPathMonitor` event‑driven; public APIs only; simulator forced inactive |
| Android  | ✅     | `ConnectivityManager` callbacks; best‑effort details                  |

## ⚠️ Limitations

- iOS detection is heuristic: a VPN‑ish interface (`utun`/`ppp`/`ipsec`) must be UP+RUNNING with a private/CGNAT IPv4 or a routable (non‑link‑local) IPv6 address. IPv6‑only VPNs are detected; system services that route traffic through a `utun` with a routable address (e.g. some iCloud Private Relay configurations) may register as a VPN.
- iOS Simulator: always reported as inactive (simulator `utun` can resemble VPN).
- Android details (DNS, gateway) are best‑effort and may vary by OEM/OS.

## 🧪 Example App

A runnable example is included under `example/`.

```bash
cd example
yarn
yarn start
```

## 🧰 Development

```bash
git clone https://github.com/hamzamekk/react-native-vpn-listener.git
cd react-native-vpn-listener
yarn
cd example
yarn
yarn android
# or
yarn ios
```

Please include minimal repro steps for native changes. TypeScript and modern RN patterns preferred.

## 🛠 Troubleshooting

- iOS events not firing:
  - `cd ios && pod install`, then Clean Build Folder in Xcode and rerun
  - Subscribe via `onChange` before fetching
  - Toggle Wi‑Fi/VPN to trigger updates
- Android build issues:
  - Use JDK 17; install Android SDK; ensure `ANDROID_HOME` is set

## 📄 License

MIT
