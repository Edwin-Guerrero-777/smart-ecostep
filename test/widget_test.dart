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

    test('voltaje → XP directo y limitado al máximo físico de la flecha', () {
      expect(Progresion.xpDePisada(5.0, Carril.izquierda), 50);
      // Abajo tiene 2 sensores → máximo 6.6 V → 66 XP aunque llegue basura
      expect(Progresion.xpDePisada(99, Carril.abajo), 66);
      expect(Progresion.xpDePisada(-3, Carril.abajo), 0);
    });

    test('nivel y progreso a partir del XP total', () {
      expect(Progresion.estado(0).nivel, 1);
      expect(Progresion.estado(249).nivel, 1);
      final e = Progresion.estado(250 + 100); // pasa a nivel 2 con 100 de sobra
      expect(e.nivel, 2);
      expect(e.xpEnNivel, 100);
      expect(e.xpNecesario, 400);
    });

    test('la dificultad se desbloquea en niveles 3, 5 y 8', () {
      expect(Dificultad.paraNivel(2), Dificultad.normal);
      expect(Dificultad.paraNivel(3), Dificultad.dificil);
      expect(Dificultad.paraNivel(5), Dificultad.experto);
      expect(Dificultad.paraNivel(12), Dificultad.maestro);
    });

    test('las flechas nuevas caen con la velocidad de la dificultad actual', () {
      final ddr = DdrController()
        ..dificultad = Dificultad.experto
        ..setGenerando(true)
        ..tick(1000);
      expect(ddr.flechas.single.caidaMs, Dificultad.experto.caidaMs);
    });
  });

  test('Pisada.fromMap ignora carriles inválidos', () {
    expect(Pisada.fromMap({'id': 1, 'carril': 'diagonal'}), isNull);
    expect(Pisada.fromMap({'id': 1, 'carril': 'abajo'})?.carril, Carril.abajo);
  });
}
