import type { CodegenTypes } from 'react-native';
import { TurboModuleRegistry, type TurboModule } from 'react-native';

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
  /**
   * Best-effort guess from the interface name. On iOS every VPN appears as a
   * generic `utun` interface, so this is almost always `'unknown'` when active.
   */
  type: VpnType;
  /** Tunnel interface name (e.g. `utun4`, `tun0`); `null` when no VPN is active. */
  interfaceName: string | null;
  /** Local tunnel address; `null` when no VPN is active. */
  localAddress: string | null;
  /** VPN gateway address. Android only — always `null` on iOS. */
  remoteAddress: string | null;
  /** DNS servers of the tunnel. Android only — always empty on iOS. */
  dns: string[];
  /** Epoch milliseconds when the snapshot was taken. */
  timestamp: number;
  platform: 'ios' | 'android';
};

export interface Spec extends TurboModule {
  isVpnActive(): Promise<boolean>;
  getVpnInfo(): Promise<VpnInfo>;

  /** Fires whenever VPN connectivity changes */
  readonly onStatusChanged: CodegenTypes.EventEmitter<VpnInfo>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('VpnListener');
