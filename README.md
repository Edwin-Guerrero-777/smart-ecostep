# Smart Eco-Step

**Generación de energía con los pies, en formato videojuego.** El usuario pisa un tapete fijo con 4 flechas (izquierda, abajo, arriba, derecha) que tiene **sensores piezoeléctricos**. Cada pisada genera electricidad. Un **ESP32** mide el pulso y lo publica en **Firebase Realtime Database**, y la app en **Flutter** lo muestra en vivo con una mecánica visual de juego de ritmo: flechas que caen, destellos neón y combos.

---

## Funcionalidades

- **Cuentas de usuario** con Firebase Authentication (registro e inicio de sesión con correo y contraseña).
- **Dashboard de energía**, que muestra solo métricas eléctricas:
  - **Voltaje actual**: pico de la última pisada (V).
  - **Energía total**: acumulada en la sesión (mJ / J), junto con la potencia de la última pisada (mW / W).
  - **Combo de pisadas**: pisadas seguidas sin pausa y combo máximo.
- **Tablero de 4 carriles** con flechas que caen hacia la **Zona de Captura**.
- **Reacción a cada pisada real**: la flecha del carril destella en neón, aparece un texto flotante ("+ Voltaje!" o "+ Energía") y el combo sube.
  - Si pisas cuando una flecha está en la Zona de Captura, cuenta como **¡PERFECTO!** o **¡BIEN!** y muestra "+ Energía".
  - Una pisada libre muestra "+ Voltaje!".
  - Si pasan 2.5 s sin pisar, el combo vuelve a 0.
- **Progresión y gamificación**:
  - **Voltaje → XP**: conversión directa, 1 V = 1 XP. Una pisada típica da de 5 a 25 XP.
  - **Barra de nivel neón**: se llena con el XP y, al completarse, aparece una celebración con explosión de partículas.
  - **Dificultades desbloqueables**: las flechas caen más rápido y más seguido. Al desbloquear una nueva aparece un toast neón.
  - **Podio**: botón 🏆 junto a la barra de nivel. Abre un ranking (simulado) de quienes más energía (XP) han generado.
- **Botón "Simular Interacción DDR"** para probar todo sin el tapete (ver más abajo).

### Física del tapete

El tapete tiene **10 sensores piezoeléctricos** repartidos bajo las flechas: ← 3, ↓ 2, ↑ 2, → 3. Cada sensor entrega de 0 a **3.3 V** según la fuerza.

Una pisada hace reaccionar a **los 10 a la vez**: los de la flecha pisada por impacto directo y el resto por vibración. El ESP32 envía la **suma de los 10**, que en una pisada típica va de **5 a 25 V**. El máximo físico es 10 × 3.3 = **33 V**, y la app recorta cualquier valor mayor para que una lectura errónea no regale XP.

### Curva de nivel (exponencial)

```
XP para subir del nivel n = 100 · n^1.6 · 1.4^max(0, n − 2)
```

- `100 · n^1.6` es una subida suave: los niveles 1 y 2 son rápidos, para enganchar.
- `1.4^(n − 2)` es la rampa exponencial. Empieza a actuar en el nivel 3 y convierte cada nivel siguiente en una prueba de resistencia.

| Nivel | XP para subir | XP acumulado | ≈ pisadas (15 V promedio) |
|:-----:|--------------:|-------------:|--------------------------:|
| 1     | 100           | 0            | 7                         |
| 2     | 303           | 100          | 20                        |
| 3     | 812           | 403          | 54                        |
| 4     | 1 801         | 1 215        | 120                       |
| 5     | 3 604         | 3 016        | 240                       |
| 6     | 6 754         | 6 620        | 450                       |
| 7     | 12 100        | 13 374       | 807                       |
| 10    | 58 752        | 81 905       | 3 917                     |

### Dificultad (velocidad de las flechas)

Desde el nivel 5 el reto es casi extremo: la flecha cruza el tablero en menos de un segundo, la etiqueta se pone roja con 🔥 y hasta el jugador simulado empieza a fallar.

