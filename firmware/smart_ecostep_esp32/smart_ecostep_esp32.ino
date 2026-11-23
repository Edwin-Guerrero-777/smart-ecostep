/*
 * =====================================================================
 *  Smart Eco-Step — Firmware del tapete (ESP32-S con CH340)
 * =====================================================================
 *  Basado en el código original del tapete (LCD, 4 piezos, botón de
 *  vaciado y sensor ultrasónico HC-SR04). Todo eso sigue funcionando
 *  igual. Lo NUEVO es la conexión a la app, con 2 modos (en config.h):
 *
 *  ── MODO_LOCAL = 1 ────────────────────────────────────────────────────
 *    Piezo ──► ESP32 (crea la red Wi-Fi "SmartEcoStep") ──WebSocket──► App
 *    Sin internet, respuesta inmediata. Funciona en Chrome y en Android.
 *    Dirección: ws://192.168.4.1:3333   Cada mensaje es un JSON:
 *      {"tipo":"pisada","id":..,"carril":"arriba","voltaje":..,
 *       "energia_j":..,"potencia_w":..,"energia_total_j":..}
 *      {"tipo":"estado","activo":true,"voltaje":..,"energia_total_j":..}
 *
 *  ── MODO_LOCAL = 2 (misma red) ────────────────────────────────────────
 *    El ESP32 se une a TU Wi-Fi (WIFI_SSID) y abre el mismo WebSocket ahí.
 *    Laptop/celular siguen con internet en esa misma red. La IP del ESP32
 *    aparece en la LCD ("IP:...") y en el Monitor Serie: escríbela en la app.
 *    (No funciona en redes que aíslan dispositivos, p. ej. algunas escolares.)
 *
 *  ── MODO_LOCAL = 0 ────────────────────────────────────────────────────
 *    Piezo ──► ESP32 ──Wi-Fi──► Firebase Realtime Database ──► App
 *    Por cada pisada escribe en  datos_esp32/{uid}  (mismo formato que el
 *    botón "Simular Interacción DDR" de la app), usando la API REST.
 *
 *  NO necesita librerías extra: WiFi, WiFiServer, HTTPClient y mbedTLS
 *  (para el WebSocket) vienen con el paquete "esp32 by Espressif Systems".
 *
 *  Arquitectura (el ESP32 tiene 2 núcleos):
 *    · Núcleo 1 → loop(): lee piezos, LCD, botón y ultrasónico (como antes).
 *    · Núcleo 0 → tarea de red (tareaLocal o tareaNube).
 *    Se comunican con una cola (FreeRTOS). Así la lectura de los piezos
 *    nunca se congela esperando a la red.
 *
 *  Antes de cargar: revisa la pestaña  config.h
 *  Indicador en la LCD: un "*" en la esquina superior derecha =
 *    LOCAL → la app está conectada · NUBE → conectado a Firebase.
 * =====================================================================
 */

#include <LiquidCrystal.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include "mbedtls/sha1.h"    // WebSocket (modo local)
#include "mbedtls/base64.h"

// Configuración: usa config.h (tus datos, no se sube a GitHub). Si no
// existe —p. ej. recién descargado el proyecto— usa config.ejemplo.h,
// que arranca en MODO_LOCAL 1 (red propia) sin necesitar contraseñas.
#if __has_include("config.h")
  #include "config.h"
#else
  #include "config.ejemplo.h"
  #define USANDO_CONFIG_EJEMPLO 1
#endif

// Pantalla LCD: RS(18a), E(17a), D4(14a), D5(12a), D6(11a), D7(7a)
LiquidCrystal lcd(23, 22, 21, 19, 18, 4);

// Pines Sensores y Botón
// (32, 34, 35 y 39 son del ADC1: funcionan aunque el Wi-Fi esté encendido)
const int PIN_ARRIBA    = 32; // 13j
const int PIN_ABAJO     = 39; // 16j (VN)
const int PIN_IZQUIERDA = 34; // 15j
const int PIN_DERECHA   = 35; // 14j
const int PIN_CAPACITOR = 33; // 12j
const int PIN_BOTON     = 25; // 11j

