/// Motor del tablero estilo juego de ritmo (sin widgets).
///
/// Separar la lógica de la UI permite probarla con tests unitarios
/// (ver `test/widget_test.dart`) sin necesidad de dibujar nada.
///
/// Línea de tiempo de una flecha:
/// ```
///  inicioMs                         llegadaMs (= inicioMs + caidaMs)
///     │  cae por el carril ...            │  pasa de largo y se desvanece
///  progreso 0.0 ──────────────────────► 1.0 ─────────────► 1.35 (se borra)
///                               ±400 ms │ ventana "¡BIEN!"
///                               ±150 ms │ ventana "¡PERFECTO!"
/// ```
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:smart_ecostep/game/progresion.dart';
import 'package:smart_ecostep/models/energia_data.dart';

/// Flecha que cae por un carril hacia la Zona de Captura.
class FlechaCayendo {
  FlechaCayendo({
    required this.id,
    required this.carril,
    required this.inicioMs,
    required this.caidaMs,
  });
  /// Identificador único (solo para depurar)
  final int id;

  /// Carril por el que cae
  final Carril carril;

  /// Momento en que apareció (reloj del Ticker, en ms)
  final double inicioMs;

  /// Velocidad con la que nació (no cambia si sube la dificultad a mitad de caída)
  final double caidaMs;

  /// Momento exacto en que llega al centro de la Zona de Captura
  double get llegadaMs => inicioMs + caidaMs;
}

/// Indicador flotante ("+ Voltaje!", "+ Energía") que sube y se desvanece.
class TextoFlotante {
  TextoFlotante({
    required this.carril,
    required this.titulo,
    required this.detalle,
    required this.inicioMs,
    required this.bonus,
  });
  /// Carril sobre el que aparece
  final Carril carril;

  /// Texto grande ("+ Voltaje!" / "+ Energía") y texto pequeño ("+72 XP")
  final String titulo, detalle;

  /// Momento en que apareció (ms)
  final double inicioMs;

  /// true si la pisada coincidió con una flecha (texto más llamativo)
  final bool bonus;
}

/// Qué tan a tiempo fue una pisada respecto a las flechas.
enum Calificacion {
  /// Dentro de ±150 ms de la llegada de una flecha
  perfecto,

  /// Dentro de ±400 ms de la llegada de una flecha
  bien,

  /// No había ninguna flecha cerca (la energía cuenta igual)
  libre,
}

/// Motor del tablero DDR: posición de flechas, destellos, textos y combo.
///
/// No depende de widgets: el HomeScreen le pasa el tiempo con un Ticker
/// (≈60 fps) y el tablero se redibuja escuchando este ChangeNotifier.
class DdrController extends ChangeNotifier {
  // ── Ajustes de jugabilidad ────────────────────────────────────────────────
  static const double ventanaPerfectoMs = 150;
  static const double ventanaBienMs     = 400;
  static const double comboTimeoutMs    = 2500; // sin pisar → combo a 0
  static const double destelloMs        = 420;
  static const double textoMs           = 950;
  static const double bumpMs            = 220;

  final _rnd = Random();

  double _now = 0;

  /// Tiempo actual del reloj de animación (ms desde que abrió la pantalla)
  double get now => _now;

  /// Flechas visibles en el tablero
  final List<FlechaCayendo> flechas = [];

  /// Indicadores flotantes visibles
  final List<TextoFlotante> textos = [];

  /// Hasta qué momento brilla cada carril
  final Map<Carril, double> _destelloHasta = {};

  /// Pisadas seguidas sin pausas largas
  int combo = 0;

  /// Mejor combo de la sesión
  int comboMax = 0;

  double _ultimaPisadaMs = -1e9;
  double _comboBumpMs    = -1e9;

  /// Dificultad actual (la fija HomeScreen según el nivel del jugador).
  Dificultad dificultad = Dificultad.normal;

  /// Tiempo de caída de las flechas nuevas
  double get caidaMs => dificultad.caidaMs;

  /// Si es true, se generan flechas nuevas.
  bool generando = false;
  double _proximaFlechaMs = 0;
  int _nextId = 0;

  /// Se llama cada vez que aparece una flecha (lo usa el simulador).
  void Function(FlechaCayendo flecha)? onFlechaGenerada;

  // ── Ciclo de animación ────────────────────────────────────────────────────

