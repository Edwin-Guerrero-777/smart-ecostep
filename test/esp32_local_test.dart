import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ecostep/models/energia_data.dart';
import 'package:smart_ecostep/services/esp32_local_service.dart';

void main() {
  group('MensajeEsp32.parsear', () {
    test('pisada del firmware → Pisada + energía', () {
      final m = MensajeEsp32.parsear(
        '{"tipo":"pisada","id":42,"carril":"arriba","voltaje":4.125,'
        '"energia_j":0.00004,"potencia_w":0.0008,"energia_total_j":0.0012}',
        EnergiaData.vacia(),
      )!;
      expect(m.pisada!.id, 42);
      expect(m.pisada!.carril, Carril.arriba);
      expect(m.pisada!.voltaje, 4.125);
      expect(m.energia.energiaTotalJ, 0.0012);
      expect(m.energia.activo, isTrue);
    });

    test('estado sin pisada conserva lo que no viene', () {
      final m = MensajeEsp32.parsear(
        '{"tipo":"hola","activo":true,"sensores":4}',
        EnergiaData.vacia(),
      )!;
      expect(m.pisada, isNull);
      expect(m.energia.activo, isTrue);
      expect(m.energia.energiaTotalJ, 0);
    });

    test('basura o tipos desconocidos se ignoran', () {
      final v = EnergiaData.vacia();
      expect(MensajeEsp32.parsear('no es json', v), isNull);
      expect(MensajeEsp32.parsear('[1,2,3]', v), isNull);
      expect(MensajeEsp32.parsear('{"tipo":"otro"}', v), isNull);
    });
  });

  test('validación de la IP escrita por el usuario', () {
    expect(esIpValida('172.20.10.5'), isTrue);
    expect(esIpValida(' 192.168.1.50 '), isTrue);
    expect(esIpValida('192.168.1'), isFalse);
    expect(esIpValida('192.168.1.300'), isFalse);
    expect(esIpValida('hola'), isFalse);
    expect(esIpValida('1..2.3'), isFalse);
  });

  test('modo misma red: el error recuerda revisar red, IP y MODO_LOCAL 2', () {
    final m = Esp32LocalService.describirError(
        'TimeoutException', '172.20.10.5', 3333);
    expect(m, contains('MISMA red'));
    expect(m, contains('MODO_LOCAL 2'));
  });

  test('los errores se traducen a pistas útiles', () {
    String d(String e) =>
        Esp32LocalService.describirError(e, '192.168.4.1', 3333);
    expect(d('TimeoutException after 0:00:03'), contains('SmartEcoStep'));
    expect(d('SocketException: Connection refused'), contains('MODO_LOCAL'));
  });

  test('Esp32LocalService recibe pisadas de un "ESP32" WebSocket falso',
      () async {
    // Servidor WebSocket que imita al firmware en modo local
    final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servidor.listen((peticion) async {
      final ws = await WebSocketTransformer.upgrade(peticion);
      ws.add('{"tipo":"hola","activo":true,"sensores":4}');
      ws.add('{"tipo":"pisada","id":1,"carril":"izquierda","voltaje":3.0,'
          '"energia_j":0.00001}');
      ws.add('{"tipo":"pisada","id":2,"carril":"derecha","voltaje":5.0,'
          '"energia_j":0.00002}');
    });

    final servicio =
        Esp32LocalService(host: '127.0.0.1', puerto: servidor.port);
    final pisadas = <Pisada>[];
    final sub = servicio.pisadaStream.listen((p) => pisadas.add(p!));
    servicio.iniciar();

    // Espera (máx. 3 s) a que lleguen las dos pisadas
    for (var i = 0; i < 60 && pisadas.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(servicio.estado.value, EstadoLocal.conectado);
    expect(pisadas.map((p) => p.carril), [Carril.izquierda, Carril.derecha]);
    expect(pisadas.map((p) => p.id), [1, 2]);

    await sub.cancel();
    servicio.dispose();
    await servidor.close(force: true);
  });
}