// Pines Ultrasónico HC-SR04
const int PIN_TRIG      = 5;  // 10a
const int PIN_ECHO      = 17; // 9a (con divisor de 2 resistencias iguales)

// =======================================================
//  ZONA PARA MOVER A TU GUSTO (CAPACITOR 470 uF / 100V)
// =======================================================
const int   UMBRAL_MIN        = 300;    // Sensibilidad de pisada (general)
// Umbral por flecha (0–4095). MÁS ALTO = MENOS sensible.
// Mira en el Monitor Serie los valores "Arr: | Aba: | Izq: | Der:" al
// pisar y al NO pisar: el umbral debe quedar entre ambos.
const int   UMBRAL_ARRIBA     = 250;   // ↑ umbral propio de la flecha ARRIBA
const int   UMBRAL_ABAJO      = UMBRAL_MIN;
const int   UMBRAL_IZQUIERDA  = UMBRAL_MIN;
const int   UMBRAL_DERECHA    = UMBRAL_MIN;
const float LIMITE_CAP        = 100.0; // Tope del capacitor grande (100V)
const float VOLTS_MIN_GOLPE   = 0.20;  // Pisada suave
const float VOLTS_MAX_GOLPE   = 0.80;  // Pisada fuerte
const float BAJADA_VACIADO    = 1.0;   // Voltios que baja al apretar botón
const int   PAUSA_VACIADO_MS  = 100;   // Velocidad de vaciado
const int   DISTANCIA_CERCA   = 50;    // cm para detectar usuario cerca
// =======================================================

// =======================================================
//  CONVERSIÓN A UNIDADES REALES (para la app)
// =======================================================
const float VOLTS_POR_CUENTA  = 3.3 / 4095.0; // ADC 12 bits → voltios en el pin
const float CAP_PIEZO_F       = 10e-6;        // Capacitancia estimada por piezo (F)
const float DURACION_PULSO_S  = 0.05;         // Duración aprox. del pulso (s)
const unsigned long LATIDO_MS = 30000;        // Cada cuánto se avisa "sigo activo"
// =======================================================

float voltajeCap = 0.0;
unsigned long ultimoPrint = 0;

// ─────────────────────────────────────────────────────────────────────
//  COMÚN A LOS DOS MODOS
// ─────────────────────────────────────────────────────────────────────

/// Pisada detectada por loop() y pendiente de enviar a la app.
struct EventoPisada {
  char  carril[12];  // "arriba" | "abajo" | "izquierda" | "derecha"
  float voltaje;     // suma de los voltajes pico de los 4 piezos (V)
  float energiaJ;    // energía estimada de la pisada (J)
};

QueueHandle_t colaPisadas;        // loop() → tarea de red
volatile bool nubeLista = false;  // LOCAL/LAN: app conectada · NUBE: Firebase listo
uint32_t siguienteIdPisada = 1;   // id único por pisada (la app ignora repetidos)
char ipTexto[16] = "";            // IP del ESP32 en tu red (modo 2, se ve en la LCD)

/// Conecta (o reconecta) a tu Wi-Fi (WIFI_SSID). Devuelve true si quedó
/// conectado. Lo usan el modo NUBE (0) y el modo MISMA RED (2).
bool conectarWiFi() {
  if (WiFi.status() == WL_CONNECTED) return true;

  Serial.printf("[WIFI] Conectando a \"%s\"...\n", WIFI_SSID);
  WiFi.disconnect(true);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 15000) {
    vTaskDelay(pdMS_TO_TICKS(250));
  }
  if (WiFi.status() == WL_CONNECTED) {
    WiFi.setSleep(false);  // sin ahorro de energía → sin picos de lag
    snprintf(ipTexto, sizeof(ipTexto), "%s", WiFi.localIP().toString().c_str());
    Serial.printf("[WIFI] OK. IP: %s\n", ipTexto);
    return true;
  }
  Serial.println("[WIFI] No se pudo conectar. Revisa nombre/contraseña y que la red sea de 2.4 GHz.");
  return false;
}

