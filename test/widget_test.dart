import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ecostep/game/ddr_controller.dart';
import 'package:smart_ecostep/game/progresion.dart';
import 'package:smart_ecostep/models/energia_data.dart';

void main() {
  group('DdrController', () {
    test('pisada sin flecha cercana = "+ Voltaje!" y suma combo', () {
      final ddr = DdrController()..tick(0);
      final cal = ddr.registrarPisada(Carril.arriba, 12);

      expect(cal, Calificacion.libre);
      expect(ddr.combo, 1);
      expect(ddr.textos.single.titulo, '+ Voltaje!');
      expect(ddr.destello(Carril.arriba), greaterThan(0));
      expect(ddr.destello(Carril.abajo), 0);
    });

    test('pisada a tiempo con una flecha = PERFECTO y la flecha se consume', () {
      final ddr = DdrController()..setGenerando(true);
      ddr.tick(1000); // genera la primera flecha
      final flecha = ddr.flechas.single;
      ddr.setGenerando(false);

      ddr.tick(flecha.llegadaMs); // llega a la zona
      final cal = ddr.registrarPisada(flecha.carril, 20);

      expect(cal, Calificacion.perfecto);
      expect(ddr.flechas, isEmpty);
      expect(ddr.textos.single.titulo, '+ Energía');
    });

    test('el combo se reinicia tras un tiempo sin pisar', () {
      final ddr = DdrController()..tick(0);
      ddr.registrarPisada(Carril.izquierda, 10);
      ddr.registrarPisada(Carril.derecha, 10);
      expect(ddr.combo, 2);

      ddr.tick(DdrController.comboTimeoutMs + 1);
      expect(ddr.combo, 0);
      expect(ddr.comboMax, 2);
    });
  });

  group('Progresión', () {
    test('el tapete tiene 10 sensores en total', () {
      expect(Carril.values.fold<int>(0, (s, c) => s + c.sensores), 10);
    });

    test('voltaje → XP directo (1 V = 1 XP) y limitado a 33 V', () {
      expect(Progresion.xpDePisada(5.0), 5);
      expect(Progresion.xpDePisada(24.6), 25);
      // 10 sensores × 3.3 V = 33 V → 33 XP como máximo aunque llegue basura
      expect(Progresion.xpDePisada(999), 33);
      expect(Progresion.xpDePisada(-3), 0);
    });

    test('curva: niveles 1–2 rápidos y rampa exponencial desde el 3', () {
      final xp = [for (var n = 1; n <= 10; n++) Progresion.xpParaSubir(n)];
      // Valores documentados en progresion.dart
      expect(xp.take(7), [100, 303, 812, 1801, 3604, 6754, 12100]);

      // Cada nivel pide más que el anterior, y la proporción crece desde el 3
      for (var i = 1; i < xp.length; i++) {
        expect(xp[i], greaterThan(xp[i - 1]));
      }
      expect(xp[3] / xp[2], greaterThan(xp[1] / xp[0] * 0.7));
      expect(xp[9], greaterThan(xp[0] * 500)); // nivel 10 ≈ 590× el nivel 1
    });

    test('nivel y progreso a partir del XP total', () {
      expect(Progresion.estado(0).nivel, 1);
      expect(Progresion.estado(99).nivel, 1);
      final e = Progresion.estado(250); // 100 para el nivel 1, sobran 150
      expect(e.nivel, 2);
      expect(e.xpEnNivel, 150);
      expect(e.xpNecesario, 303);
      expect(Progresion.estado(3016).nivel, 5); // acumulado exacto del nivel 5
      expect(Progresion.estado(81905).nivel, 10);
      expect(Progresion.estado(81904).nivel, 9);
    });

    test('dificultades: casi extrema desde el nivel 5', () {
      expect(Dificultad.paraNivel(2), Dificultad.normal);
      expect(Dificultad.paraNivel(3), Dificultad.dificil);
      expect(Dificultad.paraNivel(5), Dificultad.extremo);
      expect(Dificultad.paraNivel(7), Dificultad.leyenda);
      expect(Dificultad.paraNivel(15), Dificultad.imposible);

      expect(Dificultad.extremo.esExtrema, isTrue);
      expect(Dificultad.dificil.esExtrema, isFalse);
      // En nivel 5 la flecha cruza el tablero en menos de 1 s (≥ 2.4×)
      expect(Dificultad.paraNivel(5).caidaMs, lessThan(1000));
      expect(Dificultad.paraNivel(5).multiplicadorVelocidad,
          greaterThanOrEqualTo(2.4));
    });

    test('las flechas nuevas caen con la velocidad de la dificultad actual', () {
      final ddr = DdrController()
        ..dificultad = Dificultad.extremo
        ..setGenerando(true)
        ..tick(1000);
      expect(ddr.flechas.single.caidaMs, Dificultad.extremo.caidaMs);
    });
  });

  test('Pisada.fromMap ignora carriles inválidos', () {
    expect(Pisada.fromMap({'id': 1, 'carril': 'diagonal'}), isNull);
    expect(Pisada.fromMap({'id': 1, 'carril': 'abajo'})?.carril, Carril.abajo);
  });
}
