import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:smart_ecostep/main.dart';
import 'package:smart_ecostep/screens/home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  // ── Formulario ────────────────────────────────────────────────────────────
  final _formKey                  = GlobalKey<FormState>();
  final _nameController           = TextEditingController();
  final _emailController          = TextEditingController();
  final _passwordController       = TextEditingController();
  final _confirmPasswordController= TextEditingController();

  bool _isLoading             = false;
  bool _obscurePassword       = true;
  bool _obscureConfirmPassword= true;

  // ── Animación ─────────────────────────────────────────────────────────────
  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeAnim;

  final FirebaseAuth      _auth  = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ── Lógica de registro ────────────────────────────────────────────────────
  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final UserCredential credential =
          await _auth.createUserWithEmailAndPassword(
        email   : _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final User user = credential.user!;

      await user.updateDisplayName(_nameController.text.trim());

      // Guardar en /usuarios/<uid>
      await _dbRef.child('usuarios').child(user.uid).set({
        'uid'       : user.uid,
        'nombre'    : _nameController.text.trim(),
        'correo'    : user.email,
        'creado_en' : ServerValue.timestamp,
        'activo'    : true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: AppColors.success, size: 20),
                SizedBox(width: 10),
                Text('¡Cuenta creada exitosamente!'),
              ],
            ),
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      _showSnackBar(_mapAuthError(e.code), isError: true);
    } catch (e) {
      _showSnackBar('Error inesperado: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapAuthError(String code) {
    switch (code) {
      case 'email-already-in-use'  : return 'Ya existe una cuenta con este correo.';
      case 'invalid-email'         : return 'El formato del correo no es válido.';
      case 'weak-password'         : return 'Contraseña muy débil (mínimo 6 caracteres).';
      case 'operation-not-allowed' : return 'El registro con correo no está habilitado.';
      default: return 'Error al registrarse ($code).';
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? AppColors.error : AppColors.success,
              size : 20,
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
      // AppBar con estilo dark
      appBar: AppBar(
        title: const Text('Crear cuenta'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.cardBorder),
        ),
      ),
      body: Stack(
        children: [
          // ── Fondo degradado ───────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.5, -0.8),
                radius: 0.9,
                colors: [Color(0xFF0D1F3C), AppColors.background],
              ),
            ),
          ),

          // ── Contenido ─────────────────────────────────────────────────────
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Encabezado ────────────────────────────────────────
                      const SizedBox(height: 8),
                      _CyanGlowIcon(icon: Icons.person_add_alt_1_rounded),
                      const SizedBox(height: 16),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [AppColors.cyan, AppColors.cyanSoft],
                        ).createShader(bounds),
                        child: const Text(
                          'Únete a Smart Eco-Step',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize  : 22,
                            fontWeight: FontWeight.bold,
                            color     : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Crea tu cuenta y empieza a monitorear',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 36),

                      // ── Campo: Nombre ─────────────────────────────────────
                      _buildField(
                        controller         : _nameController,
                        label              : 'Nombre completo',
                        icon               : Icons.badge_outlined,
                        textInputAction    : TextInputAction.next,
                        textCapitalization : TextCapitalization.words,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Ingresa tu nombre';
                          if (v.trim().length < 3) return 'Mínimo 3 caracteres';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // ── Campo: Correo ─────────────────────────────────────
                      _buildField(
                        controller     : _emailController,
                        label          : 'Correo electrónico',
                        icon           : Icons.alternate_email_rounded,
                        keyboardType   : TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Ingresa tu correo';
                          if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                            return 'Formato inválido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // ── Campo: Contraseña ─────────────────────────────────
                      _buildPasswordField(
                        controller     : _passwordController,
                        label          : 'Contraseña',
                        obscure        : _obscurePassword,
                        textInputAction: TextInputAction.next,
                        onToggle: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Ingresa una contraseña';
                          if (v.length < 6) return 'Mínimo 6 caracteres';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // ── Campo: Confirmar contraseña ───────────────────────
                      _buildPasswordField(
                        controller     : _confirmPasswordController,
                        label          : 'Confirmar contraseña',
                        obscure        : _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        onToggle: () => setState(() =>
                            _obscureConfirmPassword = !_obscureConfirmPassword),
                        onSubmit: (_) => _register(),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Confirma tu contraseña';
                          if (v != _passwordController.text) return 'Las contraseñas no coinciden';
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // ── Botón: Registrarse ────────────────────────────────
                      _NeonButtonFull(
                        label    : 'Crear cuenta',
                        isLoading: _isLoading,
                        onPressed: _isLoading ? null : _register,
                      ),
                      const SizedBox(height: 20),

                      // ── Volver al login ───────────────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('¿Ya tienes cuenta? ',
                              style: TextStyle(color: AppColors.textSecondary)),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Text(
                              'Inicia sesión',
                              style: TextStyle(
                                color     : AppColors.cyan,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers de campos ─────────────────────────────────────────────────────

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType       = TextInputType.text,
    TextInputAction textInputAction  = TextInputAction.next,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller        : controller,
      keyboardType      : keyboardType,
      textInputAction   : textInputAction,
      textCapitalization: textCapitalization,
      style             : const TextStyle(color: AppColors.textPrimary),
      decoration        : InputDecoration(
        labelText : label,
        prefixIcon: Icon(icon),
      ),
      validator: validator,
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool   obscure,
    required VoidCallback onToggle,
    TextInputAction textInputAction = TextInputAction.next,
    void Function(String)? onSubmit,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller      : controller,
      obscureText     : obscure,
      textInputAction : textInputAction,
      onFieldSubmitted: onSubmit,
      style           : const TextStyle(color: AppColors.textPrimary),
      decoration      : InputDecoration(
        labelText : label,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          icon: Icon(obscure
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined),
          onPressed: onToggle,
        ),
      ),
      validator: validator,
    );
  }
}

// ── Widgets locales ───────────────────────────────────────────────────────────

class _CyanGlowIcon extends StatelessWidget {
  const _CyanGlowIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width : 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.cardElevated,
          border: Border.all(color: AppColors.cyan.withAlpha(100), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: AppColors.cyan.withAlpha(50),
                blurRadius  : 20,
                spreadRadius: 2),
          ],
        ),
        child: Icon(icon, size: 38, color: AppColors.cyan),
      ),
    );
  }
}

class _NeonButtonFull extends StatelessWidget {
  const _NeonButtonFull({
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
