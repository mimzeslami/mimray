package com.mimray.mimray

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import android.util.Log
import io.nekohasekai.libbox.BridgeOptions
import io.nekohasekai.libbox.BridgeSession
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.ExchangeContext
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NeighborUpdateListener
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.PlatformUser
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.ShellSession
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InterfaceAddress
import java.net.UnknownHostException
import io.nekohasekai.libbox.Notification as BoxNotification
import io.nekohasekai.libbox.NetworkInterface as BoxInterface
import java.net.NetworkInterface as JavaInterface

/**
 * Runs the sing-box core (libbox) inside Android's VpnService.
 * Started by MainActivity with the config JSON the Dart side built; reports
 * status changes through [listener]. Same config as desktop: the tun inbound is
 * served by [openTun], the core's own sockets are kept out of the tunnel by
 * [autoDetectInterfaceControl] (protect), and proxy-server hostnames resolve on
 * the real network via [localDNSTransport].
 */
class MimrayVpnService : VpnService(), PlatformInterface, CommandServerHandler {
    companion object {
        const val ACTION_START = "com.mimray.vpn.START"
        const val ACTION_STOP = "com.mimray.vpn.STOP"
        const val EXTRA_CONFIG = "config"
        private const val CHANNEL = "vpn"
        private const val NOTIFICATION_ID = 1
        private const val TAG = "mimray"

        @Volatile var status = "stopped"
            private set

        /** (status, error) — set by MainActivity; called from any thread. */
        @Volatile var listener: ((String, String?) -> Unit)? = null

        private var setupDone = false

        @Synchronized
        fun setup(ctx: Context) {
            if (setupDone) return
            val work = ctx.filesDir.resolve("box").apply { mkdirs() }
            Libbox.setup(SetupOptions().apply {
                basePath = ctx.filesDir.path
                workingPath = work.path
                tempPath = ctx.cacheDir.path
                logMaxLines = 1000
            })
            setupDone = true
        }
    }

    private var server: CommandServer? = null
    private var tun: ParcelFileDescriptor? = null
    private val connectivity by lazy { getSystemService(ConnectivityManager::class.java) }
    private var netCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var defaultNetwork: Network? = null
    @Volatile private var interfaceListener: InterfaceUpdateListener? = null

