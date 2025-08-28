import VpnStatus from './NativeVpnListener';
import type { VpnInfo } from './NativeVpnListener';

export function isVpnActive() {
  return VpnStatus?.isVpnActive();
}

export function getVpnInfo() {
  return VpnStatus?.getVpnInfo();
}

export function onChange(cb: (info: VpnInfo) => void) {
  return VpnStatus.onStatusChanged(cb);
}
