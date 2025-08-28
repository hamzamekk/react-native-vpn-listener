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
  type: VpnType;
  interfaceName?: string;
  localAddress?: string;
  remoteAddress?: string;
  dns?: string[];
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
