/// Pantalla principal: tablero de energía estilo juego de ritmo.
///
/// Estructura visual (de arriba a abajo):
/// ```
/// ┌──────────────────────────────────────────┐
/// │ AppBar  ⚡ Smart Eco-Step   [estado] [⏻] │
/// ├──────────────────────────────────────────┤
/// │ _BarraXp        NV 3 ▓▓▓▓▓░░░  [🏆 Podio] │
/// │ _MetricasEnergia  Voltaje│Energía│Combo  │
/// │ _TableroDdr   ←  ↓  ↑  →  (flechas caen)  │
/// │               [ ZONA DE CAPTURA ]         │
/// │ _BotonSimular  SIMULAR INTERACCIÓN DDR    │
/// └──────────────────────────────────────────┘
///   + capas encima: CelebracionNivel y ToastDificultad
/// ```
///
/// Flujo de datos:
/// ```
/// ESP32 / simulador ──► Firebase ──► streams ──► _HomeScreenState
///                                                 ├─► DdrController (animación)
///                                                 └─► XP / nivel / dificultad
/// ```
/// La pantalla **siempre reacciona a lo que llega desde Firebase**, nunca al
/// evento local. Así el simulador prueba exactamente el mismo camino que
/// seguirá el ESP32 real.
library;

import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:smart_ecostep/game/ddr_controller.dart';
import 'package:smart_ecostep/game/progresion.dart';
import 'package:smart_ecostep/main.dart';
import 'package:smart_ecostep/models/energia_data.dart';
import 'package:smart_ecostep/screens/login_screen.dart';
import 'package:smart_ecostep/screens/podio_sheet.dart';
import 'package:smart_ecostep/services/database_service.dart';
import 'package:smart_ecostep/widgets/efectos_neon.dart';

/// Apariencia de cada carril (dentro de la paleta Ocean Blue Serenity).
///
/// Vive aquí y no en el modelo [Carril] para que el modelo no dependa de
/// Flutter/Material.
extension CarrilEstilo on Carril {
  /// Flecha que se dibuja en el carril
  IconData get icono => switch (this) {
    Carril.izquierda => Icons.arrow_back_rounded,
    Carril.abajo => Icons.arrow_downward_rounded,
    Carril.arriba => Icons.arrow_upward_rounded,
    Carril.derecha => Icons.arrow_forward_rounded,
  };

  /// Color neón del carril (flechas, destello y texto flotante)
  Color get color => switch (this) {
    Carril.izquierda => AppColors.cyan,
    Carril.abajo => AppColors.iceBlue,
    Carril.arriba => const Color(0xFF64FFDA), // aqua neón
    Carril.derecha => const Color(0xFF7C9CFF), // azul océano profundo
  };
}