#if MODO_LOCAL >= 1
// ─────────────────────────────────────────────────────────────────────
//  MODO LOCAL (1) / MISMA RED (2): servidor WebSocket (núcleo 0)
// ─────────────────────────────────────────────────────────────────────

WiFiServer servidor(PUERTO_LOCAL);
WiFiClient clienteApp;            // la app conectada (solo una a la vez)
float energiaTotalJ   = 0;        // acumulada desde que se encendió el ESP32
float ultimoVoltaje   = 0;
float ultimaPotenciaW = 0;

/// Saludo WebSocket (RFC 6455): lee la petición HTTP de la app y responde
/// "101 Switching Protocols" con la clave calculada (SHA-1 + Base64).
bool saludoWebSocket(WiFiClient& c) {
  String clave;
  unsigned long t0 = millis();
  c.setTimeout(1000);
  while (c.connected() && millis() - t0 < 2000) {
    if (!c.available()) { vTaskDelay(pdMS_TO_TICKS(5)); continue; }
    String linea = c.readStringUntil('\n');
    linea.trim();
    if (linea.length() == 0) break;          // fin de las cabeceras
    String min = linea;
    min.toLowerCase();
    if (min.startsWith("sec-websocket-key:")) {
      clave = linea.substring(18);
      clave.trim();
    }
  }
  if (clave.length() == 0) {
    Serial.println("[LOCAL] Conexión sin WebSocket (¿navegador abriendo la IP?). Ignorada.");
    return false;
  }

  String fuente = clave + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
  unsigned char hash[20];
  mbedtls_sha1((const unsigned char*)fuente.c_str(), fuente.length(), hash);
  unsigned char aceptar[32];
  size_t n = 0;
  mbedtls_base64_encode(aceptar, sizeof(aceptar), &n, hash, sizeof(hash));
  aceptar[n] = '\0';

  c.print("HTTP/1.1 101 Switching Protocols\r\n"
          "Upgrade: websocket\r\n"
          "Connection: Upgrade\r\n"
          "Sec-WebSocket-Accept: ");
  c.print((const char*)aceptar);
  c.print("\r\n\r\n");
  return true;
}

/// Envía un mensaje de texto a la app como trama WebSocket.
void enviarLinea(const String& m) {
  if (!(clienteApp && clienteApp.connected())) return;
  size_t len = m.length();
  if (len > 500) return;
  uint8_t buf[512];
  size_t i = 0;
  buf[i++] = 0x81;                     // FIN + trama de texto
  if (len < 126) {
    buf[i++] = (uint8_t)len;
  } else {
    buf[i++] = 126;
    buf[i++] = (uint8_t)(len >> 8);
    buf[i++] = (uint8_t)(len & 0xFF);
  }
  memcpy(buf + i, m.c_str(), len);
  clienteApp.write(buf, i + len);      // un solo paquete → menor latencia
}

/// Mensaje de estado: mantiene "activo" en la app y sincroniza la energía.
void enviarEstado() {
  String m = "{\"tipo\":\"estado\",\"activo\":true,\"voltaje\":";
  m += String(ultimoVoltaje, 3);
  m += ",\"potencia_w\":";      m += String(ultimaPotenciaW, 6);
  m += ",\"energia_total_j\":"; m += String(energiaTotalJ, 8);
  m += "}";
  enviarLinea(m);
}

void tareaLocal(void* parametro) {
#if MODO_LOCAL == 2
  // MISMA RED: el ESP32 se une a tu Wi-Fi y abre el WebSocket ahí
  while (!conectarWiFi()) vTaskDelay(pdMS_TO_TICKS(3000));
  servidor.begin();
  servidor.setNoDelay(true);
  Serial.printf("[LAN] En la red \"%s\". En la app escribe la IP: %s  (ws://%s:%d)\n",
                WIFI_SSID, ipTexto, ipTexto, PUERTO_LOCAL);
#else
  // RED PROPIA: el ESP32 crea la red "SmartEcoStep"
  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASSWORD);
  WiFi.setSleep(false);           // sin ahorro de energía → menor latencia
  servidor.begin();
  servidor.setNoDelay(true);
  Serial.printf("[LOCAL] Red \"%s\" creada. App → ws://%s:%d\n", AP_SSID,
                WiFi.softAPIP().toString().c_str(), PUERTO_LOCAL);
