import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:smart_ecostep/models/energia_data.dart';

/// Servicio centralizado para leer y escribir en Firebase Realtime Database.
///
/// Es un *singleton*: se usa siempre como `DatabaseService.instance`.
/// Ninguna pantalla debe hablar con Firebase directamente (excepto el
/// registro, que crea el perfil); así, si cambia la estructura de la base
/// de datos, solo hay que tocar este archivo.
///
/// Todas las rutas usan el `uid` del usuario con sesión iniciada, por lo que
/// cada jugador solo ve y modifica sus propios datos.
///
/// Estructura de nodos:
///   datos_esp32/{uid}/actual    → energía acumulada (voltaje, energía total…)
///   datos_esp32/{uid}/pisada    → última pisada detectada en el tapete
///   datos_esp32/{uid}/historial/{fecha}/{push_id} → registros históricos
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── UID del usuario autenticado ───────────────────────────────────────────

  /// UID del usuario actual. Lanza una excepción si no hay sesión
  /// (no debería pasar: HomeScreen solo se abre tras iniciar sesión).
  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado');
    return user.uid;
  }

  // ── Referencias ───────────────────────────────────────────────────────────
  DatabaseReference get _baseRef   => _db.ref('datos_esp32/$_uid');
  DatabaseReference get _actualRef => _baseRef.child('actual');
  DatabaseReference get _pisadaRef => _baseRef.child('pisada');
  DatabaseReference _historialRef(String fecha) =>
      _baseRef.child('historial/$fecha');

  /// XP acumulado del jugador (el nivel se calcula a partir de este número)
  DatabaseReference get _xpRef => _db.ref('usuarios/$_uid/progreso/xp_total');

  // ── Progresión (XP) ───────────────────────────────────────────────────────

  /// Emite el XP total cada vez que cambia en Firebase.
  Stream<int> get xpStream => _xpRef.onValue
      .map((e) => (e.snapshot.value as num?)?.toInt() ?? 0);

  /// Suma XP de forma atómica (seguro aunque lleguen pisadas muy seguidas).
  Future<void> sumarXp(int xp) => _xpRef.set(ServerValue.increment(xp));

  // ── Streams en tiempo real ────────────────────────────────────────────────

  /// Emite el estado de energía cada vez que el ESP32 actualiza `actual`.
  Stream<EnergiaData> get energiaStream =>
      _actualRef.onValue.map((event) {
        final data = event.snapshot.value;
        if (data is! Map) return EnergiaData.vacia();
        return EnergiaData.fromMap(data);
      });

  /// Emite cada pisada que el ESP32 escribe en `pisada`.
  ///
  /// OJO: Firebase emite el valor existente al suscribirse; quien escuche
  /// debe ignorar ese primer evento (ver HomeScreen).
  Stream<Pisada?> get pisadaStream =>
      _pisadaRef.onValue.map((event) {
        final data = event.snapshot.value;
        if (data is! Map) return null;
        return Pisada.fromMap(data);
      });

  // ── Escritura (simulación desde la app) ───────────────────────────────────

  /// Emula exactamente lo que hará el ESP32 al detectar una pisada:
  /// una sola escritura atómica que publica la pisada y suma la energía.
  Future<void> registrarPisada(Pisada p) async {
    await _baseRef.update({
      'pisada'                : {...p.toMap(), 'timestamp': ServerValue.timestamp},
      'actual/voltaje'        : p.voltaje,
      'actual/potencia_w'     : p.energiaJ / 0.05, // pulso piezo ≈ 50 ms
      'actual/energia_total_j': ServerValue.increment(p.energiaJ),
      'actual/activo'         : true,
      'actual/timestamp'      : ServerValue.timestamp,
    });
  }

  /// Marca el dispositivo como desconectado sin borrar la energía acumulada.
  Future<void> marcarInactivo() async {
    await _actualRef.update({
      'activo'    : false,
      'voltaje'   : 0,
      'potencia_w': 0,
    });
  }

  /// Pone a cero la energía acumulada.
  Future<void> resetearDatos() async {
    await _actualRef.set(EnergiaData.vacia().toMap());
  }

  // ── Historial ─────────────────────────────────────────────────────────────

  /// Guarda un snapshot del estado actual en el historial del día.
  Future<void> guardarEnHistorial(EnergiaData datos) async {
    await _historialRef(_fechaHoy()).push().set({
      ...datos.toMap(),
      'timestamp': ServerValue.timestamp,
    });
  }

  /// Lee el historial de un día específico (formato: yyyy-MM-dd).
  Future<List<EnergiaData>> leerHistorial(String fecha) async {
    final snapshot = await _historialRef(fecha).get();
    final raw = snapshot.value;
    if (raw is! Map) return [];

    return raw.values
        .whereType<Map>()
        .map(EnergiaData.fromMap)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  // ── Utilidades ────────────────────────────────────────────────────────────

  String _fechaHoy() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
