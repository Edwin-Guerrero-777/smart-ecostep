/// Efectos de celebración que se dibujan encima de la pantalla principal.
///
/// Ambos widgets son "controlados desde fuera": reciben un
/// `Animation<double>` que va de 0 a 1 y dibujan el fotograma
/// correspondiente. Cuando la animación está en 0 o en 1 no dibujan nada.
/// Para lanzarlos basta con `controller.forward(from: 0)`.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:smart_ecostep/game/progresion.dart';
import 'package:smart_ecostep/main.dart';

const _aqua      = Color(0xFF64FFDA);
const _periwinkle = Color(0xFF7C9CFF);

// ─────────────────────────────────────────────────────────────────────────────
// CELEBRACIÓN "¡SUBISTE DE NIVEL!"
// ─────────────────────────────────────────────────────────────────────────────

/// Capa a pantalla completa con explosión de partículas neón.
/// Se controla con un AnimationController de 0 → 1 (≈ 2 s).
///
/// Fases de la animación:
/// - 0.0–0.4: el texto entra con rebote elástico.
/// - 0.0–1.0: las partículas salen del centro y caen un poco.
/// - 0.8–1.0: todo se desvanece.
///
/// Usa [IgnorePointer] para no bloquear toques mientras se ve.
class CelebracionNivel extends StatelessWidget {
  const CelebracionNivel({super.key, required this.animacion, required this.nivel});

  final Animation<double> animacion;
  final int nivel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animacion,
      builder: (context, _) {
        final t = animacion.value;
        if (t == 0 || t == 1) return const SizedBox.shrink();

        final entrada = Curves.elasticOut.transform((t / 0.4).clamp(0.0, 1.0));
        final salida  = t > 0.8 ? (1 - (t - 0.8) / 0.2).clamp(0.0, 1.0) : 1.0;

        return IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Oscurece el fondo y deja un halo cyan en el centro
              Opacity(
                opacity: salida,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 0.9,
                      colors: [
                        AppColors.cyan.withAlpha((70 * (1 - t)).round()),
                        AppColors.background.withAlpha(190),
                      ],
                    ),
                  ),
                ),
              ),
              CustomPaint(painter: _ParticulasPainter(t)),
              Center(
                child: Opacity(
                  opacity: salida,
                  child: Transform.scale(
                    scale: 0.3 + 0.7 * entrada,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.military_tech_rounded,
                          size : 72,
                          color: AppColors.cyan,
                          shadows: [Shadow(color: AppColors.cyan, blurRadius: 30)],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '¡SUBISTE DE NIVEL!',
                          style: TextStyle(
                            color        : AppColors.textPrimary,
                            fontSize     : 16,
                            fontWeight   : FontWeight.bold,
                            letterSpacing: 3,
                            decoration   : TextDecoration.none,
                          ),
                        ),
                        Text(
                          'NIVEL $nivel',
                          style: const TextStyle(
                            color        : Colors.white,
                            fontSize     : 52,
                            fontWeight   : FontWeight.w900,
                            letterSpacing: 2,
                            decoration   : TextDecoration.none,
                            shadows: [
                              Shadow(color: AppColors.cyan, blurRadius: 24),
                              Shadow(color: _aqua, blurRadius: 48),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Una chispa de la explosión: dirección, distancia que recorre,
/// tamaño y color (elegidos al azar una sola vez).
class _Particula {
  _Particula(Random r)
      : angulo   = r.nextDouble() * 2 * pi,
        distancia = 110 + r.nextDouble() * 230,
        tam      = 2.5 + r.nextDouble() * 4.5,
        color    = const [AppColors.cyan, _aqua, AppColors.iceBlue, _periwinkle,
                          Colors.white][r.nextInt(5)];
  final double angulo, distancia, tam;
  final Color  color;
}

/// Dibuja las 42 partículas en el instante [t] (0..1) con un
/// [CustomPainter], que es mucho más barato que crear 42 widgets.
class _ParticulasPainter extends CustomPainter {
  _ParticulasPainter(this.t);
  final double t;

  // Mismas partículas en cada frame (semilla fija)
  static final List<_Particula> _particulas =
      List.generate(42, (_) => _Particula(_rnd));
  static final _rnd = Random(7);

  @override
  void paint(Canvas canvas, Size size) {
    final centro  = size.center(Offset.zero);
    final avance  = Curves.easeOutCubic.transform(t);
    final opacidad = (1 - t).clamp(0.0, 1.0);

    for (final p in _particulas) {
      final pos = centro +
          Offset(cos(p.angulo), sin(p.angulo)) * p.distancia * avance +
          Offset(0, 80 * t * t); // un poco de gravedad
      final paint = Paint()
        ..color = p.color.withAlpha((255 * opacidad).round())
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.drawCircle(pos, p.tam * (1 - 0.4 * t), paint);
    }
  }

  @override
  bool shouldRepaint(_ParticulasPainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// TOAST NEÓN "¡Nueva dificultad desbloqueada!"
// ─────────────────────────────────────────────────────────────────────────────

/// Notificación que baja desde arriba, se queda ~2 s y vuelve a subir.
///
/// Muestra el nombre de la [dificultad] desbloqueada y cuánto más rápido
/// caen las flechas. El borde late mientras está visible.
class ToastDificultad extends StatelessWidget {
  const ToastDificultad({super.key, required this.animacion, required this.dificultad});

  final Animation<double> animacion;
  final Dificultad dificultad;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animacion,
      builder: (context, _) {
        final t = animacion.value;
        if (t == 0 || t == 1) return const SizedBox.shrink();

        final visible = t < 0.12
            ? Curves.easeOutBack.transform(t / 0.12)
            : t > 0.88
                ? Curves.easeIn.transform((1 - t) / 0.12)
                : 1.0;
        // Pulso del borde mientras está visible
        final pulso = 0.5 + 0.5 * sin(t * 2 * pi * 4);

        return Transform.translate(
          offset: Offset(0, -90 * (1 - visible)),
          child: Opacity(
            opacity: visible.clamp(0.0, 1.0),
            child: Container(
              margin : const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color       : AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Color.lerp(_aqua.withAlpha(140), _aqua, pulso)!,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color     : _aqua.withAlpha((60 + 80 * pulso).round()),
                    blurRadius: 18 + 10 * pulso,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _aqua.withAlpha(30),
                    ),
                    child: const Icon(Icons.lock_open_rounded,
                        color: _aqua, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '¡Nueva dificultad desbloqueada!',
                          style: TextStyle(
                            color     : _aqua,
                            fontSize  : 14,
                            fontWeight: FontWeight.w900,
                            shadows   : [Shadow(color: _aqua, blurRadius: 10)],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${dificultad.nombre.toUpperCase()} · flechas '
                          '${dificultad.multiplicadorVelocidad.toStringAsFixed(1)}× más rápidas',
                          style: const TextStyle(
                            color   : AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.speed_rounded, color: _aqua, size: 22),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