#endif

  unsigned long ultimoEstadoMs = 0;
  for (;;) {
#if MODO_LOCAL == 2
    // Si se cae el Wi-Fi, reconectar (la IP podría cambiar: se muestra de nuevo)
    if (WiFi.status() != WL_CONNECTED) {
      nubeLista = false;
      if (clienteApp) clienteApp.stop();
      if (!conectarWiFi()) { vTaskDelay(pdMS_TO_TICKS(3000)); continue; }
      Serial.printf("[LAN] Reconectado. IP: %s\n", ipTexto);
    }
#endif
    // ¿Se conectó la app? (si llega otra, reemplaza a la anterior)
    WiFiClient nuevo = servidor.accept();
    if (nuevo) {
      nuevo.setNoDelay(true);
      if (saludoWebSocket(nuevo)) {
        if (clienteApp) clienteApp.stop();
        clienteApp = nuevo;
        Serial.printf("[LOCAL] App conectada desde %s\n",
                      clienteApp.remoteIP().toString().c_str());
        enviarLinea("{\"tipo\":\"hola\",\"activo\":true,\"sensores\":4}");
        enviarEstado();
        ultimoEstadoMs = millis();
      } else {
        nuevo.stop();
      }
    }

    bool conectada = clienteApp && clienteApp.connected();
    if (nubeLista && !conectada) Serial.println("[LOCAL] App desconectada");
    nubeLista = conectada;
    while (conectada && clienteApp.available()) clienteApp.read(); // no se usa

    // Pisadas: se envían en cuanto llegan (espera máx. 20 ms)
    EventoPisada ev;
    if (xQueueReceive(colaPisadas, &ev, pdMS_TO_TICKS(20)) == pdTRUE) {
      energiaTotalJ  += ev.energiaJ;
      ultimoVoltaje   = ev.voltaje;
      ultimaPotenciaW = ev.energiaJ / DURACION_PULSO_S;
      if (conectada) {
        uint32_t id = siguienteIdPisada++;
        String m = "{\"tipo\":\"pisada\",\"id\":"; m += String(id);
        m += ",\"carril\":\"";         m += ev.carril;
        m += "\",\"voltaje\":";        m += String(ev.voltaje, 3);
        m += ",\"energia_j\":";        m += String(ev.energiaJ, 8);
        m += ",\"potencia_w\":";       m += String(ultimaPotenciaW, 6);
        m += ",\"energia_total_j\":";  m += String(energiaTotalJ, 8);
        m += "}";
        enviarLinea(m);
        Serial.printf("[LOCAL] Pisada #%lu (%s, %.2f V) enviada\n",
                      (unsigned long)id, ev.carril, ev.voltaje);
      }
    }

    // Latido cada segundo (si deja de llegar, la app sabe que se cortó)
    if (conectada && millis() - ultimoEstadoMs > 1000) {
      enviarEstado();
      ultimoEstadoMs = millis();
    }
  }
}

#else
// ─────────────────────────────────────────────────────────────────────
//  MODO NUBE: conexión a Firebase (corre en el núcleo 0)
// ─────────────────────────────────────────────────────────────────────

WiFiClientSecure clienteTls;
String   idToken;                   // "pase" de Firebase (dura 1 hora)
String   uid;                       // tu identificador de usuario
unsigned long tokenObtenidoMs = 0;
unsigned long ultimoLatidoMs  = 0;
const unsigned long VIGENCIA_TOKEN_MS = 50UL * 60UL * 1000UL; // renovar a los 50 min

/// Busca  "clave": "valor"  en un texto JSON y devuelve el valor.
String extraerCampo(const String& json, const char* clave) {
  String patron = String("\"") + clave + "\"";
  int i = json.indexOf(patron);
  if (i < 0) return "";
  i = json.indexOf(':', i + patron.length());
  if (i < 0) return "";
  int ini = json.indexOf('"', i + 1);
  if (ini < 0) return "";
  int fin = json.indexOf('"', ini + 1);
  if (fin < 0) return "";
  return json.substring(ini + 1, fin);
}

