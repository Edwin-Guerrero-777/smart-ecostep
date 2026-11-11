/// Modelo de datos enviados por el ESP32 hacia Firebase Realtime Database.
///
/// Nodo en la DB: /datos_esp32/<uid>/actual
class StepData {
  /// Pasos acumulados desde el último reinicio del ESP32
  final int pasos;

  /// Distancia recorrida en metros
  final double distanciaMetros;

  /// Calorías quemadas estimadas
  final double calorias;

  /// Frecuencia cardíaca en BPM (si el sensor está disponible; -1 si no)
  final int frecuenciaCardiaca;

  /// Timestamp de la última actualización (Unix ms, generado por el servidor)
  final DateTime ultimaActualizacion;

  /// Indica si el ESP32 está activo/conectado
  final bool dispositivoActivo;

  const StepData({
    required this.pasos,
    required this.distanciaMetros,
    required this.calorias,
    required this.frecuenciaCardiaca,
    required this.ultimaActualizacion,
    required this.dispositivoActivo,
  });

  /// Crea un [StepData] vacío / estado inicial (sin conexión al ESP32)
  factory StepData.empty() => StepData(
        pasos: 0,
        distanciaMetros: 0.0,
        calorias: 0.0,
        frecuenciaCardiaca: -1,
        ultimaActualizacion: DateTime.now(),
        dispositivoActivo: false,
      );

  /// Deserializa desde el snapshot de Firebase Realtime DB
  factory StepData.fromMap(Map<dynamic, dynamic> map) {
    return StepData(
      pasos: (map['pasos'] as num? ?? 0).toInt(),
      distanciaMetros: (map['distancia_metros'] as num? ?? 0.0).toDouble(),
      calorias: (map['calorias'] as num? ?? 0.0).toDouble(),
      frecuenciaCardiaca: (map['frecuencia_cardiaca'] as num? ?? -1).toInt(),
      ultimaActualizacion: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['timestamp'] as num).toInt())
          : DateTime.now(),
      dispositivoActivo: map['activo'] as bool? ?? false,
    );
  }

  /// Serializa para escribir en Firebase (útil para pruebas / simulación)
  Map<String, dynamic> toMap() => {
        'pasos': pasos,
        'distancia_metros': distanciaMetros,
        'calorias': calorias,
        'frecuencia_cardiaca': frecuenciaCardiaca,
        'timestamp': ultimaActualizacion.millisecondsSinceEpoch,
        'activo': dispositivoActivo,
      };

  /// Distancia formateada (m o km según el valor)
  String get distanciaFormateada => distanciaMetros >= 1000
      ? '${(distanciaMetros / 1000).toStringAsFixed(2)} km'
      : '${distanciaMetros.toStringAsFixed(0)} m';

  /// Calorías formateadas con 1 decimal
  String get caloriasFormateadas => '${calorias.toStringAsFixed(1)} kcal';

  /// BPM formateado
  String get bpmFormateado =>
      frecuenciaCardiaca > 0 ? '$frecuenciaCardiaca bpm' : '-- bpm';

  StepData copyWith({
    int? pasos,
    double? distanciaMetros,
    double? calorias,
    int? frecuenciaCardiaca,
    DateTime? ultimaActualizacion,
    bool? dispositivoActivo,
  }) =>
      StepData(
        pasos: pasos ?? this.pasos,
        distanciaMetros: distanciaMetros ?? this.distanciaMetros,
        calorias: calorias ?? this.calorias,
        frecuenciaCardiaca: frecuenciaCardiaca ?? this.frecuenciaCardiaca,
        ultimaActualizacion: ultimaActualizacion ?? this.ultimaActualizacion,
        dispositivoActivo: dispositivoActivo ?? this.dispositivoActivo,
      );
}

