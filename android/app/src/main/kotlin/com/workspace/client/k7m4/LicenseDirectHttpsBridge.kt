package com.workspace.client.k7m4

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/**
 * Narrow fallback used only for the activation service.
 *
 * If a VPN route cannot reach the VPS, this bridge retries the same HTTPS URL
 * on a validated physical network. Certificate and hostname verification remain
 * enabled because HttpsURLConnection still connects to license.apixb.top.
 */
class LicenseDirectHttpsBridge(context: Context) {
    companion object {
        private const val CHANNEL = "app.license_direct_https"
        private const val ALLOWED_HOST = "license.apixb.top"
    }

    private val appContext = context.applicationContext
    private val connectivity =
        appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val mainHandler = Handler(Looper.getMainLooper())

    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "request") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val url = call.argument<String>("url").orEmpty()
            val method = call.argument<String>("method").orEmpty().uppercase()
            @Suppress("UNCHECKED_CAST")
            val headers =
                (call.argument<Map<Any?, Any?>>("headers") ?: emptyMap())
                    .entries
                    .associate { it.key.toString() to it.value.toString() }
            val body = call.argument<String>("body")

            Thread {
                try {
                    val response = request(
                        url = url,
                        method = method,
                        headers = headers,
                        body = body,
                    )
                    mainHandler.post { result.success(response) }
                } catch (error: Exception) {
                    mainHandler.post {
                        result.error(
                            "DIRECT_HTTPS_FAILED",
                            error.message ?: "Direct HTTPS request failed.",
                            null,
                        )
                    }
                }
            }.start()
        }
    }

    private fun request(
        url: String,
        method: String,
        headers: Map<String, String>,
        body: String?,
    ): Map<String, Any> {
        val parsed = URL(url)
        require(parsed.protocol.equals("https", ignoreCase = true)) {
            "Direct fallback requires HTTPS."
        }
        require(parsed.host.equals(ALLOWED_HOST, ignoreCase = true)) {
            "Direct fallback is restricted to the activation service."
        }
        require(method in setOf("GET", "POST", "PATCH", "DELETE")) {
            "Unsupported HTTP method."
        }

        val networks = connectivity.allNetworks
            .mapNotNull { network ->
                val capabilities =
                    connectivity.getNetworkCapabilities(network) ?: return@mapNotNull null
                if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
                    !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                ) {
                    return@mapNotNull null
                }
                val validated =
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                val preference = when {
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 0
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 1
                    else -> 2
                }
                Triple(network, validated, preference)
            }
            .sortedWith(
                compareByDescending<Triple<Network, Boolean, Int>> { it.second }
                    .thenBy { it.third },
            )

        if (networks.isEmpty()) {
            throw IllegalStateException("No non-VPN network is available.")
        }

        var lastError: Exception? = null
        for ((network, _, _) in networks) {
            try {
                return requestOnNetwork(
                    network = network,
                    url = parsed,
                    method = method,
                    headers = headers,
                    body = body,
                )
            } catch (error: Exception) {
                lastError = error
            }
        }

        throw lastError ?: IllegalStateException("Direct HTTPS request failed.")
    }

    private fun requestOnNetwork(
        network: Network,
        url: URL,
        method: String,
        headers: Map<String, String>,
        body: String?,
    ): Map<String, Any> {
        val connection = network.openConnection(url) as HttpsURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 8_000
            connection.readTimeout = 12_000
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            headers.forEach { (name, value) ->
                connection.setRequestProperty(name, value)
            }

            if (body != null) {
                connection.doOutput = true
                connection.outputStream.bufferedWriter(Charsets.UTF_8).use {
                    it.write(body)
                }
            }

            val status = connection.responseCode
            val stream =
                if (status in 200..299) connection.inputStream else connection.errorStream
            val responseBody = stream
                ?.bufferedReader(Charsets.UTF_8)
                ?.use { it.readText() }
                .orEmpty()

            return mapOf(
                "statusCode" to status,
                "body" to responseBody,
            )
        } finally {
            connection.disconnect()
        }
    }
}
