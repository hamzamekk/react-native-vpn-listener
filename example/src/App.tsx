import { useEffect, useState } from 'react';
import { Text, View, StyleSheet } from 'react-native';
import {
  isVpnActive,
  getVpnInfo,
  onChange,
  type VpnInfo,
} from 'react-native-vpn-listener';

export default function App() {
  const [vpnActive, setVpnActive] = useState(false);
  const [vpnInfo, setVpnInfo] = useState<VpnInfo | null>(null);
  useEffect(() => {
    const unsubscribe = onChange((info: VpnInfo) => {
      console.log(info);
      setVpnActive(info.active);
      setVpnInfo(info);
    });
    return () => unsubscribe.remove();
  }, []);

  useEffect(() => {
    const fetchVpnInfo = async () => {
      const active = await isVpnActive();
      const info = await getVpnInfo();
      setVpnActive(active);
      setVpnInfo(info);
    };
    fetchVpnInfo();
  }, []);

  return (
    <View style={styles.container}>
      <Text>
        Hello World {vpnActive ? 'VPN is active' : 'VPN is not active'}
      </Text>
      <Text>Vpn Info: {JSON.stringify(vpnInfo)}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
