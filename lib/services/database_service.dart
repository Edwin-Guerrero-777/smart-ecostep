import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:smart_ecostep/models/step_data.dart';

/// Servicio centralizado para leer y escribir en Firebase Realtime Database.
///
/// Estructura de nodos:
///   /datos_esp32/<uid>/actual   → datos en tiempo real del ESP32
///   /datos_esp32/<uid>/historial/<fecha>/<push_id> → registros históricos
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── UID del usuario autenticado ───────────────────────────────────────────
  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado');
    return user.uid;
  }

  // ── Referencias ───────────────────────────────────────────────────────────

  /// Nodo con los datos actuales del ESP32
  DatabaseReference get _actualRef =>
      _db.ref('datos_esp32/$_uid/actual');

  /// Nodo del historial diario
  DatabaseReference _historialRef(String fecha) =>
      _db.ref('datos_esp32/$_uid/historial/$fecha');

  // ── Stream en tiempo real ─────────────────────────────────────────────────

  /// Emite un [StepData] cada vez que el ESP32 actualiza Firebase.
  /// Usa [StreamBuilder] en la UI para escuchar este stream.
  Stream<StepData> get stepDataStream {
    return _actualRef.onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return StepData.empty();
      return StepData.fromMap(Map<dynamic, dynamic>.from(data as Map));
    });
  }

  // ── Escritura (para pruebas / simulación desde la app) ────────────────────

  /// Escribe datos simulados del ESP32 en Firebase.
  /// Útil para probar la UI antes de tener el hardware real.
  Future<void> simularDatosESP32(StepData datos) async {
    await _actualRef.set({
      ...datos.toMap(),
      'activo': true,
    });
  }

  /// Marca el dispositivo como desconectado sin borrar los últimos valores.
  Future<void> marcarInactivo() async {
    await _actualRef.update({'activo': false});
  }

  /// Resetea el nodo /actual a valores en cero.
  Future<void> resetearDatos() async {
    await _actualRef.set(StepData.empty().toMap());
  }

  // ── Historial ─────────────────────────────────────────────────────────────

  /// Guarda un snapshot del estado actual en el historial del día.
  Future<void> guardarEnHistorial(StepData datos) async {
    final hoy = _fechaHoy();
    await _historialRef(hoy).push().set({
      ...datos.toMap(),
      'timestamp': ServerValue.timestamp,
    });
  }

  /// Lee el historial de un día específico (formato: yyyy-MM-dd).
  Future<List<StepData>> leerHistorial(String fecha) async {
    final snapshot = await _historialRef(fecha).get();
    if (!snapshot.exists || snapshot.value == null) return [];

    final raw = Map<dynamic, dynamic>.from(snapshot.value as Map);
    return raw.values
        .map((v) => StepData.fromMap(Map<dynamic, dynamic>.from(v as Map)))
        .toList()
      ..sort((a, b) => a.ultimaActualizacion.compareTo(b.ultimaActualizacion));
  }

  // ── Utilidades ────────────────────────────────────────────────────────────

  String _fechaHoy() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Reglas de Firebase Realtime DB recomendadas para este nodo:
  ///
  /// ```json
  /// {
  ///   "rules": {
  ///     "datos_esp32": {
  ///       "$uid": {
  ///         ".read": "$uid === auth.uid",
  ///         ".write": "$uid === auth.uid || auth.uid === 'ESP32_SERVICE_UID'"
  ///       }
  ///     }
  ///   }
  /// }
  /// ```
  static const String dbRulesDocumentation = 'Ver comentario en database_service.dart';
}

