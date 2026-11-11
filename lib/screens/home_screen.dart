import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:smart_ecostep/main.dart';
import 'package:smart_ecostep/models/step_data.dart';
import 'package:smart_ecostep/screens/login_screen.dart';
import 'package:smart_ecostep/services/database_service.dart';

/// Meta diaria de pasos (para la barra de progreso)
const int kMetaPasos = 10000;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Stream<StepData> _stream;

  // ── Simulador ESP32 (modo secreto) ────────────────────────────────────────
  Timer?   _simTimer;
  StepData _ultimo = StepData.empty();
  final _rnd = Random();

  bool get _simulando => _simTimer != null;

  @override
  void initState() {
    super.initState();
    _stream = DatabaseService.instance.stepDataStream;
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    super.dispose();
  }

  /// Se activa manteniendo presionado el título de la AppBar.
  void _toggleSimulacion() {
    if (_simulando) {
      _detenerSimulacion();
    } else {
      _iniciarSimulacion();
    }
  }

  void _iniciarSimulacion() {
    setState(() {
      _simTimer = Timer.periodic(const Duration(seconds: 2), (_) => _tickSimulacion());
    });
    _tickSimulacion();
    _snack('🧪 Simulación ESP32 activada');
  }

  Future<void> _detenerSimulacion() async {
    _simTimer?.cancel();
    setState(() => _simTimer = null);
    // Conserva los últimos valores pero marca el dispositivo como inactivo
    try {
      await DatabaseService.instance.marcarInactivo();
    } catch (_) {}
    _snack('⏹ Simulación detenida');
  }

  /// Genera una lectura falsa que imita al ESP32 (≈ caminata normal).
  Future<void> _tickSimulacion() async {
    final nuevosPasos = _ultimo.pasos + 2 + _rnd.nextInt(5); // 2–6 pasos / 2 s
    final datos = StepData(
      pasos              : nuevosPasos,
      distanciaMetros    : nuevosPasos * 0.75, // zancada promedio 75 cm
      calorias           : nuevosPasos * 0.04, // ≈ 0.04 kcal por paso
      frecuenciaCardiaca : 85 + _rnd.nextInt(30),
      ultimaActualizacion: DateTime.now(),
      dispositivoActivo  : true,
    );
    try {
      await DatabaseService.instance.simularDatosESP32(datos);
    } catch (e) {
      _simTimer?.cancel();
      if (mounted) setState(() => _simTimer = null);
      _snack('Error al escribir en Firebase: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content : Text(msg),
        backgroundColor: AppColors.cardElevated,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _signOut(BuildContext context) async {
    _simTimer?.cancel();
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user        = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Usuario';
    final email       = user?.email ?? '';
    final uid         = user?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        // Mantener presionado el título = botón secreto "Simular ESP32"
        title: GestureDetector(
          onLongPress: _toggleSimulacion,
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width : 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _simulando ? AppColors.warning : AppColors.cyan,
                  boxShadow: [
                    BoxShadow(
                        color: _simulando ? AppColors.warning : AppColors.cyan,
                        blurRadius: 6,
                        spreadRadius: 1),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Text('Smart Eco-Step'),
            ],
          ),
        ),
        actions: [
          if (_simulando)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ActionChip(
                avatar: const Icon(Icons.stop_circle_rounded,
                    size: 16, color: AppColors.warning),
                label: const Text('SIM',
                    style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
                backgroundColor: AppColors.warning.withAlpha(25),
                side: BorderSide(color: AppColors.warning.withAlpha(90)),
                onPressed: _detenerSimulacion,
              ),
            ),
          IconButton(
            icon   : const Icon(Icons.power_settings_new_rounded),
            tooltip: 'Cerrar sesión',
            onPressed: () => _signOut(context),
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
          // ── Fondo con gradiente ─────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.6, -0.5),
                radius: 0.85,
                colors: [Color(0xFF0A1A30), AppColors.background],
              ),
            ),
          ),

          // ── Contenido (reactivo a Firebase) ─────────────────────────────
          SafeArea(
            child: StreamBuilder<StepData>(
              stream: _stream,
              builder: (context, snap) {
                final conectadoDb = snap.hasData && !snap.hasError;
                final datos       = snap.data ?? StepData.empty();
                _ultimo = datos;
                return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                // ── Tarjeta de perfil ─────────────────────────────────────
                _ProfileCard(
                  displayName: displayName,
                  email      : email,
                  uid        : uid,
                ),
                const SizedBox(height: 20),

                // ── Título sección ────────────────────────────────────────
                Row(
                  children: const [
                    Icon(Icons.dashboard_rounded,
                        color: AppColors.cyan, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'PANEL DE CONTROL',
                      style: TextStyle(
                        color      : AppColors.cyan,
                        fontSize   : 11,
                        fontWeight : FontWeight.bold,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Dashboard IoT ─────────────────────────────────────────
                _IotDashboardCard(
                  conectadoDb : conectadoDb,
                  esp32Activo : datos.dispositivoActivo,
                  simulando   : _simulando,
                ),
                const SizedBox(height: 20),

                // ── Estadísticas en vivo ──────────────────────────────────
                _StatsCard(datos: datos),
                const SizedBox(height: 20),

                // ── Banner info ESP32 ─────────────────────────────────────
                _Esp32InfoBanner(
                  esp32Activo: datos.dispositivoActivo,
                  simulando  : _simulando,
                ),
                const SizedBox(height: 28),

                // ── Pie ───────────────────────────────────────────────────
                const Text(
                  'Smart Eco-Step  •  v1.1  •  Fase 2: datos en vivo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color   : AppColors.textSecondary,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS INTERNOS
// ─────────────────────────────────────────────────────────────────────────────

/// Tarjeta de perfil del usuario
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.displayName,
    required this.email,
    required this.uid,
  });
  final String displayName, email, uid;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end  : Alignment.bottomRight,
          colors: [Color(0xFF0D2137), Color(0xFF111827)],
        ),
        border: Border.all(color: AppColors.cyan.withAlpha(60), width: 1),
        boxShadow: [
          BoxShadow(
            color : AppColors.cyan.withAlpha(20),
            blurRadius  : 20,
            spreadRadius: 0,
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Avatar circular con glow
          Container(
            width : 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.cyan, AppColors.cyanSoft],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cyan.withAlpha(80),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Center(
              child: Text(
                displayName.isNotEmpty
                    ? displayName[0].toUpperCase()
                    : 'U',
                style: const TextStyle(
                  color     : AppColors.background,
                  fontSize  : 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¡Hola, $displayName!',
                  style: const TextStyle(
                    color     : AppColors.textPrimary,
                    fontSize  : 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.fingerprint,
                        color: AppColors.cyan, size: 12),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        uid.length > 16 ? '${uid.substring(0, 16)}…' : uid,
                        style: const TextStyle(
                          color  : AppColors.textSecondary,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel de estado del sistema estilo IoT dashboard
class _IotDashboardCard extends StatelessWidget {
  const _IotDashboardCard({
    required this.conectadoDb,
    required this.esp32Activo,
    required this.simulando,
  });
  final bool conectadoDb, esp32Activo, simulando;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.surface,
        border: Border.all(color: AppColors.cardBorder),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Encabezado ──────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color : AppColors.cyan.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cyan.withAlpha(60)),
                ),
                child: const Icon(Icons.sensors_rounded,
                    color: AppColors.cyan, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estado del sistema',
                    style: TextStyle(
                      color     : AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize  : 15,
                    ),
                  ),
                  Text(
                    'Monitoreo en tiempo real',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Filas de estado ──────────────────────────────────────────────
          _DashboardStatusRow(
            icon      : Icons.verified_user_rounded,
            iconColor : AppColors.success,
            label     : 'Autenticación Firebase',
            status    : 'ACTIVA',
            statusColor: AppColors.success,
            glowColor : AppColors.success,
          ),
          _DashboardDivider(),
          _DashboardStatusRow(
            icon      : conectadoDb
                ? Icons.cloud_done_rounded
                : Icons.cloud_sync_rounded,
            iconColor : conectadoDb ? AppColors.success : AppColors.warning,
            label     : 'Realtime Database',
            status    : conectadoDb ? 'CONECTADO' : 'CONECTANDO…',
            statusColor: conectadoDb ? AppColors.success : AppColors.warning,
            glowColor : conectadoDb ? AppColors.success : AppColors.warning,
          ),
          const _DashboardDivider(),
          _DashboardStatusRow(
            icon      : Icons.developer_board_rounded,
            iconColor : esp32Activo ? AppColors.success : AppColors.warning,
            label     : simulando ? 'ESP32 (simulado)' : 'ESP32',
            status    : esp32Activo
                ? (simulando ? 'SIMULADO' : 'EN LÍNEA')
                : 'EN ESPERA',
            statusColor: esp32Activo ? AppColors.success : AppColors.warning,
            glowColor : esp32Activo ? AppColors.success : AppColors.warning,
          ),
          const _DashboardDivider(),
          _DashboardStatusRow(
            icon      : Icons.wifi_tethering_rounded,
            iconColor : esp32Activo ? AppColors.success : AppColors.warning,
            label     : 'Stream de datos',
            status    : esp32Activo ? 'RECIBIENDO' : 'PENDIENTE',
            statusColor: esp32Activo ? AppColors.success : AppColors.warning,
            glowColor : esp32Activo ? AppColors.success : AppColors.warning,
          ),
        ],
      ),
    );
  }
}

class _DashboardStatusRow extends StatelessWidget {
  const _DashboardStatusRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.status,
    required this.statusColor,
    required this.glowColor,
  });
  final IconData icon;
  final Color    iconColor, statusColor, glowColor;
  final String   label, status;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
          // Badge de estado (anima color y texto al cambiar)
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: glowColor.withAlpha(25),
              border: Border.all(color: glowColor.withAlpha(80), width: 1),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                status,
                key: ValueKey(status),
                style: TextStyle(
                  color     : statusColor,
                  fontSize  : 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardDivider extends StatelessWidget {
  const _DashboardDivider();

  @override
  Widget build(BuildContext context) => const Divider(
        color    : AppColors.cardBorder,
        height   : 1,
        thickness: 1,
      );
}


/// Estadísticas de hoy — se actualizan en vivo con animación.
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.datos});
  final StepData datos;

  @override
  Widget build(BuildContext context) {
    final progreso = (datos.pasos / kMetaPasos).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.surface,
        border: Border.all(color: AppColors.cardBorder),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded,
                  color: AppColors.cyan, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Estadísticas de hoy',
                  style: TextStyle(
                    color     : AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize  : 15,
                  ),
                ),
              ),
              _BpmIndicator(datos: datos),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _MiniStatBox(
                icon  : Icons.directions_walk_rounded,
                value : datos.pasos.toDouble(),
                format: (v) => v.round().toString(),
                label : 'Pasos',
              ),
              const SizedBox(width: 12),
              _MiniStatBox(
                icon  : Icons.straighten_rounded,
                value : datos.distanciaMetros,
                format: (v) => v >= 1000
                    ? '${(v / 1000).toStringAsFixed(2)} km'
                    : '${v.toStringAsFixed(0)} m',
                label : 'Distancia',
              ),
              const SizedBox(width: 12),
              _MiniStatBox(
                icon  : Icons.local_fire_department_rounded,
                value : datos.calorias,
                format: (v) => v.toStringAsFixed(1),
                label : 'kcal',
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── Progreso hacia la meta diaria ───────────────────────────────
          Row(
            children: [
              const Text('Meta diaria',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
              const Spacer(),
              Text(
                '${(progreso * 100).toStringAsFixed(0)}%  de $kMetaPasos',
                style: const TextStyle(
                    color: AppColors.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween   : Tween(end: progreso),
            duration: const Duration(milliseconds: 900),
            curve   : Curves.easeOutCubic,
            builder : (context, v, child) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value          : v,
                minHeight      : 8,
                backgroundColor: AppColors.cardElevated,
                valueColor     : const AlwaysStoppedAnimation(AppColors.cyan),
              ),
            ),
          ),

          if (!datos.dispositivoActivo) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color       : AppColors.cardElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppColors.textSecondary, size: 14),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Los datos se mostrarán en tiempo real cuando el ESP32 esté conectado',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Corazón que "late" cada vez que llega un nuevo BPM.
class _BpmIndicator extends StatelessWidget {
  const _BpmIndicator({required this.datos});
  final StepData datos;

  @override
  Widget build(BuildContext context) {
    final activo = datos.frecuenciaCardiaca > 0 && datos.dispositivoActivo;
    return TweenAnimationBuilder<double>(
      key     : ValueKey(datos.ultimaActualizacion.millisecondsSinceEpoch),
      tween   : Tween(begin: activo ? 1.35 : 1.0, end: 1.0),
      duration: const Duration(milliseconds: 450),
      curve   : Curves.elasticOut,
      builder : (context, s, child) => Transform.scale(scale: s, child: child),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_rounded,
              size : 16,
              color: activo ? AppColors.error : AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            datos.bpmFormateado,
            style: TextStyle(
              color     : activo ? AppColors.error : AppColors.textSecondary,
              fontSize  : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatBox extends StatelessWidget {
  const _MiniStatBox({
    required this.icon,
    required this.value,
    required this.format,
    required this.label,
  });
  final IconData icon;
  final double   value;
  final String Function(double) format;
  final String   label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(
          color : AppColors.cardElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.cyan, size: 22),
            const SizedBox(height: 6),
            // Cuenta animada desde el valor anterior al nuevo
            TweenAnimationBuilder<double>(
              tween   : Tween(end: value),
              duration: const Duration(milliseconds: 800),
              curve   : Curves.easeOutCubic,
              builder : (context, v, child) => FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  format(v),
                  style: const TextStyle(
                    color     : AppColors.cyan,
                    fontSize  : 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner informativo sobre la conexión con ESP32
class _Esp32InfoBanner extends StatelessWidget {
  const _Esp32InfoBanner({
    required this.esp32Activo,
    required this.simulando,
  });
  final bool esp32Activo, simulando;

  @override
  Widget build(BuildContext context) {
    final color = esp32Activo ? AppColors.success : AppColors.cyan;
    final titulo = simulando
        ? 'Simulación ESP32 en curso'
        : esp32Activo
            ? 'ESP32 conectado'
            : 'Sistema listo para ESP32';
    final texto = simulando
        ? 'La app está escribiendo lecturas falsas en Firebase\n'
          'cada 2 s. Toca "SIM" arriba para detenerla.'
        : esp32Activo
            ? 'Recibiendo datos del módulo IoT en tiempo real\n'
              'desde Firebase Realtime Database.'
            : 'Esperando que el ESP32 publique datos.\n'
              'Tip: mantén presionado el título para simular.';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [color.withAlpha(15), AppColors.cyanSoft.withAlpha(10)],
        ),
        border: Border.all(color: color.withAlpha(60), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color : color.withAlpha(20),
              shape : BoxShape.circle,
            ),
            child: Icon(Icons.developer_board_rounded, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    color     : color,
                    fontWeight: FontWeight.bold,
                    fontSize  : 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  texto,
                  style: const TextStyle(
                    color : AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
