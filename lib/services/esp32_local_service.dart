/// Conexión DIRECTA con el ESP32, sin internet ni Firebase (modo Local).
///
/// El ESP32 crea su propia red Wi-Fi ("SmartEcoStep") y abre un servidor
/// **WebSocket** en `ws://192.168.4.1:3333`. Se usa WebSocket (y no TCP
/// puro) porque es lo único que permiten los navegadores: así el modo Local
/// funciona igual en Chrome, Android y Windows.
///
/// Cada mensaje es un JSON:
/// ```
/// {"tipo":"hola","activo":true,"sensores":4}
/// {"tipo":"estado","activo":true,"voltaje":1.2,"potencia_w":0.001,"energia_total_j":0.0004}
/// {"tipo":"pisada","id":42,"carril":"arriba","voltaje":4.1,"energia_j":0.00004,
///  "potencia_w":0.0008,"energia_total_j":0.0012}
/// ```
///
/// Expone los MISMOS streams que [DatabaseService] (`energiaStream` y
/// `pisadaStream`), así que la pantalla principal funciona igual con
/// cualquiera de las dos fuentes.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:smart_ecostep/models/energia_data.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// IP fija del ESP32 cuando actúa como punto de acceso (valor por defecto
/// de `WiFi.softAP()` en el ESP32).
const String kHostEsp32 = '192.168.4.1';

/// Puerto (debe coincidir con `PUERTO_LOCAL` en el config.h del firmware).
const int kPuertoEsp32 = 3333;

/// true si [texto] es una IPv4 válida (p. ej. "172.20.10.5").
bool esIpValida(String texto) {
  final partes = texto.trim().split('.');
  if (partes.length != 4) return false;
  return partes.every((p) {
    final n = int.tryParse(p);
    return n != null && n >= 0 && n <= 255 && p.isNotEmpty && p.length <= 3;
  });
}

/// Canal nativo de Android (ver MainActivity.kt) para forzar que la app use
/// la red Wi-Fi del ESP32 aunque no tenga internet.
const MethodChannel _canalRed = MethodChannel('smart_ecostep/red');

bool get _esAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Estado de la conexión directa con el ESP32.
enum EstadoLocal {
  /// Modo local apagado
  desconectado,

  /// Intentando conectar (o reconectando tras un corte)
  conectando,

  /// Recibiendo datos del ESP32
  conectado,
}

/// Resultado de interpretar un mensaje enviado por el ESP32.
class MensajeEsp32 {
  const MensajeEsp32(this.energia, this.pisada);

  /// Estado de energía actualizado
  final EnergiaData energia;

  /// La pisada, si el mensaje era de tipo "pisada"
  final Pisada? pisada;

  /// Interpreta un mensaje JSON del ESP32. Devuelve null si no es válido
  /// (así un mensaje corrupto nunca rompe la app).
  ///
  /// Los campos que no vengan se toman de [anterior].
  static MensajeEsp32? parsear(String texto, EnergiaData anterior) {
    final Object? decodificado;
    try {
      decodificado = jsonDecode(texto);
    } catch (_) {
      return null;
    }
    if (decodificado is! Map) return null;
    final Map<dynamic, dynamic> json = decodificado;

    final tipo = json['tipo'];
    if (tipo != 'pisada' && tipo != 'estado' && tipo != 'hola') return null;

    double leer(String clave, double porDefecto) =>
        (json[clave] as num?)?.toDouble() ?? porDefecto;

    final energia = EnergiaData(
      voltaje: leer('voltaje', anterior.voltaje),
      energiaTotalJ: leer('energia_total_j', anterior.energiaTotalJ),
      potenciaW: leer('potencia_w', anterior.potenciaW),
      activo: json['activo'] as bool? ?? true,
      timestamp: DateTime.now(),
    );
    return MensajeEsp32(energia, tipo == 'pisada' ? Pisada.fromMap(json) : null);
  }
}

/// Cliente WebSocket del ESP32 con reconexión automática.
class Esp32LocalService {
  Esp32LocalService({this.host = kHostEsp32, this.puerto = kPuertoEsp32});

  final String host;
  final int puerto;

  /// Estado de la conexión (para mostrarlo en la UI)
  final ValueNotifier<EstadoLocal> estado =
      ValueNotifier(EstadoLocal.desconectado);

  /// Último problema de conexión, en palabras simples (null = ninguno).
  final ValueNotifier<String?> ultimoError = ValueNotifier(null);

  final _energiaCtrl = StreamController<EnergiaData>.broadcast();
  final _pisadaCtrl = StreamController<Pisada?>.broadcast();

  WebSocketChannel? _canal;
  StreamSubscription<dynamic>? _sub;
  Timer? _reintento;
  Timer? _vigilante;
  bool _encendido = false;
  DateTime _ultimoMensaje = DateTime.now();
  EnergiaData _ultimo = EnergiaData.vacia();

  /// Dirección a la que se conecta
  Uri get uri => Uri.parse('ws://$host:$puerto');

  /// Emite el estado de energía en cada mensaje del ESP32.
  Stream<EnergiaData> get energiaStream => _energiaCtrl.stream;

  /// Emite cada pisada (a diferencia de Firebase, nunca hay un "valor viejo"
  /// al conectar: todo lo que llega es nuevo).
  Stream<Pisada?> get pisadaStream => _pisadaCtrl.stream;

