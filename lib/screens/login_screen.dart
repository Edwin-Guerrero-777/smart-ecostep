/// Pantalla de inicio de sesión con correo y contraseña (Firebase Auth).
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:smart_ecostep/main.dart';
import 'package:smart_ecostep/screens/home_screen.dart';
import 'package:smart_ecostep/screens/register_screen.dart';

/// Primera pantalla de la app.
///
/// - Valida el formulario localmente antes de llamar a Firebase.
/// - Si el login es correcto, reemplaza toda la pila de navegación por
///   [HomeScreen] (el botón "atrás" no regresa al login).
/// - Desde aquí se puede ir a [RegisterScreen] para crear una cuenta.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Estado del login: controladores del formulario, indicador de carga
/// y la animación de entrada (fade + deslizamiento hacia arriba).
class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  // ── Formulario ────────────────────────────────────────────────────────────
  final _formKey         = GlobalKey<FormState>();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();

  // ── Estado ────────────────────────────────────────────────────────────────
  bool _isLoading       = false;
  bool _obscurePassword = true;

  // ── Animación de entrada ──────────────────────────────────────────────────
  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Sign-in ───────────────────────────────────────────────────────────────

  /// Valida el formulario e intenta iniciar sesión en Firebase.
  ///
  /// Mientras espera, [_isLoading] desactiva el botón y muestra un spinner.
  /// Los errores de Firebase se traducen a español con [_mapAuthError].
  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await _auth.signInWithEmailAndPassword(
        email   : _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      _showSnackBar(_mapAuthError(e.code), isError: true);
    } catch (_) {
      _showSnackBar('Error inesperado. Intenta de nuevo.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Convierte un código de [FirebaseAuthException] en un mensaje
  /// entendible para el usuario.
  String _mapAuthError(String code) {
    switch (code) {
      case 'user-not-found'   : return 'No existe una cuenta con ese correo.';
      case 'wrong-password'   : return 'Contraseña incorrecta.';
      case 'invalid-email'    : return 'El formato del correo no es válido.';
      case 'user-disabled'    : return 'Esta cuenta ha sido deshabilitada.';
      case 'too-many-requests': return 'Demasiados intentos. Espera unos minutos.';
      case 'invalid-credential': return 'Credenciales inválidas. Verifica tu correo y contraseña.';
      default: return 'Error de autenticación ($code).';
    }
  }

  /// Muestra un SnackBar con ícono rojo ([isError]) o verde (éxito).
  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? AppColors.error : AppColors.success,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Fondo con gradiente sutil ─────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.3, -0.6),
                radius: 1.0,
                colors: [Color(0xFF0D1F3C), AppColors.background],
              ),
            ),
          ),

          // ── Contenido ─────────────────────────────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Logo / Ícono neón ───────────────────────────
                          _NeonIcon(
                            icon: Icons.directions_walk_rounded,
                            size: 72,
                          ),
                          const SizedBox(height: 20),

                          // ── Título ──────────────────────────────────────
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [AppColors.cyan, AppColors.cyanSoft],
                            ).createShader(bounds),
                            child: const Text(
                              'Smart Eco-Step',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize  : 30,
                                fontWeight: FontWeight.bold,
                                color     : Colors.white,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Genera energía con cada pisada',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color   : AppColors.textSecondary,
                              fontSize: 13,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 44),

                          // ── Campo: Correo ───────────────────────────────
                          TextFormField(
                            controller     : _emailController,
                            keyboardType   : TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            style          : const TextStyle(color: AppColors.textPrimary),
                            decoration     : const InputDecoration(
                              labelText : 'Correo electrónico',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Ingresa tu correo';
                              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                                return 'Formato de correo inválido';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // ── Campo: Contraseña ───────────────────────────
                          TextFormField(
                            controller     : _passwordController,
                            obscureText    : _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _signIn(),
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              labelText : 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Ingresa tu contraseña';
                              if (v.length < 6) return 'Mínimo 6 caracteres';
                              return null;
                            },
                          ),
                          const SizedBox(height: 32),

                          // ── Botón principal ─────────────────────────────
                          _NeonButton(
                            onPressed: _isLoading ? null : _signIn,
                            isLoading: _isLoading,
                            label    : 'Iniciar sesión',
                          ),
                          const SizedBox(height: 24),

                          // ── Divider con texto ───────────────────────────
                          Row(
                            children: const [
                              Expanded(child: Divider()),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  '¿Nuevo aquí?',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // ── Botón outline: Registro ─────────────────────
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const RegisterScreen()),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.cyan,
                              side: const BorderSide(
                                  color: AppColors.cyan, width: 1.4),
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Crear cuenta',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize  : 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widgets de diseño compartidos ────────────────────────────────────────────

/// Ícono circular con glow neón cyan
class _NeonIcon extends StatelessWidget {
  const _NeonIcon({required this.icon, this.size = 64});
  final IconData icon;
  final double   size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width : size + 32,
        height: size + 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.cardElevated,
          border: Border.all(color: AppColors.cyan.withAlpha(100), width: 1.5),
          boxShadow: [
            BoxShadow(
              color : AppColors.cyan.withAlpha(50),
              blurRadius  : 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(icon, size: size, color: AppColors.cyan),
      ),
    );
  }
}

/// Botón elevado con efecto glow neón.
///
/// Si [onPressed] es null (por ejemplo, mientras carga) se desactiva y pierde
/// el brillo. Con [isLoading] muestra un spinner en lugar del texto.
class _NeonButton extends StatelessWidget {
  const _NeonButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });
  final String    label;
  final VoidCallback? onPressed;
  final bool      isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: onPressed != null
            ? [
                BoxShadow(
                  color : AppColors.cyan.withAlpha(70),
                  blurRadius  : 18,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        child: isLoading
            ? const SizedBox(
                height: 22,
                width : 22,
                child : CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.background,
                ),
              )
            : Text(label),
      ),
    );
  }
}
