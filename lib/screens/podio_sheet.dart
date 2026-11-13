/// Podio / leaderboard: ranking de jugadores por energía generada (XP).
///
/// Por ahora los rivales son **simulados** (lista fija). El usuario actual
/// se inserta con su XP real y se ordena junto a ellos.
library;

import 'package:flutter/material.dart';
import 'package:smart_ecostep/game/progresion.dart';
import 'package:smart_ecostep/main.dart';

/// Jugador del ranking.
class JugadorRanking {
  const JugadorRanking(this.nombre, this.xp, {this.esUsuario = false});

  /// Nombre visible
  final String nombre;

  /// XP total (energía generada)
  final int xp;

  /// true para el usuario con sesión iniciada (se resalta en cyan)
  final bool esUsuario;
}

/// Ranking SIMULADO (más adelante se puede leer de Firebase:
/// usuarios/*/progreso/xp_total ordenado con orderByChild).
///
/// Valores pensados para la curva exponencial (1 V = 1 XP): el líder está
/// en nivel 10 tras miles de pisadas; la mayoría se queda entre 3 y 6.
const List<JugadorRanking> _rivalesSimulados = [
  JugadorRanking('NeonStomper', 92400), // nivel 10 · Imposible
  JugadorRanking('VoltQueen',   41800), // nivel 8  · Leyenda
  JugadorRanking('PiezoKid',    27300), // nivel 8  · Leyenda
  JugadorRanking('AquaDash',    15600), // nivel 7  · Leyenda
  JugadorRanking('EcoPulse',     9800), // nivel 6  · Extremo
  JugadorRanking('WattWalker',   5200), // nivel 5  · Extremo
  JugadorRanking('BlueSpark',    2900), // nivel 4  · Difícil
  JugadorRanking('TidalStep',    1450), // nivel 4  · Difícil
  JugadorRanking('JouleJumper',   640), // nivel 3  · Difícil
  JugadorRanking('OceanBeat',     180), // nivel 2  · Normal
];

const _oro    = Color(0xFFFFD54F);
const _plata  = Color(0xFFCFD8DC);
const _bronce = Color(0xFFFFAB91);

/// Abre el Podio como hoja inferior deslizable.
///
/// Muestra los 3 primeros en pedestales (2º · 1º · 3º) y el resto en
/// una lista. La hoja se puede arrastrar entre 50 % y 95 % de la pantalla.
Future<void> mostrarPodio(
  BuildContext context, {
  required String nombreUsuario,
  required int    xpUsuario,
}) {
  final ranking = [
    ..._rivalesSimulados,
    JugadorRanking(nombreUsuario, xpUsuario, esUsuario: true),
  ]..sort((a, b) => b.xp.compareTo(a.xp));

  return showModalBottomSheet(
    context           : context,
    isScrollControlled: true,
    backgroundColor   : Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize    : 0.5,
      maxChildSize    : 0.95,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color       : AppColors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border      : Border.all(color: AppColors.cardBorder),
          boxShadow   : [
            BoxShadow(color: AppColors.cyan.withAlpha(40), blurRadius: 30),
          ],
        ),
        child: ListView(
          controller: scroll,
          padding   : const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children  : [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color       : AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emoji_events_rounded, color: _oro, size: 26,
                    shadows: [Shadow(color: _oro, blurRadius: 14)]),
                SizedBox(width: 8),
                Text(
                  'PODIO DE ENERGÍA',
                  style: TextStyle(
                    color        : AppColors.textPrimary,
                    fontSize     : 18,
                    fontWeight   : FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Ranking simulado · XP = energía generada pisando el tapete',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 24),

            // ── Podio top 3 (2º · 1º · 3º) ──────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: _Pedestal(jugador: ranking[1], puesto: 2, alto: 92,  color: _plata)),
                const SizedBox(width: 8),
                Expanded(child: _Pedestal(jugador: ranking[0], puesto: 1, alto: 128, color: _oro)),
                const SizedBox(width: 8),
                Expanded(child: _Pedestal(jugador: ranking[2], puesto: 3, alto: 70,  color: _bronce)),
              ],
            ),
            const SizedBox(height: 22),

            // ── Resto de la tabla ───────────────────────────────────────────
            for (var i = 3; i < ranking.length; i++)
              _FilaRanking(jugador: ranking[i], puesto: i + 1, indice: i),
          ],
        ),
      ),
    ),
  );
}