/// Hace una petición HTTPS y devuelve el código HTTP (200 = OK).
int peticionHttp(const char* metodo, const String& url, const String& cuerpo,
                 String* respuesta) {
  HTTPClient http;
  http.setTimeout(8000);
  if (!http.begin(clienteTls, url)) return -1;
  http.addHeader("Content-Type", "application/json");
  int codigo = http.sendRequest(metodo, cuerpo);
  if (respuesta) *respuesta = http.getString();
  http.end();
  return codigo;
}

/// Inicia sesión con el correo y contraseña de la app (Firebase Auth REST).
/// Obtiene el idToken (para escribir) y el uid (para saber en qué carpeta).
bool iniciarSesion() {
  String url = String("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=")
               + FIREBASE_API_KEY;
  String cuerpo = String("{\"email\":\"") + USER_EMAIL +
                  "\",\"password\":\"" + USER_PASSWORD +
                  "\",\"returnSecureToken\":true}";
  String resp;
  int codigo = peticionHttp("POST", url, cuerpo, &resp);

  if (codigo != 200) {
    Serial.printf("[AUTH] Error %d al iniciar sesión.\n", codigo);
    if (resp.indexOf("INVALID_LOGIN_CREDENTIALS") >= 0 ||
        resp.indexOf("INVALID_PASSWORD") >= 0 ||
        resp.indexOf("EMAIL_NOT_FOUND") >= 0) {
      Serial.println("[AUTH] Correo o contraseña incorrectos. Usa los mismos de la app (config.h).");
    } else {
      Serial.println(resp);
    }
    return false;
  }

  idToken = extraerCampo(resp, "idToken");
  uid     = extraerCampo(resp, "localId");
  tokenObtenidoMs = millis();
  Serial.printf("[AUTH] Sesión iniciada. uid = %s\n", uid.c_str());
  return idToken.length() > 0 && uid.length() > 0;
}

/// URL base de tus datos:  .../datos_esp32/{uid}
String rutaBase() {
  return String(FIREBASE_DATABASE_URL) + "/datos_esp32/" + uid;
}

/// Avisa a la app que el tapete está conectado (activo = true).
/// Se repite cada LATIDO_MS para mantener el timestamp al día.
void marcarActivo() {
  String url = rutaBase() + "/actual.json?auth=" + idToken;
  int codigo = peticionHttp("PATCH", url,
                            "{\"activo\":true,\"timestamp\":{\".sv\":\"timestamp\"}}",
                            nullptr);
  if (codigo == 401) idToken = "";  // token vencido → volver a iniciar sesión
  ultimoLatidoMs = millis();
}

/// Envía una pisada a Firebase en UNA sola escritura atómica (PATCH
/// multi-ruta), igual que hace el simulador de la app.
bool enviarPisada(const EventoPisada& ev) {
  uint32_t id = siguienteIdPisada++;
  String v = String(ev.voltaje, 3);
  String e = String(ev.energiaJ, 8);
  String p = String(ev.energiaJ / DURACION_PULSO_S, 6);

  String cuerpo = "{";
  // Nodo "pisada": la app lo escucha para hacer destellar la flecha.
  // El "id" DEBE cambiar en cada pisada o la app la ignora.
  cuerpo += "\"pisada\":{\"id\":";        cuerpo += String(id);
  cuerpo += ",\"carril\":\"";             cuerpo += ev.carril;
  cuerpo += "\",\"voltaje\":";            cuerpo += v;
  cuerpo += ",\"energia_j\":";            cuerpo += e;
  cuerpo += ",\"timestamp\":{\".sv\":\"timestamp\"}},";
  // Nodo "actual": métricas del dashboard.
  cuerpo += "\"actual/voltaje\":";        cuerpo += v;
  cuerpo += ",\"actual/potencia_w\":";    cuerpo += p;
  // Suma atómica en el servidor (no se pierde nada aunque haya pisadas seguidas)
  cuerpo += ",\"actual/energia_total_j\":{\".sv\":{\"increment\":"; cuerpo += e; cuerpo += "}}";
  cuerpo += ",\"actual/activo\":true";
  cuerpo += ",\"actual/timestamp\":{\".sv\":\"timestamp\"}";
  cuerpo += "}";

  String url = rutaBase() + ".json?auth=" + idToken;
  String resp;
  int codigo = peticionHttp("PATCH", url, cuerpo, &resp);

  if (codigo == 200) {
    Serial.printf("[NUBE] Pisada #%lu (%s, %.2f V) enviada a la app\n",
                  (unsigned long)id, ev.carril, ev.voltaje);
    ultimoLatidoMs = millis();
    return true;
  }

  Serial.printf("[NUBE] Error %d al enviar pisada: %s\n", codigo, resp.c_str());
  if (codigo == 401) idToken = "";  // token vencido
  if (codigo == 403 || resp.indexOf("Permission denied") >= 0) {
    Serial.println("[NUBE] Permiso denegado: revisa las reglas de Realtime Database (ver README).");
  }
  return false;
}

