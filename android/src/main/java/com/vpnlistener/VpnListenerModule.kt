package com.vpnlistener

import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.module.annotations.ReactModule
import java.util.Collections

@ReactModule(name = VpnListenerModule.NAME)
class VpnListenerModule(reactContext: ReactApplicationContext) :
  NativeVpnListenerSpec(reactContext) {

  companion object {
    const val NAME = "VpnListener"
  }

  private val appContext: ReactApplicationContext = reactContext
  private var registeredDefault: Boolean = false
  private var registeredVpnOnly: Boolean = false

  /** VPN networks currently reported available by the vpn-only callback. */
  private val vpnNetworks: MutableSet<Network> =
    Collections.synchronizedSet(mutableSetOf())

  /** Key of the last emitted snapshot, used to drop no-op events. */
  private var lastEmittedKey: String? = null

  /**
   * Module name exposed to React Native. Kept for clarity alongside codegen.
   */
  override fun getName(): String = NAME

  private val cm: ConnectivityManager =
    appContext.getSystemService(ConnectivityManager::class.java)

  private val vpnRequest: NetworkRequest = NetworkRequest.Builder()
    .addTransportType(NetworkCapabilities.TRANSPORT_VPN)
    .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
    .build()

  /** Tracks VPN networks coming and going. */
  private val vpnCallback = object : ConnectivityManager.NetworkCallback() {
    override fun onAvailable(network: Network) {
      vpnNetworks.add(network)
      emitSnapshot()
    }

    override fun onLost(network: Network) {
      vpnNetworks.remove(network)
      emitSnapshot()
    }

    override fun onLinkPropertiesChanged(n: Network, lp: LinkProperties) = emitSnapshot()
  }

  /**
   * Watches the default network so we also catch VPNs that become the default
   * route; snapshot dedupe drops unrelated wifi/cell transitions.
   */
  private val defaultCallback = object : ConnectivityManager.NetworkCallback() {
    override fun onAvailable(network: Network) = emitSnapshot()
    override fun onLost(network: Network) = emitSnapshot()
    override fun onCapabilitiesChanged(n: Network, c: NetworkCapabilities) = emitSnapshot()
  }

  /**
   * Called when the module is initialized. Register callbacks up front; emission is guarded
   * by hasActiveReactInstance() so there's no early crash before JS is ready.
   */
  override fun initialize() {
    super.initialize()
    if (!registeredDefault) {
      runCatching { cm.registerDefaultNetworkCallback(defaultCallback) }
        .onSuccess { registeredDefault = true }
    }
    if (!registeredVpnOnly) {
      runCatching { cm.registerNetworkCallback(vpnRequest, vpnCallback) }
        .onSuccess { registeredVpnOnly = true }
    }
  }

  /**
   * Called when the module is being disposed. Cleans up callbacks.
   */
  override fun invalidate() {
    super.invalidate()
    safeUnregister()
  }

  /**
   * Promise-returning API used by JS to check if a VPN is active.
   */
  override fun isVpnActive(promise: Promise) {
    promise.resolve(isVpnUp())
  }

  /**
   * Promise-returning API used by JS to fetch current VPN info snapshot.
   */
  override fun getVpnInfo(promise: Promise) {
    promise.resolve(buildVpnInfo())
  }

  // ---- Helpers ----

  /**
   * Best-effort unregister of the connectivity callbacks.
   */
  private fun safeUnregister() {
    if (registeredDefault) {
      runCatching { cm.unregisterNetworkCallback(defaultCallback) }
        .onSuccess { registeredDefault = false }
    }
    if (registeredVpnOnly) {
      runCatching { cm.unregisterNetworkCallback(vpnCallback) }
        .onSuccess { registeredVpnOnly = false }
    }
    vpnNetworks.clear()
  }

  /**
   * Emits an onStatusChanged event if the React instance is active and the
   * snapshot meaningfully differs from the last one emitted (drops timestamp-only
   * changes and unrelated wifi/cell transitions).
   */
  @Synchronized
  private fun emitSnapshot() {
    if (!appContext.hasActiveReactInstance()) return
    val info = buildVpnInfo()
    val key = listOf(
      info.getBoolean("active"),
      info.getString("type"),
      info.getString("interfaceName"),
      info.getString("localAddress")
    ).joinToString("|")
    if (key == lastEmittedKey) return
    runCatching { emitOnStatusChanged(info) }
      .onSuccess { lastEmittedKey = key }
  }

  /**
   * Returns true if a VPN network is currently up.
   */
  private fun isVpnUp(): Boolean = currentVpnNetwork() != null

  /**
   * Finds the current VPN network, if any: prefer networks tracked by the
   * vpn-only callback, fall back to checking the default network's transport.
   */
  private fun currentVpnNetwork(): Network? {
    synchronized(vpnNetworks) {
      val tracked = vpnNetworks.firstOrNull { n ->
        cm.getNetworkCapabilities(n)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
      }
      if (tracked != null) return tracked
    }
    return cm.activeNetwork?.takeIf { n ->
      cm.getNetworkCapabilities(n)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
    }
  }

  /**
   * Builds the data map describing VPN state, interface, addresses, DNS, and timestamps.
   */
  private fun buildVpnInfo(): WritableMap {
    val now = System.currentTimeMillis()
    val vpn = currentVpnNetwork()
    val lp = vpn?.let { cm.getLinkProperties(it) }

    val interfaceName = lp?.interfaceName
    val type = inferType(interfaceName)

    val localAddress = lp?.linkAddresses?.firstOrNull()?.address?.hostAddress
    val dns = (lp?.dnsServers ?: emptyList()).mapNotNull { it.hostAddress }
    val remoteAddress = lp?.routes
      ?.firstOrNull { it.isDefaultRoute }
      ?.gateway
      ?.hostAddress

    return Arguments.createMap().apply {
      putBoolean("active", vpn != null)
      putString("type", if (vpn != null) type else "none")
      putString("interfaceName", interfaceName)
      putString("localAddress", localAddress)
      putString("remoteAddress", remoteAddress)
      putArray("dns", Arguments.createArray().also { arr -> dns.forEach(arr::pushString) })
      putDouble("timestamp", now.toDouble())
      putString("platform", "android")
    }
  }

  /**
   * Heuristically infers VPN type from the interface name.
   */
  private fun inferType(ifName: String?): String {
    if (ifName == null) return "unknown"
    val n = ifName.lowercase()
    return when {
      n.startsWith("wg")    -> "wireguard"
      n.startsWith("tun")   -> "openvpn"
      n.startsWith("tap")   -> "openvpn"
      n.startsWith("ppp")   -> "l2tp"
      n.startsWith("ipsec") -> "ipsec"
      n.startsWith("ike")   -> "ikev2"
      else                  -> "unknown"
    }
  }
}