/// Columna del podio: avatar, nombre, XP y un pedestal que crece al abrir.
/// El 1º lleva corona; los colores son oro, plata y bronce.
class _Pedestal extends StatelessWidget {
  const _Pedestal({
    required this.jugador,
    required this.puesto,
    required this.alto,
    required this.color,
  });
  final JugadorRanking jugador;
  final int    puesto;
  final double alto;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    final borde = jugador.esUsuario ? AppColors.cyan : color;
    return Column(
      children: [
        if (puesto == 1)
          const Icon(Icons.workspace_premium_rounded, color: _oro, size: 22,
              shadows: [Shadow(color: _oro, blurRadius: 12)]),
        _Avatar(jugador: jugador, color: borde, radio: puesto == 1 ? 30 : 25),
        const SizedBox(height: 6),
        Text(
          jugador.esUsuario ? 'Tú' : jugador.nombre,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color     : jugador.esUsuario ? AppColors.cyan : AppColors.textPrimary,
            fontSize  : 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          '${jugador.xp} XP',
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        // El pedestal "crece" al abrir el Podio
        TweenAnimationBuilder<double>(
          tween   : Tween(begin: 0, end: alto),
          duration: Duration(milliseconds: 500 + 150 * puesto),
          curve   : Curves.easeOutBack,
          builder : (context, h, child) => Container(
            height: h.clamp(0.0, double.infinity),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              gradient: LinearGradient(
                begin : Alignment.topCenter,
                end   : Alignment.bottomCenter,
                colors: [color.withAlpha(110), color.withAlpha(20)],
              ),
              border: Border.all(color: color.withAlpha(160)),
              boxShadow: [BoxShadow(color: color.withAlpha(60), blurRadius: 16)],
            ),
            alignment: Alignment.topCenter,
            padding  : const EdgeInsets.only(top: 6),
            child: h > 30
                ? Text(
                    '$puesto',
                    style: TextStyle(
                      color     : Colors.white,
                      fontSize  : 26,
                      fontWeight: FontWeight.w900,
                      shadows   : [Shadow(color: color, blurRadius: 14)],
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

/// Fila de la tabla (puesto 4 en adelante) con nivel, dificultad y XP.
/// Entra deslizándose, con un pequeño retraso según su posición.
class _FilaRanking extends StatelessWidget {
  const _FilaRanking({required this.jugador, required this.puesto, required this.indice});
  final JugadorRanking jugador;
  final int puesto, indice;

  @override
  Widget build(BuildContext context) {
    final yo    = jugador.esUsuario;
    final nivel = Progresion.estado(jugador.xp).nivel;

    // Entrada escalonada desde la derecha
    return TweenAnimationBuilder<double>(
      tween   : Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + 60 * indice),
      curve   : Curves.easeOutCubic,
      builder : (context, v, child) => Opacity(
        opacity: v,
        child  : Transform.translate(offset: Offset(40 * (1 - v), 0), child: child),
      ),
      child: Container(
        margin : const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color       : yo ? AppColors.cyan.withAlpha(22) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: yo ? AppColors.cyan.withAlpha(160) : AppColors.cardBorder),
          boxShadow: yo
              ? [BoxShadow(color: AppColors.cyan.withAlpha(50), blurRadius: 12)]
              : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '#$puesto',
                style: const TextStyle(
                  color     : AppColors.textSecondary,
                  fontSize  : 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _Avatar(jugador: jugador, color: yo ? AppColors.cyan : AppColors.iceBlue, radio: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    yo ? '${jugador.nombre} (Tú)' : jugador.nombre,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color     : yo ? AppColors.cyan : AppColors.textPrimary,
                      fontSize  : 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Nivel $nivel · ${Dificultad.paraNivel(nivel).nombre}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10),
                  ),
                ],
              ),
            ),
            Text(
              '${jugador.xp} XP',
              style: const TextStyle(
                color     : AppColors.cyan,
                fontSize  : 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Círculo con la inicial del jugador y borde luminoso.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.jugador, required this.color, required this.radio});
  final JugadorRanking jugador;
  final Color  color;
  final double radio;

  @override
  Widget build(BuildContext context) {
    return Container(
      width : radio * 2,
      height: radio * 2,
      decoration: BoxDecoration(
        shape : BoxShape.circle,
        color : AppColors.cardElevated,
        border: Border.all(color: color, width: 2),
        boxShadow: [BoxShadow(color: color.withAlpha(90), blurRadius: 10)],
      ),
      alignment: Alignment.center,
      child: Text(
        jugador.nombre.isNotEmpty ? jugador.nombre[0].toUpperCase() : '?',
        style: TextStyle(
          color     : color,
          fontSize  : radio * 0.9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