/// Tarea de red: mantiene Wi-Fi y sesión, y envía las pisadas de la cola.
void tareaNube(void* parametro) {
  // Sin verificación de certificado (suficiente para un prototipo).
  clienteTls.setInsecure();

  for (;;) {
    if (!conectarWiFi()) {
      nubeLista = false;
      vTaskDelay(pdMS_TO_TICKS(3000));
      continue;
    }

    // Iniciar o renovar sesión (el token de Firebase dura 1 hora)
    if (idToken.isEmpty() || millis() - tokenObtenidoMs > VIGENCIA_TOKEN_MS) {
      nubeLista = false;
      if (!iniciarSesion()) {
        vTaskDelay(pdMS_TO_TICKS(5000));
        continue;
      }
      marcarActivo();
      nubeLista = true;
      Serial.println("[NUBE] Conectado a Firebase. ¡Abre la app y pisa el tapete!");
    }

    EventoPisada ev;
    if (xQueueReceive(colaPisadas, &ev, pdMS_TO_TICKS(500)) == pdTRUE) {
      if (!enviarPisada(ev) && idToken.isEmpty()) {
        // Falló por token vencido: se devuelve a la cola y se reintenta
        // en cuanto se renueve la sesión.
        xQueueSendToFront(colaPisadas, &ev, 0);
      }
    } else if (millis() - ultimoLatidoMs > LATIDO_MS) {
      marcarActivo();
    }
  }
}
#endif  // MODO_LOCAL >= 1

// ─────────────────────────────────────────────────────────────────────
//  CÓDIGO ORIGINAL DEL TAPETE (núcleo 1)
// ─────────────────────────────────────────────────────────────────────

float leerDistanciaCm() {
  digitalWrite(PIN_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_TRIG, LOW);
  long duracion = pulseIn(PIN_ECHO, HIGH, 15000); // Máx ~2.5 metros
  if (duracion == 0) return -1.0;
  return (duracion * 0.0343) / 2.0;
}

void actualizarLCD(String linea2) {
  int porcentaje = (int)((voltajeCap / LIMITE_CAP) * 100.0);

  // Fila 1: Voltaje y Porcentaje
  lcd.setCursor(0, 0);
  lcd.print("Cap:");
  lcd.print(voltajeCap, 1);
  lcd.print("V ");
  lcd.print(porcentaje);
  lcd.print("%    ");

  // NUEVO: esquina superior derecha → "*" = app conectada (local) / Firebase listo (nube)
  lcd.setCursor(15, 0);
  lcd.print(nubeLista ? '*' : ' ');

  // Fila 2: Estado / Dirección / Distancia (rellenada con espacios para no parpadear)
  lcd.setCursor(0, 1);
  while (linea2.length() < 16) linea2 += " ";
  lcd.print(linea2.substring(0, 16));
}

