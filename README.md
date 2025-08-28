# react-native-vpn-listener

Detect VPN connectivity on iOS and Android using React Native’s New Architecture (TurboModule + codegen). Minimal API, typed results, and an event for status changes.

![npm](https://img.shields.io/npm/v/react-native-vpn-listener) ![license](https://img.shields.io/npm/l/react-native-vpn-listener) ![platforms](https://img.shields.io/badge/platforms-ios%20%7C%20android-blue)

## ✨ Features

- ⚡ New Architecture TurboModule (fast, typed, codegen‑driven)
- 📱 Cross‑platform with a single JS API
- 🔔 Event‑driven updates via `onChange`
- 🧪 Strong TypeScript types
- 🛡 Public APIs only on iOS; best‑effort details on Android

## ✅ Requirements

| Runtime      | Minimum                               |
| ------------ | ------------------------------------- |
| React Native | 0.75+ (New Architecture required)     |
| iOS          | 13.4+                                 |
| Android      | minSdk 21+                            |
| Expo         | Dev Client / EAS builds (not Expo Go) |

## 📦 Installation

```bash
# npm	npm install react-native-vpn-listener
# yarn	yarn add react-native-vpn-listener
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
import React, { useEffect, useState } from 'react';
import { Text, View } from 'react-native';
import {
  onChange,
  getVpnInfo,
  isVpnActive,
  type VpnInfo,
} from 'react-native-vpn-listener';

export default function App() {
  const [vpn, setVpn] = useState<VpnInfo | null>(null);

  // Subscribe to changes
  useEffect(() => {
    const sub = onChange((next) => setVpn(next));
    return () => sub.remove();
  }, []);

  // Fetch once at start
  useEffect(() => {
    (async () => {
      setVpn(await getVpnInfo());
      console.log('Active?', await isVpnActive());
    })();
  }, []);

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

## 📖 API Reference

### Methods

- `isVpnActive(): Promise<boolean>`
  - Returns whether a VPN‑like interface is currently active.
- `getVpnInfo(): Promise<VpnInfo>`
  - Returns a snapshot with details (see Types).
- `onChange(cb: (info: VpnInfo) => void): { remove(): void }`
  - Subscribes to status changes; call `remove()` to unsubscribe.

### Events (semantics)

- Android: fires on system connectivity changes related to VPN.
- iOS: sampled roughly every ~2s and de‑noised (emits only when fields other than `timestamp` change). Sends one initial snapshot after subscription.

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
  interfaceName?: string; // e.g., utun0 (iOS), tun0 (Android)
  localAddress?: string; // local IP if known
  remoteAddress?: string; // Android best‑effort
  dns?: string[]; // Android best‑effort; empty on iOS
  timestamp: number; // ms since epoch
  platform: 'ios' | 'android';
};
```

Notes:

- iOS does not populate `dns` or `remoteAddress` (public APIs do not expose them).
- Android may omit fields depending on device/OS.

## 🔧 Configuration

### iOS

- No Info.plist changes or special entitlements.
- Uses `getifaddrs` to enumerate interfaces.

### Android

- Requires `ACCESS_NETWORK_STATE`. Declared by the library and merged automatically.

## 🧭 Platform Support

| Platform | Status | Notes                                                     |
| -------- | ------ | --------------------------------------------------------- |
| iOS      | ✅     | Public APIs only; sampling ~2s; simulator forced inactive |
| Android  | ✅     | `ConnectivityManager` callbacks; best‑effort details      |

## ⚠️ Limitations

- iOS: To avoid false positives (e.g. iCloud Private Relay / enterprise tunnels), the module requires a VPN‑ish interface (`utun`/`ppp`/`ipsec`) that is UP+RUNNING with a private IPv4. As a result, IPv6‑only VPNs may not be detected.
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