/// Pantalla principal tras iniciar sesión. Ver la descripción del archivo.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Estado de la pantalla principal. Coordina tres cosas:
///
/// 1. **Escucha Firebase** (3 streams): energía acumulada, pisadas y XP.
/// 2. **Anima el tablero**: un [Ticker] avanza el [DdrController] ~60 veces
///    por segundo.
/// 3. **Simula el ESP32** cuando se activa el botón de simulación.
///
/// Usa [TickerProviderStateMixin] (y no la versión "Single") porque tiene
/// varios relojes: el Ticker del tablero, la celebración y el toast.
class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  /// Motor del tablero (flechas, destellos, combo). No es un widget.
  final DdrController _ddr = DdrController();

  /// Reloj de animación del tablero; llama a `_ddr.tick()` en cada frame.
  late final Ticker _ticker;

  StreamSubscription<EnergiaData>? _energiaSub;
  StreamSubscription<Pisada?>? _pisadaSub;
  StreamSubscription<int>? _xpSub;

  // ── Progresión ────────────────────────────────────────────────────────────

  /// XP total del jugador, tal como está guardado en Firebase.
  int _xpTotal = 0;

  /// false hasta recibir la primera lectura de XP (esa no se celebra).
  bool _xpCargado = false;

  /// Animación 0→1 de la capa "¡SUBISTE DE NIVEL!".
  late final AnimationController _celebracion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  /// Animación 0→1 del toast "¡Nueva dificultad desbloqueada!".
  late final AnimationController _toast = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  /// Nivel que muestra la celebración en curso.
  int _nivelCelebrado = 1;

  /// Dificultad que anuncia el toast en curso.
  Dificultad _toastDificultad = Dificultad.normal;

  // ── Estado del dispositivo ────────────────────────────────────────────────

  /// Último estado de energía recibido de `datos_esp32/{uid}/actual`.
  EnergiaData _energia = EnergiaData.vacia();

  /// true en cuanto Firebase entrega la primera lectura.
  bool _dbConectada = false;

  // Firebase emite el valor guardado al suscribirse: ese no es una pisada nueva
  bool _primeraPisadaLeida = false;
  int? _ultimoIdPisada;

  // ── Simulador ─────────────────────────────────────────────────────────────

  /// true mientras el botón "Simular Interacción DDR" está activo.
  bool _simulando = false;

  /// Pisadas simuladas programadas. Se cancelan al detener la simulación
  /// o al salir de la pantalla.
  final Set<Timer> _timersSim = {};
  final _rnd = Random();

  /// true si los datos vienen de un ESP32 físico (no del simulador).
  bool get _esp32Real => _energia.activo && !_simulando;

  /// Arranca el reloj de animación y se suscribe a los 3 streams de Firebase.
  @override
  void initState() {
    super.initState();

    _ticker = createTicker((elapsed) {
      _ddr.tick(elapsed.inMicroseconds / 1000);
    })..start();

    _ddr.onFlechaGenerada = _programarPisadaSimulada;

    final db = DatabaseService.instance;
    _energiaSub = db.energiaStream.listen((e) {
      setState(() {
        _energia = e;
        _dbConectada = true;
      });
      _actualizarGeneracion();
    }, onError: (_) => setState(() => _dbConectada = false));
    _pisadaSub = db.pisadaStream.listen(_onPisada);
    _xpSub = db.xpStream.listen(_onXp);
  }

  /// Libera todo: timers, reloj, suscripciones y animaciones.
  /// Sin esto seguirían llegando eventos de Firebase a una pantalla cerrada.
  @override
  void dispose() {
    _cancelarTimers();
    _ticker.dispose();
    _energiaSub?.cancel();
    _pisadaSub?.cancel();
    _xpSub?.cancel();
    _celebracion.dispose();
    _toast.dispose();
    _ddr.dispose();
    super.dispose();
  }

  // ── XP / Nivel / Dificultad ───────────────────────────────────────────────

  /// Firebase es la fuente de verdad del XP. Al cambiar, se recalcula el
  /// nivel; si subió, se celebra y, si toca, se desbloquea dificultad.
  void _onXp(int xp) {
    final antes = Progresion.estado(_xpTotal);
    final despues = Progresion.estado(xp);
    setState(() => _xpTotal = xp);
    _ddr.dificultad = despues.dificultad;

    // La primera lectura solo carga el progreso guardado (sin celebrar)
    if (!_xpCargado) {
      _xpCargado = true;
      return;
    }
    if (despues.nivel <= antes.nivel) return;

    HapticFeedback.heavyImpact();
    setState(() => _nivelCelebrado = despues.nivel);
    _celebracion.forward(from: 0);

    if (despues.dificultad != antes.dificultad) {
      setState(() => _toastDificultad = despues.dificultad);
      // Aparece cuando la celebración empieza a desvanecerse
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _toast.forward(from: 0);
      });
    }
  }

  /// Abre el Podio con el nombre y XP reales del usuario. Si no tiene
  /// nombre registrado, se muestra como "Jugador".
  void _abrirPodio() {
    final user = FirebaseAuth.instance.currentUser;
    mostrarPodio(
      context,
      nombreUsuario: user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!.trim()
          : 'Jugador',
      xpUsuario: _xpTotal,
    );
  }

  /// Las flechas caen mientras el ESP32 esté activo o se esté simulando.
  void _actualizarGeneracion() =>
      _ddr.setGenerando(_simulando || _energia.activo);

  // ── Listener de pisadas (ESP32 real o simulado) ───────────────────────────

  /// Se ejecuta cada vez que cambia `datos_esp32/{uid}/pisada`.
  ///
  /// - Ignora el primer evento: es la pisada vieja que ya estaba guardada.
  /// - Ignora pisadas con el mismo `id` que la anterior (duplicados).
  /// - Convierte voltaje en XP, lo suma en Firebase y dispara los efectos
  ///   visuales del carril (destello, texto flotante y combo).
  void _onPisada(Pisada? p) {
    if (!_primeraPisadaLeida) {
      _primeraPisadaLeida = true;
      _ultimoIdPisada = p?.id;
      return;
    }
    if (p == null || p.id == _ultimoIdPisada) return;
    _ultimoIdPisada = p.id;

    // Voltaje → XP (conversión directa). Se suma en Firebase y la barra
    // reacciona cuando el nuevo total vuelve por xpStream.
    final xp = Progresion.xpDePisada(p.voltaje);
    if (xp > 0) DatabaseService.instance.sumarXp(xp).catchError((_) {});

    final cal = _ddr.registrarPisada(p.carril, p.voltaje, xp: xp);
    if (cal == Calificacion.perfecto) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  // ── Simulación DDR ────────────────────────────────────────────────────────

  /// Enciende o apaga el simulador. Al apagarlo cancela las pisadas
  /// pendientes y marca el dispositivo como inactivo en Firebase (la
  /// energía acumulada se conserva).
  void _toggleSimulacion() {
    setState(() => _simulando = !_simulando);
    if (_simulando) {
      _snack('🎮 Simulación DDR activada');
    } else {
      _cancelarTimers();
      DatabaseService.instance.marcarInactivo().catchError((_) {});
      _snack('⏹ Simulación detenida');
    }
    _actualizarGeneracion();
  }

  /// Por cada flecha que aparece, el "jugador virtual" pisa ese carril
  /// justo cuando la flecha llega a la Zona de Captura (con algo de error
  /// humano y fallos ocasionales), escribiendo en Firebase como el ESP32.
  void _programarPisadaSimulada(FlechaCayendo f) {
    // El jugador virtual también sufre con la velocidad: falla más
    // a medida que sube la dificultad.
    final precision = switch (_ddr.dificultad) {
      Dificultad.normal    => 0.92,
      Dificultad.dificil   => 0.87,
      Dificultad.extremo   => 0.78,
      Dificultad.leyenda   => 0.70,
      Dificultad.imposible => 0.60,
    };
    if (!_simulando || _rnd.nextDouble() > precision) return;

    // Se adelanta ~150 ms para compensar la ida y vuelta a Firebase
    final ms = f.caidaMs - 150 + (_rnd.nextInt(180) - 90);
    late final Timer t;
    t = Timer(Duration(milliseconds: ms.round()), () {
      _timersSim.remove(t);
      if (mounted && _simulando) _enviarPisadaSimulada(f.carril);
    });
    _timersSim.add(t);
  }

  /// Genera una pisada con valores físicamente realistas y la escribe en
  /// Firebase exactamente como lo haría el ESP32. Si la escritura falla
  /// (sin internet, reglas de seguridad…), detiene la simulación y avisa.
  Future<void> _enviarPisadaSimulada(Carril carril) async {
    // Una pisada excita los 10 piezos a la vez: los de la flecha pisada
    // reciben el impacto directo (peso 1.0) y el resto vibra (peso 0.7).
    // La suma objetivo va de 5 V (pisada suave) a 25 V (pisada fuerte).
    // Cada sensor se limita a 3.3 V. El ESP32 envía la SUMA de los 10.
    // Energía ≈ Σ ½·C·Vᵢ² con C ≈ 10 µF por sensor.
    final objetivo = 5.0 + _rnd.nextDouble() * 20.0;
    const pesoVibracion = 0.7;
    final pesoTotal = carril.sensores +
        (kSensoresTapete - carril.sensores) * pesoVibracion;

    var voltaje = 0.0, energia = 0.0;
    for (var i = 0; i < kSensoresTapete; i++) {
      final peso = i < carril.sensores ? 1.0 : pesoVibracion;
      final ruido = 0.9 + _rnd.nextDouble() * 0.2; // ±10 % por sensor
      final v = (objetivo * peso / pesoTotal * ruido)
          .clamp(0.0, kVoltajeMaxSensor);
      voltaje += v;
      energia += 0.5 * 10e-6 * v * v;
    }
    try {
      await DatabaseService.instance.registrarPisada(
        Pisada(
          id: DateTime.now().microsecondsSinceEpoch,
          carril: carril,
          voltaje: voltaje,
          energiaJ: energia,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _cancelarTimers();
      setState(() => _simulando = false);
      _actualizarGeneracion();
      _snack('Error al escribir en Firebase: $e');
    }
  }

  /// Cancela todas las pisadas simuladas que aún no se enviaron.
  void _cancelarTimers() {
    for (final t in _timersSim) {
      t.cancel();
    }
    _timersSim.clear();
  }

  /// Muestra un mensaje corto flotante (reemplaza al anterior si lo hay).
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.cardElevated,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// Cierra sesión y vuelve al login. Si estaba simulando, primero deja el
  /// dispositivo como inactivo para que no quede "en línea" en Firebase.
  Future<void> _signOut() async {
    if (_simulando) {
      _cancelarTimers();
      await DatabaseService.instance.marcarInactivo().catchError((_) {});
    }
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  /// Construye la pantalla. Solo se reconstruye entera cuando cambia la
  /// energía, el XP o el modo simulación; el tablero y el combo se redibujan
  /// por su cuenta escuchando al [DdrController] (más eficiente a 60 fps).
  @override
  Widget build(BuildContext context) {
    // Texto y color de la pastilla de estado de la AppBar
    final (estado, colorEstado) = _simulando
        ? ('SIMULADO', AppColors.warning)
        : _esp32Real
        ? ('ESP32 EN LÍNEA', AppColors.success)
        : _dbConectada
        ? ('EN ESPERA', AppColors.textSecondary)
        : ('CONECTANDO…', AppColors.warning);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: AppColors.cyan, size: 22),
            SizedBox(width: 6),
            Text('Smart Eco-Step'),
          ],
        ),
        actions: [
          _EstadoPill(texto: estado, color: colorEstado),
          IconButton(
            icon: const Icon(Icons.power_settings_new_rounded),
            tooltip: 'Cerrar sesión',
            onPressed: _signOut,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.cardBorder),
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.6, -0.5),
                radius: 0.85,
                colors: [Color(0xFF0A1A30), AppColors.background],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                children: [
                  // ── Barra de nivel / XP + acceso al Podio ────────────────
                  _BarraXp(xpTotal: _xpTotal, onPodio: _abrirPodio),
                  const SizedBox(height: 10),

                  // ── Dashboard superior: SOLO métricas de energía ─────────
                  _MetricasEnergia(energia: _energia, ddr: _ddr),
                  const SizedBox(height: 14),

                  // ── Tablero DDR ──────────────────────────────────────────
                  Expanded(child: _TableroDdr(ddr: _ddr)),
                  const SizedBox(height: 14),

                  // ── Botón de simulación ──────────────────────────────────
                  _BotonSimular(
                    simulando: _simulando,
                    onPressed: _toggleSimulacion,
                  ),
                ],
              ),
            ),
          ),

          // ── Capas de celebración (encima de todo) ───────────────────────
          Positioned.fill(
            child: CelebracionNivel(
              animacion: _celebracion,
              nivel: _nivelCelebrado,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 8,
            child: SafeArea(
              child: ToastDificultad(
                animacion: _toast,
                dificultad: _toastDificultad,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BARRA DE NIVEL (XP)
// ─────────────────────────────────────────────────────────────────────────────

/// Barra de nivel superior: insignia con el nivel, dificultad actual,
/// progreso "XP / meta" con barra neón y el botón 🏆 que abre el Podio.
///
/// Recibe solo el XP total; el nivel y el progreso se calculan con
/// [Progresion.estado].
class _BarraXp extends StatelessWidget {
  const _BarraXp({required this.xpTotal, required this.onPodio});
  final int xpTotal;
  final VoidCallback onPodio;

  static const _aqua = Color(0xFF64FFDA);

  @override
  Widget build(BuildContext context) {
    final e = Progresion.estado(xpTotal);
    // Desde Extremo la etiqueta de dificultad se vuelve roja con fuego
    final extrema    = e.dificultad.esExtrema;
    final colorDif   = extrema ? AppColors.error : _aqua;
    final iconoDif   = extrema
        ? Icons.local_fire_department_rounded
        : Icons.speed_rounded;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cyan.withAlpha(70)),
        boxShadow: [
          BoxShadow(color: AppColors.cyan.withAlpha(25), blurRadius: 16),
        ],
      ),
      child: Row(
        children: [
          // ── Insignia de nivel ───────────────────────────────────────────
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.cyan, _aqua],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: AppColors.cyan.withAlpha(110), blurRadius: 12),
              ],
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'NV',
                  style: TextStyle(
                    color: AppColors.background,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                Text(
                  '${e.nivel}',
                  style: const TextStyle(
                    color: AppColors.background,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // ── Barra ───────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(iconoDif, color: colorDif, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      '${e.dificultad.nombre.toUpperCase()} '
                      '${e.dificultad.multiplicadorVelocidad.toStringAsFixed(1)}×',
                      style: TextStyle(
                        color: colorDif,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${e.xpEnNivel} / ${e.xpNecesario} XP',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                // Al cambiar de nivel la key reinicia la animación desde 0
                TweenAnimationBuilder<double>(
                  key: ValueKey(e.nivel),
                  tween: Tween(begin: 0, end: e.fraccion),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, f, _) => _BarraNeon(fraccion: f),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),

          // ── Botón Podio ─────────────────────────────────────────────────
          IconButton(
            tooltip: 'Podio',
            onPressed: onPodio,
            icon: const Icon(
              Icons.emoji_events_rounded,
              color: Color(0xFFFFD54F),
              shadows: [Shadow(color: Color(0xFFFFD54F), blurRadius: 10)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra de progreso con degradado cyan→aqua y resplandor.
/// [fraccion] va de 0 (vacía) a 1 (llena).
class _BarraNeon extends StatelessWidget {
  const _BarraNeon({required this.fraccion});
  final double fraccion;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: AppColors.cardElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraccion.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: const LinearGradient(
                colors: [AppColors.cyanSoft, AppColors.cyan, Color(0xFF64FFDA)],
              ),
              boxShadow: [
                BoxShadow(color: AppColors.cyan.withAlpha(160), blurRadius: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD DE ENERGÍA
// ─────────────────────────────────────────────────────────────────────────────

/// Las 3 métricas del dashboard: Voltaje actual, Energía total y Combo.
///
/// Voltaje y energía vienen de Firebase; el combo vive en el
/// [DdrController] (se calcula en la app), por eso esa tarjeta escucha
/// al controlador por separado.
class _MetricasEnergia extends StatelessWidget {
  const _MetricasEnergia({required this.energia, required this.ddr});
  final EnergiaData energia;
  final DdrController ddr;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricaTile(
            icono: Icons.electric_bolt_rounded,
            etiqueta: 'Voltaje actual',
            color: AppColors.cyan,
            valor: energia.voltaje,
            formato: EnergiaData.formatearVoltaje,
            subtitulo: 'suma de sensores',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricaTile(
            icono: Icons.battery_charging_full_rounded,
            etiqueta: 'Energía total',
            color: const Color(0xFF64FFDA),
            valor: energia.energiaTotalJ,
            formato: EnergiaData.formatearEnergia,
            subtitulo: EnergiaData.formatearPotencia(energia.potenciaW),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ListenableBuilder(
            listenable: ddr,
            builder: (context, _) => Transform.scale(
              scale: 1 + 0.08 * ddr.comboBump,
              child: _MetricaTile(
                icono: Icons.local_fire_department_rounded,
                etiqueta: 'Combo',
                color: const Color(0xFF7C9CFF),
                valor: ddr.combo.toDouble(),
                formato: (v) => 'x${v.round()}',
                subtitulo: 'máx x${ddr.comboMax}',
                animar: false,
                brillo: ddr.comboBump,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tarjeta de una métrica: ícono + etiqueta, valor grande y subtítulo.
///
/// - [formato] convierte el número en texto ("12.4 V", "x7"…).
/// - Con [animar] el número "cuenta" desde el valor anterior al nuevo.
/// - [brillo] (0..1) ilumina el borde; lo usa el combo al recibir pisadas.
class _MetricaTile extends StatelessWidget {
  const _MetricaTile({
    required this.icono,
    required this.etiqueta,
    required this.color,
    required this.valor,
    required this.formato,
    required this.subtitulo,
    this.animar = true,
    this.brillo = 0,
  });
  final IconData icono;
  final String etiqueta, subtitulo;
  final Color color;
  final double valor;
  final String Function(double) formato;
  final bool animar;
  final double brillo;

  @override
  Widget build(BuildContext context) {
    Widget texto(double v) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        formato(v),
        style: TextStyle(
          color: color,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: color.withAlpha(140), blurRadius: 10)],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Color.lerp(AppColors.cardBorder, color, brillo)!,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha((25 + 90 * brillo).round()),
            blurRadius: 14 + 10 * brillo,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, color: color, size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  etiqueta.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          animar
              ? TweenAnimationBuilder<double>(
                  tween: Tween(end: valor),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, child) => texto(v),
                )
              : texto(valor),
          const SizedBox(height: 2),
          Text(
            subtitulo,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastilla de estado en la AppBar ("ESP32 EN LÍNEA", "SIMULADO",
/// "EN ESPERA"…) con un punto luminoso del mismo color.
class _EstadoPill extends StatelessWidget {
  const _EstadoPill({required this.texto, required this.color});
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withAlpha(25),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [BoxShadow(color: color, blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            texto,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TABLERO DDR
// ─────────────────────────────────────────────────────────────────────────────

/// Tablero central con los 4 carriles y la Zona de Captura.
///
/// Es "tonto": no guarda estado. En cada frame lee del [DdrController]
/// dónde está cada flecha, cuánto brilla cada carril y qué textos flotan,
/// y lo dibuja. Las posiciones se calculan según el tamaño disponible, así
/// que se adapta a cualquier pantalla.
class _TableroDdr extends StatelessWidget {
  const _TableroDdr({required this.ddr});
  final DdrController ddr;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: AppColors.surface.withAlpha(200),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(color: AppColors.cyan.withAlpha(18), blurRadius: 24),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: LayoutBuilder(
          builder: (context, box) => ListenableBuilder(
            listenable: ddr,
            builder: (context, _) => _dibujar(box.maxWidth, box.maxHeight),
          ),
        ),
      ),
    );
  }

  /// Construye todas las capas del tablero para un tamaño [w]×[h].
  ///
  /// Orden de capas (de atrás hacia adelante): carriles con haz de luz →
  /// Zona de Captura → receptores → flechas cayendo → combo gigante →
  /// textos flotantes → mensaje de reposo.
  Widget _dibujar(double w, double h) {
    final anchoCarril = w / Carril.values.length;
    final tam = min(anchoCarril * 0.72, 64.0);
    final capturaY = h - 22 - tam / 2; // centro de la Zona de Captura
    final inicioY = -tam / 2; // nace justo fuera del tablero
    double centroX(Carril c) => anchoCarril * (c.index + 0.5);

    final hijos = <Widget>[];

    // ── Carriles + haz de luz al pisar ──────────────────────────────────────
    for (final c in Carril.values) {
      final d = ddr.destello(c);
      hijos.add(
        Positioned(
          left: anchoCarril * c.index,
          top: 0,
          bottom: 0,
          width: anchoCarril,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: c.index == 0
                  ? null
                  : Border(
                      left: BorderSide(
                        color: AppColors.cardBorder.withAlpha(120),
                      ),
                    ),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  c.color.withAlpha((18 + 110 * d).round()),
                  c.color.withAlpha((40 * d).round()),
                  Colors.transparent,
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
        ),
      );
    }

    // ── Zona de Captura ─────────────────────────────────────────────────────
    hijos.add(
      Positioned(
        left: 6,
        right: 6,
        top: capturaY - tam / 2 - 8,
        height: tam + 16,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: AppColors.cyan.withAlpha(10),
            border: Border.all(color: AppColors.cyan.withAlpha(70)),
          ),
        ),
      ),
    );
    hijos.add(
      Positioned(
        left: 0,
        right: 0,
        top: capturaY - tam / 2 - 24,
        child: const Text(
          'ZONA DE CAPTURA',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.cyan,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.5,
          ),
        ),
      ),
    );

    // ── Receptores (flechas fijas que destellan) ────────────────────────────
    for (final c in Carril.values) {
      final d = ddr.destello(c);
      hijos.add(
        Positioned(
          left: centroX(c) - tam / 2,
          top: capturaY - tam / 2,
          child: Transform.scale(
            scale: 1 + 0.14 * d,
            child: _Flecha(carril: c, tam: tam, receptor: true, brillo: d),
          ),
        ),
      );
    }

    // ── Flechas cayendo ─────────────────────────────────────────────────────
    for (final f in ddr.flechas) {
      final p = ddr.progreso(f);
      final y = inicioY + (capturaY - inicioY) * p;
      // Se desvanece al pasar de largo la zona de captura (flecha fallada)
      final opacidad = p <= 1.05 ? 1.0 : (1 - (p - 1.05) / 0.3).clamp(0.0, 1.0);
      hijos.add(
        Positioned(
          left: centroX(f.carril) - tam / 2,
          top: y - tam / 2,
          child: Opacity(
            opacity: opacidad,
            child: _Flecha(carril: f.carril, tam: tam),
          ),
        ),
      );
    }

    // ── Combo gigante en el centro ──────────────────────────────────────────
    if (ddr.combo >= 2) {
      hijos.add(
        Positioned(
          left: 0,
          right: 0,
          top: h * 0.26,
          child: IgnorePointer(
            child: Transform.scale(
              scale: 1 + 0.18 * ddr.comboBump,
              child: Column(
                children: [
                  Text(
                    '${ddr.combo}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withAlpha(215),
                      fontSize: 54,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      shadows: const [
                        Shadow(color: AppColors.cyan, blurRadius: 22),
                      ],
                    ),
                  ),
                  Text(
                    'COMBO',
                    style: TextStyle(
                      color: AppColors.cyan.withAlpha(200),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ── Indicadores flotantes "+ Voltaje!" / "+ Energía" ────────────────────
    for (final t in ddr.textos) {
      final v = ddr.vidaTexto(t);
      final sube = Curves.easeOut.transform(v) * 90;
      final color = t.bonus ? t.carril.color : AppColors.textPrimary;
      hijos.add(
        Positioned(
          left: anchoCarril * t.carril.index - 10,
          width: anchoCarril + 20,
          top: capturaY - tam / 2 - 46 - sube,
          child: Opacity(
            opacity: (1 - v * v).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: v < 0.15 ? 0.7 + 2 * v : 1.0, // "pop" inicial
              child: Column(
                children: [
                  FittedBox(
                    child: Text(
                      t.titulo,
                      style: TextStyle(
                        color: color,
                        fontSize: t.bonus ? 16 : 14,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(color: color, blurRadius: 12)],
                      ),
                    ),
                  ),
                  FittedBox(
                    child: Text(
                      t.detalle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ── Mensaje en reposo ───────────────────────────────────────────────────
    if (!ddr.generando && ddr.flechas.isEmpty && ddr.textos.isEmpty) {
      hijos.add(
        Positioned(
          left: 24,
          right: 24,
          top: h * 0.3,
          child: const Column(
            children: [
              Icon(
                Icons.sensors_rounded,
                color: AppColors.textSecondary,
                size: 30,
              ),
              SizedBox(height: 8),
              Text(
                'Esperando al tapete…\nPisa una flecha o pulsa "Simular Interacción DDR"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(clipBehavior: Clip.hardEdge, children: hijos);
  }
}

/// Flecha estilo DDR. `receptor` = la flecha fija de la Zona de Captura.
class _Flecha extends StatelessWidget {
  const _Flecha({
    required this.carril,
    required this.tam,
    this.receptor = false,
    this.brillo = 0,
  });
  final Carril carril;
  final double tam;
  final bool receptor;
  final double brillo; // 0..1, solo receptores

  @override
  Widget build(BuildContext context) {
    final c = carril.color;

    final fondo = receptor
        ? Color.lerp(AppColors.background, c.withAlpha(230), brillo)!
        : c.withAlpha(45);
    final borde = receptor
        ? Color.lerp(c.withAlpha(90), Colors.white, brillo * 0.7)!
        : c;
    final icono = receptor
        ? Color.lerp(c.withAlpha(110), Colors.white, brillo)!
        : c;
    final glow = receptor
        ? BoxShadow(
            color: c.withAlpha((220 * brillo).round()),
            blurRadius: 6 + 34 * brillo,
            spreadRadius: 8 * brillo,
          )
        : BoxShadow(color: c.withAlpha(120), blurRadius: 14, spreadRadius: 1);

    return Container(
      width: tam,
      height: tam,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(tam * 0.28),
        border: Border.all(color: borde, width: receptor ? 2 : 2.5),
        boxShadow: [glow],
      ),
      child: Icon(
        carril.icono,
        size: tam * 0.62,
        color: icono,
        shadows: [
          Shadow(color: c, blurRadius: receptor ? 4 + 14 * brillo : 10),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTÓN DE SIMULACIÓN
// ─────────────────────────────────────────────────────────────────────────────

/// Botón inferior que enciende/apaga el simulador. Cambia a ámbar y a
/// "DETENER SIMULACIÓN" mientras está activo.
class _BotonSimular extends StatelessWidget {
  const _BotonSimular({required this.simulando, required this.onPressed});
  final bool simulando;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = simulando ? AppColors.warning : AppColors.cyan;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(
          simulando ? Icons.stop_circle_rounded : Icons.sports_esports_rounded,
          color: color,
        ),
        label: Text(
          simulando ? 'DETENER SIMULACIÓN' : 'SIMULAR INTERACCIÓN DDR',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: color.withAlpha(20),
          side: BorderSide(color: color.withAlpha(150), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