| Dificultad | Desde nivel | Caída de flecha | Velocidad |
|------------|:-----------:|:---------------:|:---------:|
| Normal     | 1           | 2.2 s           | 1.0×      |
| Difícil    | 3           | 1.5 s           | 1.5×      |
| Extremo    | 5           | 0.9 s           | 2.4×      |
| Leyenda    | 7           | 0.7 s           | 3.1×      |
| Imposible  | 10          | 0.55 s          | 4.0×      |

Todas estas reglas están en [`lib/game/progresion.dart`](lib/game/progresion.dart). Para ajustar el balance, cambia `base`, `exponente` o `rampa`.
- Tema oscuro **"Ocean Blue Serenity"** con acentos cyan neón.

---

## Arquitectura

```
┌────────────┐        ┌──────────┐  Wi-Fi  ┌───────────────────────────┐  onValue  ┌─────────────┐
│ Tapete     │ pulso  │  ESP32   │ ──────▶ │ Firebase Realtime DB      │ ────────▶ │ App Flutter │
│ piezo ×4   │ ─────▶ │  ADC     │ escribe │ /datos_esp32/<uid>/actual │           │ tablero DDR │
└────────────┘        └──────────┘         │ /datos_esp32/<uid>/pisada │           └─────────────┘
                                           └───────────────────────────┘
```

### Estructura del código

```
lib/
├── main.dart                     # Punto de entrada, inicializa Firebase, tema y paleta AppColors
├── firebase_options.dart         # Configuración generada por FlutterFire CLI
├── models/
│   └── energia_data.dart         # Carril, EnergiaData y Pisada
├── game/
│   ├── ddr_controller.dart       # Motor del tablero: flechas, destellos, textos y combo
│   └── progresion.dart           # Voltaje → XP, niveles y dificultades
├── widgets/
│   └── efectos_neon.dart         # Celebración de nivel (partículas) y toast de dificultad
├── services/
│   └── database_service.dart     # Lectura y escritura en Realtime Database (singleton)
└── screens/
    ├── login_screen.dart         # Inicio de sesión
    ├── register_screen.dart      # Registro de cuenta (+ nodo /usuarios/<uid>)
    ├── podio_sheet.dart          # Podio / leaderboard (ranking simulado)
    └── home_screen.dart          # Dashboard de energía + tablero DDR + simulador
test/
└── widget_test.dart              # Pruebas del motor DDR y del modelo
```

---

## Estructura de la base de datos

```
/usuarios/<uid>
    uid, nombre, correo, creado_en, activo
    progreso/xp_total : int   (XP acumulado; el nivel se calcula a partir de este valor)

/datos_esp32/<uid>/actual                 ← estado acumulado de energía
    voltaje         : double   (V, pico de la última pisada)
    energia_total_j : double   (J acumulados)
    potencia_w      : double   (W de la última pisada)
    activo          : bool     (true mientras el ESP32 está conectado)
    timestamp       : int      (Unix en milisegundos)

/datos_esp32/<uid>/pisada                 ← última pisada detectada
    id        : int      (DEBE cambiar en cada pisada, por ejemplo un contador)
    carril    : string   ("izquierda" | "abajo" | "arriba" | "derecha")
    voltaje   : double   (V)
    energia_j : double   (J de esta pisada)
    timestamp : int

/datos_esp32/<uid>/historial/<yyyy-MM-dd>/<push_id>   ← registros históricos
```

### Contrato para el firmware del ESP32

Por cada pisada, el ESP32 hace **una sola escritura multi-ruta** (`update`) sobre `/datos_esp32/<uid>`:

```json
{
  "pisada":                 { "id": 42, "carril": "arriba", "voltaje": 18.3, "energia_j": 0.0017 },
  "actual/voltaje":         18.3,
  "actual/potencia_w":      0.034,
  "actual/energia_total_j": { ".sv": { "increment": 0.0017 } },
  "actual/activo":          true,
  "actual/timestamp":       { ".sv": "timestamp" }
}
```