  /// Avanza el juego hasta [nowMs]. Se llama en cada frame.
  ///
  /// 1. Si toca, genera una flecha nueva en un carril aleatorio.
  /// 2. Borra flechas y textos que ya terminaron su animación.
  /// 3. Reinicia el combo si pasó demasiado tiempo sin pisar.
  /// 4. Avisa a los widgets para que se redibujen.
  void tick(double nowMs) {
    _now = nowMs;

    if (generando && _now >= _proximaFlechaMs) {
      final f = FlechaCayendo(
        id      : _nextId++,
        carril  : Carril.values[_rnd.nextInt(Carril.values.length)],
        inicioMs: _now,
        caidaMs : dificultad.caidaMs,
      );
      flechas.add(f);
      onFlechaGenerada?.call(f);
      _proximaFlechaMs = _now +
          dificultad.intervaloMinMs +
          _rnd.nextInt(dificultad.intervaloRangoMs);
    }

    flechas.removeWhere((f) => progreso(f) > 1.35);
    textos.removeWhere((t) => _now - t.inicioMs > textoMs);

    if (combo > 0 && _now - _ultimaPisadaMs > comboTimeoutMs) combo = 0;

    notifyListeners();
  }

  /// Activa o pausa la generación de flechas. Las que ya caen terminan
  /// su recorrido. Al activarse, la primera flecha sale en 250 ms.
  void setGenerando(bool valor) {
    if (valor && !generando) _proximaFlechaMs = _now + 250;
    generando = valor;
  }

  // ── Consultas para dibujar ────────────────────────────────────────────────

  /// 0 = parte superior, 1 = centro de la Zona de Captura.
  double progreso(FlechaCayendo f) => (_now - f.inicioMs) / f.caidaMs;

  /// Intensidad del destello neón del carril (1 → 0).
  double destello(Carril c) =>
      (((_destelloHasta[c] ?? 0) - _now) / destelloMs).clamp(0.0, 1.0);

  /// 0 → 1 a lo largo de la vida del texto flotante.
  double vidaTexto(TextoFlotante t) =>
      ((_now - t.inicioMs) / textoMs).clamp(0.0, 1.0);

  /// Pequeño "salto" del contador de combo justo después de cada pisada.
  double get comboBump =>
      (1 - (_now - _comboBumpMs) / bumpMs).clamp(0.0, 1.0);

  // ── Pisadas ───────────────────────────────────────────────────────────────

  /// Registra una pisada (real o simulada) en el carril indicado.
  ///
  /// Busca la flecha de ese carril más cercana a la Zona de Captura y la
  /// califica según la distancia en tiempo. Si acierta, la flecha desaparece.
  /// Siempre: hace destellar el carril, suma combo y crea un texto flotante.
  ///
  /// [voltaje] y [xp] solo se usan para el texto flotante.
  Calificacion registrarPisada(Carril carril, double voltaje, {int xp = 0}) {
    // Busca la flecha más cercana a la Zona de Captura en ese carril
    FlechaCayendo? mejor;
    double mejorDelta = double.infinity;
    for (final f in flechas) {
      if (f.carril != carril) continue;
      final delta = (_now - f.llegadaMs).abs();
      if (delta < mejorDelta) {
        mejorDelta = delta;
        mejor = f;
      }
    }

    final Calificacion cal;
    if (mejor != null && mejorDelta <= ventanaPerfectoMs) {
      cal = Calificacion.perfecto;
    } else if (mejor != null && mejorDelta <= ventanaBienMs) {
      cal = Calificacion.bien;
    } else {
      cal = Calificacion.libre;
    }
    if (cal != Calificacion.libre) flechas.remove(mejor);

    _destelloHasta[carril] = _now + destelloMs;

    combo++;
    comboMax        = max(comboMax, combo);
    _ultimaPisadaMs = _now;
    _comboBumpMs    = _now;

    final extra = xp > 0 ? '+$xp XP' : EnergiaData.formatearVoltaje(voltaje);
    textos.add(TextoFlotante(
      carril  : carril,
      inicioMs: _now,
      bonus   : cal != Calificacion.libre,
      titulo  : cal == Calificacion.libre ? '+ Voltaje!' : '+ Energía',
      detalle : switch (cal) {
        Calificacion.perfecto => '¡PERFECTO! $extra',
        Calificacion.bien     => '¡BIEN! $extra',
        Calificacion.libre    => extra,
      },
    ));

    notifyListeners();
    return cal;
  }

  /// Pone a cero el combo actual y el máximo.
  void reiniciarCombo() {
    combo    = 0;
    comboMax = 0;
    notifyListeners();
  }
}
