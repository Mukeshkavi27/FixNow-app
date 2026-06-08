import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/enums/user_role.dart';
import '../data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _isRegister = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  UserRole _role = UserRole.customer;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(authRepositoryProvider);
      if (_isRegister) {
        await repo.createUser(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          phone: _phone.text.trim(),
          role: _role,
        );
      } else {
        await repo.signIn(_email.text.trim(), _password.text);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final screenHeight = size.height;
    final screenWidth = size.width;

    // Responsive breakpoints
    final isSmall = screenHeight < 680;
    final isWide = screenWidth > 600;

    // Adaptive values
    final brandTopPad = isSmall ? 24.0 : (isWide ? 40.0 : 32.0);
    final brandBottomPad = isSmall ? 20.0 : (isWide ? 32.0 : 28.0);
    final logoSize = isSmall ? 44.0 : 52.0;
    final logoFontSize = isSmall ? 15.0 : 18.0;
    final titleFontSize = isSmall ? 26.0 : 32.0;
    final logoBottomGap = isSmall ? 12.0 : 20.0;
    final titleBottomGap = isSmall ? 2.0 : 4.0;
    final formHPad = isWide ? 32.0 : 24.0;
    final fieldGap = isSmall ? 10.0 : 14.0;
    final formTopGap = isSmall ? 4.0 : 8.0;

    // For wide screens (tablet/web), constrain & center the card
    Widget body = SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Brand section ──────────────────────────────
            Container(
              color: AppTheme.primary,
              padding: EdgeInsets.fromLTRB(formHPad, brandTopPad, formHPad, brandBottomPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: logoSize,
                    height: logoSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        'FN',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: logoFontSize,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: logoBottomGap),
                  Text(
                    'FixNow',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: titleBottomGap),
                  Text(
                    _isRegister
                        ? 'Create your account'
                        : 'Home services at your doorstep',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),

            // ── Form section ───────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(formHPad, 20, formHPad, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: formTopGap),
                    Text(
                      _isRegister ? 'Sign up' : 'Sign in',
                      style: TextStyle(
                        fontSize: isSmall ? 18 : 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: isSmall ? 14 : 20),

                    if (_isRegister) ...[
                      _UCTextField(
                        controller: _name,
                        label: 'Full name',
                        prefixIcon: Icons.person_outline,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter name'
                            : null,
                      ),
                      SizedBox(height: fieldGap),
                      _UCTextField(
                        controller: _phone,
                        label: 'Phone number',
                        prefixIcon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: (v) =>
                            v == null || v.trim().length < 8
                                ? 'Enter phone number'
                                : null,
                      ),
                      SizedBox(height: fieldGap),
                      // Role selector
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: Row(
                          children: UserRole.values
                              .map(
                                (role) => Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _role = role),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      margin: const EdgeInsets.all(4),
                                      padding: EdgeInsets.symmetric(
                                          vertical: isSmall ? 8 : 10),
                                      decoration: BoxDecoration(
                                        color: _role == role
                                            ? AppTheme.primary
                                            : Colors.transparent,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        role.name[0].toUpperCase() +
                                            role.name.substring(1),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _role == role
                                              ? Colors.white
                                              : AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      SizedBox(height: fieldGap),
                    ],

                    _UCTextField(
                      controller: _email,
                      label: 'Email address',
                      prefixIcon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) =>
                          v == null || !v.contains('@')
                              ? 'Enter a valid email'
                              : null,
                    ),
                    SizedBox(height: fieldGap),
                    _UCTextField(
                      controller: _password,
                      label: 'Password',
                      prefixIcon: Icons.lock_outline,
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppTheme.textHint,
                          size: 20,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      validator: (v) =>
                          v == null || v.length < 6
                              ? 'Minimum 6 characters'
                              : null,
                    ),

                    SizedBox(height: isSmall ? 16 : 24),

                    // Submit button
                    SizedBox(
                      height: isSmall ? 46 : 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(_isRegister
                                ? 'Create Account'
                                : 'Sign In'),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Toggle
                    Center(
                      child: GestureDetector(
                        onTap: _isLoading
                            ? null
                            : () => setState(
                                () => _isRegister = !_isRegister),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 13),
                            children: [
                              TextSpan(
                                text: _isRegister
                                    ? 'Already have an account? '
                                    : 'New to FixNow? ',
                                style: const TextStyle(
                                    color: AppTheme.textSecondary),
                              ),
                              TextSpan(
                                text: _isRegister
                                    ? 'Sign in'
                                    : 'Create account',
                                style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // On wide screens (tablet/web), center in a constrained card
    if (isWide) {
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            elevation: 4,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: body,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isWide ? AppTheme.background.withOpacity(0.92) : AppTheme.background,
      body: body,
    );
  }
}

class _UCTextField extends StatelessWidget {
  const _UCTextField({
    required this.controller,
    required this.label,
    required this.prefixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppTheme.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: AppTheme.textHint,
          fontSize: 13,
        ),
        prefixIcon: Icon(prefixIcon, size: 18, color: AppTheme.textHint),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade400),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
      ),
    );
  }
}