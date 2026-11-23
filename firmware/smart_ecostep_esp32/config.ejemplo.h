// =====================================================================
//  CONFIGURACIÓN DE EJEMPLO — Smart Eco-Step ESP32
// ---------------------------------------------------------------------
//  Este archivo SÍ está en GitHub y NO lleva contraseñas reales.
//
//  · Si NO existe config.h, el firmware usa este archivo tal cual:
//    arranca en MODO_LOCAL 1 (el ESP32 crea la red "SmartEcoStep"),
//    que funciona sin configurar nada.
//
//  · Para usar los modos 0 (Nube) o 2 (Misma red): copia este archivo,
//    renombra la copia a  config.h  y llena tus datos ahí. config.h está
//    en .gitignore, así tus contraseñas nunca se suben a GitHub.
//    NO pongas contraseñas reales en ESTE archivo.
// =====================================================================
#pragma once

// ── MODO DE CONEXIÓN ───────────────────────────────────────────────────
//   0 = NUBE: el ESP32 se conecta a tu Wi-Fi y envía todo a Firebase.
//   1 = RED PROPIA: el ESP32 crea la red "SmartEcoStep" y la app se
//       conecta directo por WebSocket (sin internet).
//   2 = MISMA RED: el ESP32 se une a tu Wi-Fi (WIFI_SSID) y la app se
//       conecta directo por WebSocket a su IP. Todos siguen con internet.
//       La IP sale en la LCD ("IP:...") y en el Monitor Serie.
#define MODO_LOCAL 1

// ── Red propia del ESP32 (solo MODO_LOCAL = 1) ─────────────────────────
// Conecta la laptop/celular a esta red y en la app elige "Local".
#define AP_SSID        "SmartEcoStep"
#define AP_PASSWORD    "ecostep2026"   // mínimo 8 caracteres
#define PUERTO_LOCAL   3333            // modos 1 y 2; debe coincidir con la app

// ── Tu Wi-Fi con internet (MODO_LOCAL = 0 y 2) ─────────────────────────
// Debe ser una red de 2.4 GHz; el ESP32 no ve redes de 5 GHz.
#define WIFI_SSID      "TU_RED_WIFI"
#define WIFI_PASSWORD  "TU_CONTRASENA_WIFI"

// ── Cuenta de la app (solo MODO_LOCAL = 0) ─────────────────────────────
// Usa EL MISMO correo y contraseña con los que entras a la app Smart
// Eco-Step. Así el ESP32 escribe en tu carpeta y la app ve tus pisadas.
#define USER_EMAIL     "tu_correo@ejemplo.com"
#define USER_PASSWORD  "tu_contrasena_de_la_app"

// ── Proyecto de Firebase (ya está llenado, no hace falta tocarlo) ──────
#define FIREBASE_API_KEY      "AIzaSyA99XQyt-gRu1hukVr7uSOdSJge1qDm-Zg"
#define FIREBASE_DATABASE_URL "https://smart-ecostep-default-rtdb.firebaseio.com"