void setup() {
  Serial.begin(115200);
#ifdef USANDO_CONFIG_EJEMPLO
  Serial.println("[CONFIG] Sin config.h: usando config.ejemplo.h (MODO_LOCAL 1, red \"SmartEcoStep\").");
  Serial.println("[CONFIG] Para Nube o Misma red: copia config.ejemplo.h como config.h y llena tus datos.");
#endif
  analogReadResolution(12);
  pinMode(PIN_BOTON, INPUT);
  pinMode(PIN_TRIG, OUTPUT);
  pinMode(PIN_ECHO, INPUT);

  lcd.begin(16, 2);
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Tapete Piezo OK");
  lcd.setCursor(0, 1);
  lcd.print("Iniciando...");

  // NUEVO: cola de pisadas + tarea de red en el núcleo 0
  colaPisadas = xQueueCreate(20, sizeof(EventoPisada));
  siguienteIdPisada = (esp_random() >> 4) + 1;  // id distinto tras cada reinicio
#if MODO_LOCAL == 2
  Serial.println("[MODO] MISMA RED: WebSocket dentro de tu Wi-Fi");
  xTaskCreatePinnedToCore(tareaLocal, "local", 8192, nullptr, 1, nullptr, 0);
#elif MODO_LOCAL == 1
  Serial.println("[MODO] LOCAL: red propia del ESP32 (WebSocket), sin internet");
  xTaskCreatePinnedToCore(tareaLocal, "local", 8192, nullptr, 1, nullptr, 0);
#else
  Serial.println("[MODO] NUBE: Firebase por internet");
  xTaskCreatePinnedToCore(tareaNube, "nube", 12288, nullptr, 1, nullptr, 0);
#endif

  delay(1200);
  lcd.clear();
  actualizarLCD("Esperando pisada");
}

