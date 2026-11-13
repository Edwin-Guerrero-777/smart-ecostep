/// Reglas de gamificación: cómo el voltaje se convierte en XP, cuánto XP
/// pide cada nivel y qué dificultad se desbloquea en cada uno.
///
/// Todo lo "ajustable" del balance del juego está en este archivo.
/// Ejemplo de uso:
/// ```dart
/// final xp     = Progresion.xpDePisada(14.8);  // 15 XP
/// final estado = Progresion.estado(1200);      // nivel 3, 797 de 812 XP
/// final dif    = estado.dificultad;            // Dificultad.dificil
/// ```
library;

import 'dart:math';

import 'package:smart_ecostep/models/energia_data.dart';

/// Niveles de dificultad que se desbloquean al subir de nivel.
///
/// Cada uno acelera la caída de las flechas y las hace aparecer más seguido.
/// A partir de [extremo] (nivel 5) el juego pasa a ser un reto casi extremo:
/// la flecha cruza el tablero en menos de un segundo.
///
/// | Dificultad | Nivel | Caída  | Velocidad |
/// |------------|:-----:|:------:|:---------:|
/// | Normal     |   1   | 2.2 s  |   1.0×    |
/// | Difícil    |   3   | 1.5 s  |   1.5×    |
/// | Extremo    |   5   | 0.9 s  |   2.4×    |
/// | Leyenda    |   7   | 0.7 s  |   3.1×    |
/// | Imposible  |  10   | 0.55 s |   4.0×    |
enum Dificultad {
  normal   (nivelMinimo: 1,  nombre: 'Normal',    caidaMs: 2200, intervaloMinMs: 450, intervaloRangoMs: 550),
  dificil  (nivelMinimo: 3,  nombre: 'Difícil',   caidaMs: 1500, intervaloMinMs: 360, intervaloRangoMs: 420),
  extremo  (nivelMinimo: 5,  nombre: 'Extremo',   caidaMs:  900, intervaloMinMs: 260, intervaloRangoMs: 280),
  leyenda  (nivelMinimo: 7,  nombre: 'Leyenda',   caidaMs:  700, intervaloMinMs: 210, intervaloRangoMs: 220),
  imposible(nivelMinimo: 10, nombre: 'Imposible', caidaMs:  550, intervaloMinMs: 170, intervaloRangoMs: 170);

  const Dificultad({
    required this.nivelMinimo,
    required this.nombre,
    required this.caidaMs,
    required this.intervaloMinMs,
    required this.intervaloRangoMs,
  });

  /// Nivel del jugador a partir del cual se desbloquea
  final int nivelMinimo;

  /// Nombre que se muestra en la barra de nivel y en el toast
  final String nombre;

  /// Tiempo que tarda una flecha en llegar a la Zona de Captura
  final double caidaMs;

  /// Tiempo entre flechas: intervaloMinMs + aleatorio(0..intervaloRangoMs)
  final int intervaloMinMs, intervaloRangoMs;

  /// Velocidad relativa a la dificultad Normal (1.0×, 2.4×…)
  double get multiplicadorVelocidad => Dificultad.normal.caidaMs / caidaMs;

  /// true desde Extremo en adelante (la UI lo resalta en rojo)
  bool get esExtrema => index >= Dificultad.extremo.index;

  /// La dificultad más alta desbloqueada para un nivel.
  static Dificultad paraNivel(int nivel) =>
      Dificultad.values.lastWhere((d) => nivel >= d.nivelMinimo);
}

/// Posición del jugador dentro de su nivel actual.
class EstadoNivel {
  const EstadoNivel(this.nivel, this.xpEnNivel, this.xpNecesario);

  /// Nivel actual (empieza en 1)
  final int nivel;

  /// XP acumulado desde que empezó el nivel actual
  final int xpEnNivel;

  /// XP que pide el nivel actual para subir al siguiente
  final int xpNecesario;

  /// Progreso dentro del nivel, de 0.0 a 1.0 (para la barra)
  double get fraccion => xpNecesario == 0 ? 0 : xpEnNivel / xpNecesario;

  /// Dificultad desbloqueada en este nivel
  Dificultad get dificultad => Dificultad.paraNivel(nivel);
}

/// Reglas de progresión: voltaje → XP → nivel.
class Progresion {
  Progresion._();

  /// Conversión directa: cada voltio generado vale 1 XP.
  /// Una pisada típica (5–25 V) da entre 5 y 25 XP.
  static const double xpPorVoltio = 1;

  // ── Curva de nivel ────────────────────────────────────────────────────────
  //
  //   XP(n) = base · n^exponente · rampa^max(0, n − 2)
  //
  // · base · n^1.6 → crecimiento polinómico suave (niveles 1 y 2 rápidos).
  // · rampa^(n−2) → componente exponencial que entra en el nivel 3 y
  //   convierte cada nivel siguiente en una prueba de resistencia.
  //
  //  Nivel │ XP para subir │ XP acumulado │ ≈ pisadas (15 XP c/u)
  //  ──────┼───────────────┼──────────────┼──────────────────────
  //    1   │        100    │          0   │      7
  //    2   │        303    │        100   │     20
  //    3   │        812    │        403   │     54
  //    4   │      1 801    │      1 215   │    120
  //    5   │      3 604    │      3 016   │    240
  //    6   │      6 754    │      6 620   │    450
  //    7   │     12 100    │     13 374   │    807
  //    8   │     20 975    │     25 474   │  1 398
  //   10   │     58 752    │     81 905   │  3 917

  /// XP del nivel 1
  static const double base = 100;

  /// Exponente de la parte polinómica (el "1.6" de la fórmula)
  static const double exponente = 1.6;

  /// Multiplicador exponencial por nivel a partir del nivel 3
  static const double rampa = 1.4;

  /// XP de una pisada. El voltaje se limita al máximo físico del tapete
  /// (10 sensores × 3.3 V = 33 V) para que una lectura errónea no regale XP.
  static int xpDePisada(double voltaje) =>
      (voltaje.clamp(0.0, kVoltajeMaxTapete) * xpPorVoltio).round();

  /// XP necesario para pasar del [nivel] al siguiente (ver tabla arriba).
  static int xpParaSubir(int nivel) =>
      (base * pow(nivel, exponente) * pow(rampa, max(0, nivel - 2))).round();

  /// Calcula nivel y progreso a partir del XP total acumulado.
  ///
  /// Va "gastando" el XP nivel por nivel hasta que no alcanza para subir;
  /// lo que sobra es el progreso dentro del nivel actual.
  /// Ej.: 250 XP → nivel 1 cuesta 100 → sobran 150 → nivel 2 con 150/303.
  static EstadoNivel estado(int xpTotal) {
    var nivel = 1;
    var resto = xpTotal < 0 ? 0 : xpTotal;
    while (resto >= xpParaSubir(nivel)) {
      resto -= xpParaSubir(nivel);
      nivel++;
    }
    return EstadoNivel(nivel, resto, xpParaSubir(nivel));
  }
}