    private fun report(s: String, error: String? = null) {
        status = s
        listener?.invoke(s, error)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                if (config == null || status != "stopped") return START_NOT_STICKY
                goForeground()
                report("starting")
                Thread({ start(config) }, "mimray-start").start()
            }
            ACTION_STOP -> Thread({ stop(null) }, "mimray-stop").start()
        }
        return START_NOT_STICKY
    }

    private fun start(config: String) {
        try {
            setup(this)
            startNetworkMonitor()
            val s = CommandServer(this, this)
            s.start()
            server = s
            s.startOrReloadService(config, OverrideOptions())
            report("started")
        } catch (e: Exception) {
            Log.e(TAG, "start failed", e)
            stop(e.message ?: e.toString())
        }
    }

    @Synchronized
    private fun stop(error: String?) {
        if (status == "stopped") return
        runCatching { server?.closeService() }
        runCatching { server?.close() }
        server = null
        runCatching { tun?.close() }
        tun = null
        stopNetworkMonitor()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION") stopForeground(true)
        }
        stopSelf()
        report("stopped", error)
    }

    override fun onRevoke() {
        // another VPN app took over, or the user revoked permission in Settings
        Thread({ stop("VPN permission was revoked") }, "mimray-stop").start()
    }

    override fun onDestroy() {
        stop(null)
        super.onDestroy()
    }

    private fun goForeground() {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "VPN status", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, MimrayVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        val n = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("mimray")
            .setContentText("VPN is on")
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Disconnect", stop).build())
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    // --- default network tracking (the core binds outgoing traffic to it) ---

    private fun startNetworkMonitor() {
        defaultNetwork = connectivity.activeNetwork
        if (netCallback != null) return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = update(network)
            override fun onLinkPropertiesChanged(network: Network, lp: android.net.LinkProperties) = update(network)
            override fun onLost(network: Network) {
                if (network == defaultNetwork) update(null)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            connectivity.registerBestMatchingNetworkCallbackCompat(cb)
        } else {
            connectivity.registerDefaultNetworkCallback(cb)
        }
        netCallback = cb
    }

    /** The default network *outside* the VPN (not our own tunnel). */
    private fun ConnectivityManager.registerBestMatchingNetworkCallbackCompat(cb: ConnectivityManager.NetworkCallback) {
        val req = android.net.NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            registerBestMatchingNetworkCallback(req, cb, android.os.Handler(android.os.Looper.getMainLooper()))
        } else {
            registerNetworkCallback(req, cb) // passive: never brings up a network by itself
        }
    }

    private fun stopNetworkMonitor() {
        netCallback?.let { runCatching { connectivity.unregisterNetworkCallback(it) } }
        netCallback = null
    }

    private fun update(network: Network?) {
        defaultNetwork = network
        val l = interfaceListener ?: return
        if (network == null) {
            l.updateDefaultInterface("", -1, false, false)
            return
        }
        val name = connectivity.getLinkProperties(network)?.interfaceName ?: return
        val index = runCatching { JavaInterface.getByName(name).index }.getOrDefault(-1)
        l.updateDefaultInterface(name, index, false, false)
    }

    // --- PlatformInterface ---

    override fun usePlatformAutoDetectInterfaceControl() = true

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd) // keep the core's own connections out of the tunnel
    }

    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) error("VPN permission missing")
        val b = Builder().setSession("mimray").setMtu(options.mtu)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) b.setMetered(false)
        options.inet4Address.let { while (it.hasNext()) it.next().let { a -> b.addAddress(a.address(), a.prefix()) } }
        options.inet6Address.let { while (it.hasNext()) it.next().let { a -> b.addAddress(a.address(), a.prefix()) } }
        if (options.autoRoute) {
            runCatching { options.dnsServerAddress }.getOrNull()?.let { while (it.hasNext()) b.addDnsServer(it.next()) }
            val r4 = options.inet4RouteRange
            if (r4.hasNext()) while (r4.hasNext()) r4.next().let { b.addRoute(it.address(), it.prefix()) }
            else b.addRoute("0.0.0.0", 0)
            val r6 = options.inet6RouteRange
            if (r6.hasNext()) while (r6.hasNext()) r6.next().let { b.addRoute(it.address(), it.prefix()) }
            else if (options.inet6Address.hasNext()) b.addRoute("::", 0)
        }
        val pfd = b.establish() ?: error("VPN permission missing or revoked")
        tun = pfd
        return pfd.fd
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        interfaceListener = listener
        update(defaultNetwork)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        interfaceListener = null
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val all = JavaInterface.getNetworkInterfaces()?.toList() ?: emptyList()
        val out = mutableListOf<BoxInterface>()
        for (network in connectivity.allNetworks) {
            val lp = connectivity.getLinkProperties(network) ?: continue
            val caps = connectivity.getNetworkCapabilities(network) ?: continue
            val ni = all.find { it.name == lp.interfaceName } ?: continue
            out += BoxInterface().apply {
                name = ni.name
                index = ni.index
                runCatching { mtu = ni.mtu }
                addresses = Strings(ni.interfaceAddresses.map { it.prefix() })
                dnsServer = Strings(lp.dnsServers.mapNotNull { it.hostAddress })
                type = when {
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                    else -> Libbox.InterfaceTypeOther
                }
                var f = 0
                if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) f = OsConstants.IFF_UP or OsConstants.IFF_RUNNING
                if (ni.isLoopback) f = f or OsConstants.IFF_LOOPBACK
                if (ni.isPointToPoint) f = f or OsConstants.IFF_POINTOPOINT
                if (ni.supportsMulticast()) f = f or OsConstants.IFF_MULTICAST
                flags = f
                metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            }
        }
        val it = out.iterator()
        return object : NetworkInterfaceIterator {
            override fun hasNext() = it.hasNext()
            override fun next() = it.next()
        }
    }

    private fun InterfaceAddress.prefix(): String {
        val host = if (address is Inet6Address) address.hostAddress!!.substringBefore('%') else address.hostAddress!!
        return "$host/$networkPrefixLength"
    }

    /** Resolves names (e.g. the proxy server's host) on the real network, not through the tunnel. */
    override fun localDNSTransport(): LocalDNSTransport = object : LocalDNSTransport {
        override fun raw() = false
        override fun exchange(ctx: ExchangeContext, message: ByteArray) = error("raw DNS not supported")
        override fun lookup(ctx: ExchangeContext, network: String, domain: String) {
            val n = defaultNetwork ?: connectivity.activeNetwork ?: error("no network")
            try {
                val all = n.getAllByName(domain).filter {
                    when {
                        network.endsWith("4") -> it is Inet4Address
                        network.endsWith("6") -> it is Inet6Address
                        else -> true
                    }
                }
                ctx.success(all.mapNotNull { it.hostAddress }.joinToString("\n"))
            } catch (e: UnknownHostException) {
                ctx.errorCode(3) // NXDOMAIN
            }
        }
    }

    override fun findConnectionOwner(
        ipProtocol: Int, sourceAddress: String, sourcePort: Int,
        destinationAddress: String, destinationPort: Int,
    ): ConnectionOwner = error("not supported")

    override fun underNetworkExtension() = false
    override fun includeAllNetworks() = false
    override fun readWIFIState(): WIFIState? = null
    override fun clearDNSCache() {}
    override fun sendNotification(notification: BoxNotification) {}
    override fun cancelNotification(identifier: String, typeID: Int) {}
    override fun startNeighborMonitor(listener: NeighborUpdateListener) {}
    override fun closeNeighborMonitor(listener: NeighborUpdateListener) {}
    override fun registerMyInterface(name: String) {}
    override fun usePlatformShell() = false
    override fun checkPlatformShell() = error("not supported")
    override fun openShellSession(
        user: PlatformUser, command: String, environ: StringIterator,
        term: String, rows: Int, cols: Int,
    ): ShellSession = error("not supported")
    override fun lookupUser(username: String): PlatformUser = error("not supported")
    override fun lookupSFTPServer(): String = error("not supported")
    override fun readSystemSSHHostKey(): String = error("not supported")
    override fun tailscaleHostname() = ""
    override fun usePlatformBridge() = false
    override fun createBridge(options: BridgeOptions): BridgeSession = error("not supported")

    // --- CommandServerHandler ---

    override fun serviceStop() {
        Thread({ stop(null) }, "mimray-stop").start()
    }
    override fun serviceReload() {}
    override fun getSystemProxyStatus() = SystemProxyStatus()
    override fun setSystemProxyEnabled(enabled: Boolean) {}
    override fun triggerNativeCrash() {}
    override fun writeDebugMessage(message: String) {
        Log.d(TAG, message)
    }
    override fun connectSSHAgent(): Int = error("not supported")

    private class Strings(private val list: List<String>) : StringIterator {
        private val it = list.iterator()
        override fun hasNext() = it.hasNext()
        override fun next(): String = it.next()
        override fun len() = list.size
    }
}