void loop() {
  // 1. Si el botón está presionado, vaciamos el capacitor poco a poco
  if (digitalRead(PIN_BOTON) == HIGH) {
    if (voltajeCap > 0.0) {
      voltajeCap -= BAJADA_VACIADO;
      if (voltajeCap < 0.0) voltajeCap = 0.0;
      int porcentaje = (int)((voltajeCap / LIMITE_CAP) * 100.0);

      Serial.print("[VACIANDO] Cap:");
      Serial.print(voltajeCap, 2);
      Serial.print("V ("); Serial.print(porcentaje); Serial.println("%)");

      actualizarLCD("VACIANDO CARGA..");
      delay(PAUSA_VACIADO_MS);
    } else {
      actualizarLCD("SIN ENERGIA (0V)");
      delay(150);
    }
    return;
  }

  // 2. Lectura de los 4 piezoeléctricos
  int pArr = 0, pAba = 0, pIzq = 0, pDer = 0;
  unsigned long t0 = millis();

  while (millis() - t0 < 50) {
    int vArr = analogRead(PIN_ARRIBA);
    int vAba = analogRead(PIN_ABAJO);
    int vIzq = analogRead(PIN_IZQUIERDA);
    int vDer = analogRead(PIN_DERECHA);
    if (vArr > pArr) pArr = vArr;
    if (vAba > pAba) pAba = vAba;
    if (vIzq > pIzq) pIzq = vIzq;
    if (vDer > pDer) pDer = vDer;
  }

  // Cada flecha tiene su propio umbral: solo cuentan las que lo superan,
  // y de ésas gana la más fuerte. (0=arriba, 1=abajo, 2=izquierda, 3=derecha)
  const int pico[4]   = {pArr, pAba, pIzq, pDer};
  const int umbral[4] = {UMBRAL_ARRIBA, UMBRAL_ABAJO, UMBRAL_IZQUIERDA, UMBRAL_DERECHA};
  int ganadora = -1;
  for (int i = 0; i < 4; i++) {
    if (pico[i] > umbral[i] && (ganadora < 0 || pico[i] > pico[ganadora])) {
      ganadora = i;
    }
  }
  bool huboGolpe   = (ganadora >= 0);
  int  picoMax     = huboGolpe ? pico[ganadora]   : 0;
  int  umbralGolpe = huboGolpe ? umbral[ganadora] : UMBRAL_MIN;

  // 3. Suma proporcional a la fuerza del golpe
  if (huboGolpe && voltajeCap < LIMITE_CAP) {
    float proporcion = (float)(picoMax - umbralGolpe) / (4095.0 - umbralGolpe);
    float incremento = VOLTS_MIN_GOLPE + (proporcion * (VOLTS_MAX_GOLPE - VOLTS_MIN_GOLPE));
    voltajeCap += incremento;
    if (voltajeCap > LIMITE_CAP) voltajeCap = LIMITE_CAP;
  }

  // 3b. NUEVO: mandar la pisada a la app (sin esperar a internet)
  if (huboGolpe) {
    EventoPisada ev;
    const char* const claves[4] = {"arriba", "abajo", "izquierda", "derecha"};
    const char* clave = claves[ganadora];
    strncpy(ev.carril, clave, sizeof(ev.carril));
    ev.carril[sizeof(ev.carril) - 1] = '\0';

    // Voltaje: suma de los picos de los 4 piezos, en voltios
    float vA = pArr * VOLTS_POR_CUENTA, vB = pAba * VOLTS_POR_CUENTA;
    float vI = pIzq * VOLTS_POR_CUENTA, vD = pDer * VOLTS_POR_CUENTA;
    ev.voltaje  = vA + vB + vI + vD;
    // Energía estimada: Σ ½·C·V²
    ev.energiaJ = 0.5 * CAP_PIEZO_F * (vA * vA + vB * vB + vI * vI + vD * vD);

    if (xQueueSend(colaPisadas, &ev, 0) != pdTRUE) {
      Serial.println("[NUBE] Cola llena: pisada descartada (¿sin internet?)");
    }
  }

  // 4. Actualizar Monitor Serie y LCD
  if (huboGolpe || (millis() - ultimoPrint > 800)) {
    int porcentaje = (int)((voltajeCap / LIMITE_CAP) * 100.0);
    float dist = leerDistanciaCm();

    // Detectar qué dirección tuvo el golpe más fuerte
    String dirTexto = "";
    if (huboGolpe) {
      const char* const textos[4] = {"Pisada: ARRIBA", "Pisada: ABAJO",
                                     "Pisada: IZQ", "Pisada: DER"};
      dirTexto = textos[ganadora];
    }

    // Decidir qué mostrar en la fila 2 de la LCD
    String msgLCD = "";
    if (voltajeCap >= LIMITE_CAP) {
      msgLCD = "LISTO PARA USAR!";
    } else if (huboGolpe) {
      msgLCD = dirTexto;
#if MODO_LOCAL == 2
    } else if (!nubeLista && ipTexto[0] != '\0') {
      // MISMA RED: mientras la app no se conecte, mostrar la IP a escribir
      msgLCD = String("IP:") + ipTexto;
#endif
    } else if (dist > 0 && dist <= DISTANCIA_CERCA) {
      msgLCD = "Usuario: " + String((int)dist) + "cm";
    } else if (dist > 0) {
      msgLCD = "Dist: " + String((int)dist) + "cm";
    } else {
      msgLCD = "Libre / Reposo";
    }

    actualizarLCD(msgLCD);

    // Imprimir en Monitor Serie
    Serial.print(huboGolpe ? "[PISADA] " : "[REPOSO] ");
    Serial.print("Arr:"); Serial.print(pArr);
    Serial.print(" | Aba:"); Serial.print(pAba);
    Serial.print(" | Izq:"); Serial.print(pIzq);
    Serial.print(" | Der:"); Serial.print(pDer);
    Serial.print(" | Cap:"); Serial.print(voltajeCap, 2); Serial.print("V (");
    Serial.print(porcentaje); Serial.print("%)");
    Serial.print(" | Dist:"); Serial.print(dist, 1); Serial.print("cm");
    Serial.print(nubeLista ? " | Nube:OK" : " | Nube:--");

    if (voltajeCap >= LIMITE_CAP) Serial.print(" >>> LISTO <<<");
    Serial.println();

    ultimoPrint = millis();
    if (huboGolpe) delay(250);
  }
}
