import { useEffect, useState } from 'react';
import VpnListener from './NativeVpnListener';
import type { VpnInfo, VpnType } from './NativeVpnListener';

export function isVpnActive(): Promise<boolean> {
  return VpnListener.isVpnActive();
}

export function getVpnInfo(): Promise<VpnInfo> {
  return VpnListener.getVpnInfo();
}

export function onChange(cb: (info: VpnInfo) => void) {
  return VpnListener.onStatusChanged(cb);
}

/**
 * React hook that returns the current VPN status and re-renders on every
 * change. Returns `null` until the first snapshot arrives.
 */
export function useVpnStatus(): VpnInfo | null {
  const [info, setInfo] = useState<VpnInfo | null>(null);

  useEffect(() => {
    let mounted = true;
    const subscription = VpnListener.onStatusChanged((next) => {
      if (mounted) setInfo(next);
    });
    VpnListener.getVpnInfo().then(
      (snapshot) => {
        // Keep the event value if one already arrived before the fetch resolved
        if (mounted) setInfo((prev) => prev ?? snapshot);
      },
      () => {}
    );
    return () => {
      mounted = false;
      subscription.remove();
    };
  }, []);

  return info;
}

export default VpnListener;

export type { VpnInfo, VpnType };
