import { useEffect, useRef, useState } from 'react';
import {
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  useColorScheme,
  View,
} from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import {
  getVpnInfo,
  isVpnActive,
  onChange,
  useVpnStatus,
  type VpnInfo,
} from 'react-native-vpn-listener';

type LogEntry = {
  id: number;
  time: string;
  source: 'event' | 'check';
  info: VpnInfo;
  activeFlag?: boolean;
};

const IOS_ONLY_NA = Platform.OS === 'ios' ? 'n/a on iOS' : null;

function formatTime(timestamp: number): string {
  return new Date(timestamp).toLocaleTimeString();
}

function Row({
  label,
  value,
  colors,
  testID,
}: {
  label: string;
  value: string | null;
  colors: Palette;
  testID?: string;
}) {
  return (
    <View style={styles.row}>
      <Text style={[styles.rowLabel, { color: colors.dim }]}>{label}</Text>
      <Text
        testID={testID}
        style={[styles.rowValue, { color: value ? colors.text : colors.dim }]}
      >
        {value ?? '—'}
      </Text>
    </View>
  );
}

function StatusCard({
  info,
  colors,
}: {
  info: VpnInfo | null;
  colors: Palette;
}) {
  const active = info?.active ?? false;
  return (
    <View
      testID="status-card"
      style={[styles.card, { backgroundColor: colors.card }]}
    >
      <View style={styles.statusHeader}>
        <View
          style={[
            styles.dot,
            {
              backgroundColor: info
                ? active
                  ? colors.ok
                  : colors.bad
                : colors.dim,
            },
          ]}
        />
        <Text
          testID="status-text"
          style={[styles.statusText, { color: colors.text }]}
        >
          {info == null ? 'Loading…' : active ? 'VPN connected' : 'No VPN'}
        </Text>
      </View>
      <Row
        label="Type"
        value={info?.active ? info.type : null}
        colors={colors}
        testID="row-type"
      />
      <Row
        label="Interface"
        value={info?.interfaceName ?? null}
        colors={colors}
        testID="row-interface"
      />
      <Row
        label="Local address"
        value={info?.localAddress ?? null}
        colors={colors}
        testID="row-local"
      />
      <Row
        label="Remote address"
        value={info?.remoteAddress ?? IOS_ONLY_NA}
        colors={colors}
        testID="row-remote"
      />
      <Row
        label="DNS"
        value={info && info.dns.length > 0 ? info.dns.join(', ') : IOS_ONLY_NA}
        colors={colors}
        testID="row-dns"
      />
      <Row
        label="Updated"
        value={info ? formatTime(info.timestamp) : null}
        colors={colors}
        testID="row-updated"
      />
    </View>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <Main />
    </SafeAreaProvider>
  );
}

function Main() {
  const scheme = useColorScheme();
  const colors = scheme === 'dark' ? dark : light;

  // Live status via the hook — updates on every native event.
  const vpnInfo = useVpnStatus();

  // Event log via the imperative subscription API.
  const [log, setLog] = useState<LogEntry[]>([]);
  const nextId = useRef(0);

  useEffect(() => {
    const subscription = onChange((info) => {
      setLog((prev) => [
        {
          id: nextId.current++,
          time: formatTime(info.timestamp),
          source: 'event',
          info,
        },
        ...prev,
      ]);
    });
    return () => subscription.remove();
  }, []);

  // One-shot promise API: isVpnActive() + getVpnInfo().
  const checkNow = async () => {
    const [activeFlag, info] = await Promise.all([isVpnActive(), getVpnInfo()]);
    setLog((prev) => [
      {
        id: nextId.current++,
        time: formatTime(info.timestamp),
        source: 'check',
        info,
        activeFlag,
      },
      ...prev,
    ]);
  };

  return (
    <SafeAreaView
      style={[styles.container, { backgroundColor: colors.background }]}
    >
      <Text style={[styles.title, { color: colors.text }]}>VPN Listener</Text>
      <StatusCard info={vpnInfo} colors={colors} />

      <Pressable
        testID="check-now"
        onPress={checkNow}
        style={({ pressed }) => [
          styles.button,
          { backgroundColor: colors.accent, opacity: pressed ? 0.7 : 1 },
        ]}
      >
        <Text style={styles.buttonText}>Check now</Text>
      </Pressable>

      <Text style={[styles.logTitle, { color: colors.dim }]}>
        {log.length === 0
          ? 'Waiting for VPN changes… (connect or disconnect a VPN)'
          : `Log — ${log.length} entr${log.length === 1 ? 'y' : 'ies'}`}
      </Text>
      <ScrollView style={styles.log} testID="event-log">
        {log.map((entry) => (
          <View
            key={entry.id}
            style={[styles.logEntry, { borderColor: colors.border }]}
          >
            <Text style={[styles.logMeta, { color: colors.dim }]}>
              {entry.time} ·{' '}
              {entry.source === 'event'
                ? 'onChange event'
                : `check (isVpnActive: ${String(entry.activeFlag)})`}
            </Text>
            <Text style={[styles.logText, { color: colors.text }]}>
              {entry.info.active
                ? `connected — ${entry.info.type} on ${entry.info.interfaceName}` +
                  (entry.info.localAddress
                    ? ` (${entry.info.localAddress})`
                    : '')
                : 'disconnected'}
            </Text>
          </View>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

type Palette = typeof light;

const light = {
  background: '#f2f2f7',
  card: '#ffffff',
  text: '#1c1c1e',
  dim: '#8e8e93',
  border: '#e5e5ea',
  accent: '#007aff',
  ok: '#34c759',
  bad: '#ff3b30',
};

const dark: Palette = {
  background: '#000000',
  card: '#1c1c1e',
  text: '#f2f2f7',
  dim: '#8e8e93',
  border: '#2c2c2e',
  accent: '#0a84ff',
  ok: '#30d158',
  bad: '#ff453a',
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    paddingHorizontal: 16,
  },
  title: {
    fontSize: 28,
    fontWeight: '700',
    marginTop: 8,
    marginBottom: 16,
  },
  card: {
    borderRadius: 12,
    padding: 16,
    gap: 8,
  },
  statusHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  dot: {
    width: 12,
    height: 12,
    borderRadius: 6,
    marginRight: 8,
  },
  statusText: {
    fontSize: 20,
    fontWeight: '600',
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  rowLabel: {
    fontSize: 15,
  },
  rowValue: {
    fontSize: 15,
    fontVariant: ['tabular-nums'],
    flexShrink: 1,
    textAlign: 'right',
  },
  button: {
    marginTop: 16,
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: 'center',
  },
  buttonText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '600',
  },
  logTitle: {
    fontSize: 13,
    marginTop: 20,
    marginBottom: 8,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  log: {
    flex: 1,
  },
  logEntry: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    paddingVertical: 8,
  },
  logMeta: {
    fontSize: 12,
    marginBottom: 2,
  },
  logText: {
    fontSize: 14,
  },
});
