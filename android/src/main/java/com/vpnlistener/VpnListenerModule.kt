package com.vpnlistener

import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.module.annotations.ReactModule

@ReactModule(name = VpnListenerModule.NAME)
class VpnListenerModule(reactContext: ReactApplicationContext) :
  NativeVpnListenerSpec(reactContext) {

  companion object {
    const val NAME = "VpnListener"
  }

  private val appContext: ReactApplicationContext = reactContext
  private var hasListeners: Boolean = false
  private var registeredDefault: Boolean = false
  private var registeredVpnOnly: Boolean = false

  /**
   * Module name exposed to React Native. Kept for clarity alongside codegen.
   */
  override fun getName(): String = NAME

  private val cm: ConnectivityManager =
    appContext.getSystemService(ConnectivityManager::class.java)

  private val vpnRequest: NetworkRequest = NetworkRequest.Builder()
    .addTransportType(NetworkCapabilities.TRANSPORT_VPN)
    .build()

  private val vpnCallback = object : ConnectivityManager.NetworkCallback() {
    override fun onAvailable(network: Network) = emitSnapshot()
    override fun onLost(network: Network) = emitSnapshot()
    override fun onCapabilitiesChanged(n: Network, c: NetworkCapabilities) = emitSnapshot()
    override fun onLinkPropertiesChanged(n: Network, lp: LinkProperties) = emitSnapshot()
  }

  /**
   * Called when the module is initialized. Register callbacks up front; emission is guarded
   * by hasActiveCatalystInstance() so there's no early crash before JS is ready.
   */
  override fun initialize() {
    super.initialize()
    if (!registeredDefault) {
      runCatching { cm.registerDefaultNetworkCallback(vpnCallback) }
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
   * Required by NativeEventEmitter. Marks that JS subscribed and pushes first snapshot.
   */
  @ReactMethod
  fun addListener(eventName: String) {
    hasListeners = true
    emitSnapshot()
  }

  /**
   * Required by NativeEventEmitter. Marks that JS unsubscribed.
   */
  @ReactMethod
  fun removeListeners(count: Int) {
    hasListeners = false
  }

  /**
   * Best-effort unregister of the connectivity callback.
   */
  private fun safeUnregister() {
    if (registeredDefault) {
      runCatching { cm.unregisterNetworkCallback(vpnCallback) }
        .onSuccess { registeredDefault = false }
    }
    if (registeredVpnOnly) {
      runCatching { cm.unregisterNetworkCallback(vpnCallback) }
        .onSuccess { registeredVpnOnly = false }
    }
  }

  /**
   * Emits an onStatusChanged event if the React instance is active and JS is listening.
   */
  private fun emitSnapshot() {
    if (!appContext.hasActiveCatalystInstance()) return
    runCatching { emitOnStatusChanged(buildVpnInfo()) }.onFailure { /* ignore */ }
  }

  /**
   * Returns true if any active network reports VPN transport.
   */
  private fun isVpnUp(): Boolean =
    cm.allNetworks.any { n ->
      cm.getNetworkCapabilities(n)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
    }

  /**
   * Finds the first active network that has VPN transport, if any.
   */
  private fun currentVpnNetwork(): Network? =
    cm.allNetworks.firstOrNull { n ->
      cm.getNetworkCapabilities(n)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
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
    val dns = (lp?.dnsServers ?: emptyList()).map { it.hostAddress }
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
