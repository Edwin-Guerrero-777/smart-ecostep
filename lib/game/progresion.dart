/// Reglas de gamificación: cómo el voltaje se convierte en XP, cuánto XP
/// pide cada nivel y qué dificultad se desbloquea en cada uno.
///
/// Todo lo "ajustable" del balance del juego está en este archivo.
/// Ejemplo de uso:
/// ```dart
/// final xp     = Progresion.xpDePisada(7.2, Carril.izquierda); // 72
/// final estado = Progresion.estado(1200);  // nivel 3, 550 de 700 XP…
/// final dif    = estado.dificultad;        // Dificultad.dificil
/// ```
library;

import 'package:smart_ecostep/models/energia_data.dart';

/// Niveles de dificultad que se desbloquean al subir de nivel.
///
/// Cada uno acelera la caída de las flechas y las hace aparecer más seguido.
enum Dificultad {
  normal (nivelMinimo: 1, nombre: 'Normal',  caidaMs: 2200, intervaloMinMs: 450, intervaloRangoMs: 550),
  dificil(nivelMinimo: 3, nombre: 'Difícil', caidaMs: 1750, intervaloMinMs: 380, intervaloRangoMs: 450),
  experto(nivelMinimo: 5, nombre: 'Experto', caidaMs: 1350, intervaloMinMs: 320, intervaloRangoMs: 360),
  maestro(nivelMinimo: 8, nombre: 'Maestro', caidaMs: 1050, intervaloMinMs: 260, intervaloRangoMs: 300);

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

  /// Velocidad relativa a la dificultad Normal (1.0×, 1.3×…)
  double get multiplicadorVelocidad => Dificultad.normal.caidaMs / caidaMs;

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

  /// Conversión directa: cada voltio generado vale 10 XP.
  static const double xpPorVoltio = 10;

  /// XP de una pisada. El voltaje se limita al máximo físico de la flecha
  /// (nº de sensores × 3.3 V) para que una lectura errónea no regale XP.
  static int xpDePisada(double voltaje, Carril carril) =>
      (voltaje.clamp(0.0, carril.voltajeMaximo) * xpPorVoltio).round();

  /// XP necesario para pasar del [nivel] al siguiente (250, 400, 550…).
  static int xpParaSubir(int nivel) => 250 + 150 * (nivel - 1);

  /// Calcula nivel y progreso a partir del XP total acumulado.
  ///
  /// Va "gastando" el XP nivel por nivel hasta que no alcanza para subir;
  /// lo que sobra es el progreso dentro del nivel actual.
  /// Ej.: 350 XP → nivel 1 cuesta 250 → sobran 100 → nivel 2 con 100/400.
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
