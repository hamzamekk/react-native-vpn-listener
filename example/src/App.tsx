import { Text, View, StyleSheet } from 'react-native';
import { useVpnStatus } from 'react-native-vpn-listener';

export default function App() {
  const vpnInfo = useVpnStatus();

  return (
    <View style={styles.container}>
      <Text>
        {vpnInfo == null
          ? 'Loading VPN status…'
          : vpnInfo.active
            ? 'VPN is active'
            : 'VPN is not active'}
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