  /// Empieza a conectarse y se reconecta solo si se corta.
  void iniciar() {
    if (_encendido) return;
    _encendido = true;
    _conectar();
    // Si en 3 s no llega nada (el ESP32 manda un latido cada 1 s),
    // se considera la conexión perdida.
    _vigilante = Timer.periodic(const Duration(seconds: 1), (_) {
      if (estado.value == EstadoLocal.conectado &&
          DateTime.now().difference(_ultimoMensaje) >
              const Duration(seconds: 3)) {
        _alPerderConexion();
      }
    });
  }

  /// Cierra la conexión y deja de reintentar. En Android devuelve el
  /// tráfico de la app a la red normal (para que Firebase tenga internet).
  void detener() {
    _encendido = false;
    _reintento?.cancel();
    _vigilante?.cancel();
    _cerrarCanal();
    estado.value = EstadoLocal.desconectado;
    ultimoError.value = null;
    if (_esAndroid) {
      _canalRed.invokeMethod<bool>('liberarRed').catchError((_) => false);
    }
  }

  /// Libera todo (llamar al cerrar la pantalla).
  void dispose() {
    detener();
    _energiaCtrl.close();
    _pisadaCtrl.close();
    estado.dispose();
    ultimoError.dispose();
  }

  Future<void> _conectar() async {
    if (!_encendido) return;
    estado.value = EstadoLocal.conectando;

    // Android: obligar a que el tráfico vaya por el Wi-Fi del ESP32 y no
    // por los datos móviles (Android evita las redes sin internet).
    String? avisoRed;
    if (_esAndroid) {
      try {
        final ok =
            await _canalRed.invokeMethod<bool>('usarWifiLocal') ?? false;
        if (!ok) {
          avisoRed = 'El celular no está conectado a ninguna red Wi-Fi. '
              'Conéctalo a "SmartEcoStep".';
        }
      } catch (_) {
        // Canal no disponible: se intenta igual
      }
    }

    try {
      final canal = WebSocketChannel.connect(uri);
      await canal.ready.timeout(const Duration(seconds: 3));
      if (!_encendido) {
        canal.sink.close();
        return;
      }
      _canal = canal;
      _ultimoMensaje = DateTime.now();
      estado.value = EstadoLocal.conectado;
      ultimoError.value = null;
      _sub = canal.stream.listen(
        (m) => _procesarMensaje(m.toString()),
        onDone: _alPerderConexion,
        onError: (_) => _alPerderConexion(),
        cancelOnError: true,
      );
    } catch (e) {
      ultimoError.value = avisoRed ?? describirError(e, host, puerto);
      _alPerderConexion();
    }
  }

  /// Traduce el error técnico a una pista útil.
  static String describirError(Object e, String host, int puerto) {
    // Modo "misma red": el ESP32 está en tu Wi-Fi con una IP del router
    if (host != kHostEsp32) {
      return 'No se pudo conectar a ws://$host:$puerto. Revisa que este '
          'dispositivo y el ESP32 estén en la MISMA red Wi-Fi, que la IP sea '
          'la que muestra la LCD y que el firmware esté en MODO_LOCAL 2. '
          '(Algunas redes escolares bloquean la conexión entre dispositivos.)';
    }
    final t = e.toString().toLowerCase();
    if (t.contains('timeout') || t.contains('timed out')) {
      return 'Sin respuesta de $host:$puerto. Conecta este dispositivo a la '
          'red Wi-Fi "SmartEcoStep" (en el celular, apaga los datos móviles).';
    }
    if (t.contains('refused')) {
      return 'El ESP32 rechazó la conexión en el puerto $puerto. Revisa que '
          'el firmware esté en MODO_LOCAL 1.';
    }
    if (t.contains('unreachable') || t.contains('no route')) {
      return 'No hay ruta hacia $host. Conecta este dispositivo a '
          '"SmartEcoStep".';
    }
    return 'No se pudo conectar a ws://$host:$puerto. Conecta este '
        'dispositivo a la red "SmartEcoStep" y revisa que el ESP32 esté '
        'encendido en MODO_LOCAL 1.';
  }

  void _procesarMensaje(String texto) {
    _ultimoMensaje = DateTime.now();
    final m = MensajeEsp32.parsear(texto, _ultimo);
    if (m == null) return;
    _ultimo = m.energia;
    _energiaCtrl.add(m.energia);
    if (m.pisada != null) _pisadaCtrl.add(m.pisada);
  }

  void _alPerderConexion() {
    _cerrarCanal();
    if (!_encendido) return;
    estado.value = EstadoLocal.conectando;
    // Avisar a la UI que el ESP32 ya no está activo (conserva la energía)
    _ultimo = EnergiaData(
      voltaje: 0,
      energiaTotalJ: _ultimo.energiaTotalJ,
      potenciaW: 0,
      activo: false,
      timestamp: DateTime.now(),
    );
    _energiaCtrl.add(_ultimo);
    _reintento?.cancel();
    _reintento = Timer(const Duration(seconds: 2), _conectar);
  }

  void _cerrarCanal() {
    _sub?.cancel();
    _sub = null;
    _canal?.sink.close();
    _canal = null;
  }
}
