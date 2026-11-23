package com.example.smart_ecostep

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Actividad principal de Android.
 *
 * Además de lo normal de Flutter, expone el canal "smart_ecostep/red" para
 * el MODO LOCAL:
 *
 * Problema: cuando el celular se conecta a la red del ESP32 ("SmartEcoStep"),
 * esa red NO tiene internet. Android lo detecta y sigue mandando el tráfico
 * de las apps por los datos móviles, así que la app nunca llega a
 * 192.168.4.1 aunque el Wi-Fi diga "conectado".
 *
 * Solución: "usarWifiLocal" ata (bind) todo el tráfico de esta app a la red
 * Wi-Fi; "liberarRed" lo devuelve a la red por defecto (al volver a Nube).
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smart_ecostep/red")
            .setMethodCallHandler { call, result ->
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                when (call.method) {
                    "usarWifiLocal" -> {
                        val wifi = buscarWifi(cm)
                        result.success(wifi != null && atarProceso(cm, wifi))
                    }
                    "liberarRed" -> {
                        atarProceso(cm, null)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Devuelve la red Wi-Fi activa. Si hay varias, prefiere la del ESP32
     * (la que da direcciones 192.168.4.x).
     */
    @Suppress("DEPRECATION")
    private fun buscarWifi(cm: ConnectivityManager): Network? {
        val wifis = cm.allNetworks.filter { red ->
            cm.getNetworkCapabilities(red)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
        return wifis.firstOrNull { red ->
            cm.getLinkProperties(red)?.linkAddresses?.any {
                it.address.hostAddress?.startsWith("192.168.4.") == true
            } == true
        } ?: wifis.firstOrNull()
    }

    /** Ata (o con null, desata) el tráfico de toda la app a una red. */
    @Suppress("DEPRECATION")
    private fun atarProceso(cm: ConnectivityManager, red: Network?): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            cm.bindProcessToNetwork(red)
        } else {
            ConnectivityManager.setProcessDefaultNetwork(red)
        }
}