> ⚠️ La app detecta una pisada nueva cuando cambia `pisada/id`. Si el ESP32 repite el mismo `id`, la pisada se ignora. Si no envía `activo: true`, las flechas no caen, aunque las pisadas sí se registran.

### Reglas de seguridad recomendadas

```json
{
  "rules": {
    "usuarios": {
      "$uid": {
        ".read": "$uid === auth.uid",
        ".write": "$uid === auth.uid"
      }
    },
    "datos_esp32": {
      "$uid": {
        ".read": "$uid === auth.uid",
        ".write": "$uid === auth.uid"
      }
    }
  }
}
```

Con estas reglas, el ESP32 debe autenticarse en Firebase con la **misma cuenta del usuario**. Así su `uid` coincide con el nodo en el que escribe.

---

## Requisitos

- Flutter **3.41** o superior (SDK de Dart `^3.11.4`)
- Un proyecto de Firebase con **Authentication (correo/contraseña)** y **Realtime Database** habilitados
- Android Studio o VS Code, y un dispositivo o emulador Android
- (Opcional) El tapete con 10 sensores piezoeléctricos conectados a un ESP32

### Dependencias principales

| Paquete             | Uso                                 |
|---------------------|-------------------------------------|
| `firebase_core`     | Inicialización de Firebase          |
| `firebase_auth`     | Registro e inicio de sesión         |
| `firebase_database` | Lectura y escritura en tiempo real  |

---

## Instalación y ejecución

```bash
# 1. Clonar el repositorio
git clone <url-del-repositorio>
cd smart_ecostep

# 2. Instalar dependencias
flutter pub get

# 3. (Solo si usas tu propio proyecto de Firebase) regenerar la configuración
dart pub global activate flutterfire_cli
flutterfire configure

# 4. Ejecutar
flutter run
```

---

## Probar sin hardware: "Simular Interacción DDR"

1. Inicia sesión en la app.
2. Pulsa **SIMULAR INTERACCIÓN DDR**, debajo del tablero.
3. Las flechas empiezan a caer. Un "jugador virtual" pisa cada flecha justo cuando llega a la Zona de Captura. Acierta ~90 % de las veces, con un pequeño error humano en el tiempo.
4. Cada pisada simulada se **escribe en Firebase con el mismo formato que usará el ESP32**:
   - suma de los 10 piezos entre **5 y 25 V** por pisada (cada sensor ≤ 3.3 V; la flecha pisada aporta más que el resto)
   - energía ≈ Σ ½·C·Vᵢ² con C = 10 µF por sensor
   - el jugador virtual acierta el 92 % en Normal y baja hasta el 60 % en Imposible
   - con la curva exponencial, el nivel 3 llega en unos 20 s de simulación, el nivel 5 en unos 2–3 minutos y el nivel 7 en más de 8 minutos
5. Pulsa **DETENER SIMULACIÓN** para parar. La energía acumulada se conserva y el dispositivo queda como inactivo.

Como la app reacciona al evento que **vuelve** de Firebase y no a un evento local, el simulador también prueba la conexión completa.

---

## Pruebas

```bash
flutter test
```

---

## Estado del proyecto

- [x] **Fase 1**: autenticación, registro de usuarios, estructura de la base de datos y diseño de la interfaz
- [x] **Fase 2 (app)**: dashboard de energía, tablero DDR animado y simulador
- [x] **Gamificación**: XP por voltaje, niveles, dificultades desbloqueables y Podio (simulado)
- [ ] **Podio real**: leer el ranking de `usuarios/*/progreso/xp_total` (requiere ajustar las reglas de lectura)
- [ ] **Fase 2 (hardware)**: firmware del ESP32 leyendo los 4 piezos y publicando pisadas
- [ ] **Fase 3**: historial diario con gráficas de energía generada

---

## Licencia

Proyecto académico / personal. Define aquí la licencia que prefieras (por ejemplo, MIT).
