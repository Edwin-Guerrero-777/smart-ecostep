/// Modelos de datos del tapete piezoeléctrico Smart Eco-Step.
///
/// Nodos en Firebase Realtime Database:
///   datos_esp32/{uid}/actual  → estado acumulado de energía
///   datos_esp32/{uid}/pisada  → última pisada detectada por el ESP32
library;

/// Voltaje máximo que entrega cada sensor piezoeléctrico (límite del ADC del ESP32).
const double kVoltajeMaxSensor = 3.3;

/// Los 4 carriles del tablero (igual que las 4 flechas del tapete físico).
///
/// El tapete tiene 10 sensores piezoeléctricos repartidos entre las flechas.
enum Carril {
  izquierda('izquierda', 'Izquierda', 3),
  abajo('abajo', 'Abajo', 2),
  arriba('arriba', 'Arriba', 2),
  derecha('derecha', 'Derecha', 3);

  const Carril(this.clave, this.nombre, this.sensores);

  /// Valor que el ESP32 escribe en Firebase (`pisada/carril`)
  final String clave;

  /// Nombre legible
  final String nombre;

  /// Sensores piezoeléctricos bajo esta flecha
  final int sensores;

  /// Suma máxima posible de voltaje en una pisada sobre esta flecha
  double get voltajeMaximo => sensores * kVoltajeMaxSensor;

  /// Convierte el texto que llega de Firebase en un [Carril].
  /// Devuelve null si el valor no corresponde a ninguna flecha.
  static Carril? desdeClave(Object? clave) {
    for (final c in Carril.values) {
      if (c.clave == clave) return c;
    }
    return null;
  }
}

/// Estado de energía acumulado que publica el ESP32.
///
/// Nodo: datos_esp32/{uid}/actual
class EnergiaData {
  /// Suma de voltajes de la última pisada (V)
  final double voltaje;

  /// Energía total generada en la sesión (J)
  final double energiaTotalJ;

  /// Potencia instantánea de la última pisada (W)
  final double potenciaW;

  /// true mientras el ESP32 está conectado y enviando
  final bool activo;

  /// Última actualización
  final DateTime timestamp;

  const EnergiaData({
    required this.voltaje,
    required this.energiaTotalJ,
    required this.potenciaW,
    required this.activo,
    required this.timestamp,
  });

  /// Estado inicial: todo en cero y dispositivo desconectado.
  factory EnergiaData.vacia() => EnergiaData(
        voltaje      : 0,
        energiaTotalJ: 0,
        potenciaW    : 0,
        activo       : false,
        timestamp    : DateTime.now(),
      );

  /// Lee el nodo `actual` de Firebase. Los campos que falten valen 0/false,
  /// así un dato incompleto del ESP32 nunca rompe la app.
  factory EnergiaData.fromMap(Map<dynamic, dynamic> map) => EnergiaData(
        voltaje      : (map['voltaje'] as num? ?? 0).toDouble(),
        energiaTotalJ: (map['energia_total_j'] as num? ?? 0).toDouble(),
        potenciaW    : (map['potencia_w'] as num? ?? 0).toDouble(),
        activo       : map['activo'] as bool? ?? false,
        timestamp    : map['timestamp'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (map['timestamp'] as num).toInt())
            : DateTime.now(),
      );

  /// Formato para escribir en Firebase (mismas claves que usa el ESP32).
  Map<String, dynamic> toMap() => {
        'voltaje'        : voltaje,
        'energia_total_j': energiaTotalJ,
        'potencia_w'     : potenciaW,
        'activo'         : activo,
        'timestamp'      : timestamp.millisecondsSinceEpoch,
      };

  /// "12.4 V"
  static String formatearVoltaje(double v) => '${v.toStringAsFixed(1)} V';

  /// mJ si es menor a 1 J, si no J
  static String formatearEnergia(double j) => j < 0.01
      ? '${(j * 1000).toStringAsFixed(2)} mJ'
      : j < 1
          ? '${(j * 1000).toStringAsFixed(1)} mJ'
          : '${j.toStringAsFixed(2)} J';

  /// mW si es menor a 1 W, si no W
  static String formatearPotencia(double w) => w < 1
      ? '${(w * 1000).toStringAsFixed(0)} mW'
      : '${w.toStringAsFixed(2)} W';
}

/// Una pisada detectada sobre el tapete.
///
/// Nodo: datos_esp32/{uid}/pisada
class Pisada {
  /// Identificador incremental. La app lo usa para no procesar
  /// dos veces la misma pisada (el ESP32 debe cambiarlo en cada pisada).
  final int id;

  /// Flecha del tapete que se pisó
  final Carril carril;

  /// Suma de los voltajes de los sensores de la flecha en este impacto (V).
  /// Máximo: carril.sensores × 3.3 V.
  final double voltaje;

  /// Energía generada por esta pisada (J)
  final double energiaJ;

  const Pisada({
    required this.id,
    required this.carril,
    required this.voltaje,
    required this.energiaJ,
  });

  /// Devuelve null si el nodo está vacío o el carril no es válido.
  static Pisada? fromMap(Map<dynamic, dynamic> map) {
    final carril = Carril.desdeClave(map['carril']);
    final id     = map['id'];
    if (carril == null || id is! num) return null;
    return Pisada(
      id      : id.toInt(),
      carril  : carril,
      voltaje : (map['voltaje'] as num? ?? 0).toDouble(),
      energiaJ: (map['energia_j'] as num? ?? 0).toDouble(),
    );
  }

  /// Formato para escribir en Firebase (lo usa el simulador).
  Map<String, dynamic> toMap() => {
        'id'       : id,
        'carril'   : carril.clave,
        'voltaje'  : voltaje,
        'energia_j': energiaJ,
      };
}
