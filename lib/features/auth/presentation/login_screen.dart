import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/resilient_asset_image.dart';
import '../../../core/branches/branch_info.dart';
import '../../../core/branches/branch_repository.dart';
import '../../../core/branches/branch_resolver.dart';
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
  bool _isTechnicianRequest = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _selectedBranchId;

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
        if (_isTechnicianRequest) {
          final branches = ref.read(branchesProvider).valueOrNull ??
              BranchInfo.fallbackBranches;
          final branch =
              branches.where((item) => item.id == _selectedBranchId).isEmpty
                  ? null
                  : branches.firstWhere((item) => item.id == _selectedBranchId);
          if (branch == null) {
            throw StateError('Select the technician branch.');
          }
          final position = await _position();
          await repo.createTechnicianRequest(
            name: _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            phone: _phone.text.trim(),
            branchId: branch.id,
            branchName: branch.name,
            requestLatitude: position?.latitude,
            requestLongitude: position?.longitude,
          );
        } else {
          await repo.createUser(
            name: _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            phone: _phone.text.trim(),
          );
        }
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

  Future<Position?> _position() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  Future<void> _suggestBranch() async {
    final position = await _position();
    final branches = ref.read(branchesProvider).valueOrNull ?? const [];
    if (position == null || branches.isEmpty) return;
    final resolution = BranchResolver.resolve(
      branches: branches,
      latitude: position.latitude,
      longitude: position.longitude,
    );
    if (!mounted) return;
    setState(() => _selectedBranchId = resolution.branch.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Suggested branch: ${resolution.branch.name}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shouldLoadBranches = _isRegister && _isTechnicianRequest;
    final branchesAsync = shouldLoadBranches
        ? ref.watch(branchesProvider)
        : const AsyncValue<List<BranchInfo>>.data([]);
    final List<BranchInfo> branches =
        branchesAsync.valueOrNull ?? BranchInfo.fallbackBranches;
    final size = MediaQuery.sizeOf(context);
    final screenHeight = size.height;
    final screenWidth = size.width;

    final isSmall = screenHeight < 680;
    final isWide = screenWidth > 600;
    final isMobile = !isWide;

    final logoSize = isMobile ? 52.0 : (isSmall ? 72.0 : 88.0);
    final titleFontSize = isMobile ? 26.0 : (isSmall ? 26.0 : 32.0);
    final formHPad = isWide ? 32.0 : 18.0;
    final fieldGap = isMobile || isSmall ? 10.0 : 14.0;
    final panelPad = isMobile ? 18.0 : (isSmall ? 22.0 : 28.0);
    final panelRadius = isMobile ? 22.0 : 28.0;
    final panelOpacity = isWide ? 0.34 : 0.24;
    final imageLightenOpacity = isWide ? 0.08 : 0.18;
    final imageTintOpacity = isWide ? 0.22 : 0.08;

    Widget formPanel = ClipRRect(
      borderRadius: BorderRadius.circular(panelRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: isMobile ? 10 : 18,
          sigmaY: isMobile ? 10 : 18,
        ),
        child: Container(
          padding: EdgeInsets.all(panelPad),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: panelOpacity),
            borderRadius: BorderRadius.circular(panelRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: isMobile ? 0.42 : 0.62),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(
                  alpha: isMobile ? 0.06 : 0.1,
                ),
                blurRadius: isMobile ? 16 : 24,
                offset: Offset(0, isMobile ? 8 : 12),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: logoSize,
                    height: logoSize,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: isMobile ? 0.62 : 0.76,
                      ),
                      borderRadius: BorderRadius.circular(isMobile ? 16 : 22),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          blurRadius: isMobile ? 14 : 24,
                          offset: Offset(0, isMobile ? 7 : 12),
                        ),
                      ],
                    ),
                    child: const ResilientAssetImage(
                      assetName: 'assets/images/fixnow_logo.png',
                      fit: BoxFit.contain,
                      fallbackIcon: Icons.home_repair_service_outlined,
                      fallbackIconSize: 30,
                    ),
                  ),
                ),
                SizedBox(height: isMobile ? 10 : (isSmall ? 14 : 20)),
                Text(
                  'FixNow',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isRegister
                      ? (_isTechnicianRequest
                          ? 'Join your branch as a verified service technician'
                          : 'Create your appliance service booking account')
                      : 'Trusted appliance repair and service booking',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: isMobile ? 13 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: isMobile ? 16 : (isSmall ? 18 : 26)),
                if (_isRegister && _isTechnicianRequest) ...[
                  if (branchesAsync.hasError)
                    Padding(
                      padding: EdgeInsets.only(bottom: fieldGap),
                      child: Text(
                        'Branch list could not be loaded right now. Customer login still works, but technician signup needs an approved service branch.',
                        style: const TextStyle(
                          color: Color(0xFFD95C2A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else if (!branchesAsync.isLoading && branches.isEmpty)
                    Padding(
                      padding: EdgeInsets.only(bottom: fieldGap),
                      child: const Text(
                        'No service branches are available yet. Ask admin to create a branch before technician signup.',
                        style: TextStyle(
                          color: Color(0xFFD95C2A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
                Text(
                  _isRegister ? 'Sign up' : 'Sign in',
                  style: TextStyle(
                    fontSize: isMobile || isSmall ? 18 : 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: isMobile ? 12 : (isSmall ? 14 : 20)),
                if (_isRegister) ...[
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.52),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _RegisterModeChip(
                            label: 'Customer',
                            selected: !_isTechnicianRequest,
                            onTap: () => setState(() {
                              _isTechnicianRequest = false;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _RegisterModeChip(
                            label: 'Technician',
                            selected: _isTechnicianRequest,
                            onTap: () => setState(() {
                              _isTechnicianRequest = true;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: fieldGap),
                  _UCTextField(
                    controller: _name,
                    label: 'Full name',
                    prefixIcon: Icons.person_outline,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Enter name' : null,
                  ),
                  SizedBox(height: fieldGap),
                  _UCTextField(
                    controller: _phone,
                    label: 'Phone number',
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (v) => v == null || v.trim().length < 8
                        ? 'Enter phone number'
                        : null,
                  ),
                  SizedBox(height: fieldGap),
                  if (_isTechnicianRequest) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _selectedBranchId,
                      decoration: const InputDecoration(
                        labelText: 'Requested branch',
                        prefixIcon: Icon(Icons.account_tree_outlined),
                      ),
                      items: branches
                          .map(
                            (branch) => DropdownMenuItem(
                              value: branch.id,
                              child: Text(branch.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedBranchId = value),
                      disabledHint: Text(
                        branchesAsync.isLoading
                            ? 'Loading branches...'
                            : 'No branches available',
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Choose a branch'
                          : null,
                    ),
                    SizedBox(height: fieldGap),
                    OutlinedButton.icon(
                      onPressed: _isLoading || branches.isEmpty
                          ? null
                          : _suggestBranch,
                      icon: const Icon(Icons.my_location_outlined),
                      label: const Text('Suggest nearest branch'),
                    ),
                    SizedBox(height: fieldGap),
                    const Text(
                      'Technician access stays pending until the selected branch admin verifies and approves the request.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: fieldGap),
                  ] else ...[
                    const Text(
                      'Customer accounts can book services instantly. Technician accounts need branch admin approval.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: fieldGap),
                  ],
                ],
                _UCTextField(
                  controller: _email,
                  label: 'Email address',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v == null || !v.contains('@')
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
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (v) =>
                      v == null || v.length < 6 ? 'Minimum 6 characters' : null,
                ),
                SizedBox(height: isMobile ? 14 : (isSmall ? 16 : 24)),
                SizedBox(
                  height: isMobile || isSmall ? 46 : 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppTheme.accent.withValues(alpha: 0.55),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
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
                            ? (_isTechnicianRequest
                                ? 'Request Technician Access'
                                : 'Create Service Account')
                            : 'Sign In'),
                  ),
                ),
                SizedBox(height: isMobile ? 12 : 16),
                Center(
                  child: GestureDetector(
                    onTap: _isLoading
                        ? null
                        : () => setState(() => _isRegister = !_isRegister),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 13),
                        children: [
                          TextSpan(
                            text: _isRegister
                                ? 'Already have an account? '
                                : 'New to FixNow? ',
                            style:
                                const TextStyle(color: AppTheme.textSecondary),
                          ),
                          TextSpan(
                            text: _isRegister ? 'Sign in' : 'Create account',
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w800,
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
      ),
    );

    formPanel = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: isMobile ? 340 : 480),
      child: formPanel,
    );

    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ResilientAssetImage(
            assetName: 'assets/images/fix_now_general.png',
            fit: BoxFit.cover,
            alignment: isWide ? Alignment.center : Alignment.centerRight,
            color: Colors.white.withValues(alpha: imageLightenOpacity),
            colorBlendMode: BlendMode.screen,
            fallbackIcon: Icons.build_circle_outlined,
            fallbackIconSize: 64,
            fallbackBackgroundColor: const Color(0xFFEAF1FF),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primary.withValues(alpha: imageTintOpacity),
                  Colors.white.withValues(alpha: isWide ? 0.08 : 0.24),
                  AppTheme.accent.withValues(alpha: isWide ? 0.18 : 0.1),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: isMobile ? Alignment.bottomCenter : Alignment.center,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: formHPad,
                  vertical: isMobile ? 18 : (isSmall ? 18 : 28),
                ),
                child: formPanel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterModeChip extends StatelessWidget {
  const _RegisterModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
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
        fillColor: Colors.white.withValues(alpha: 0.7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.58),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.58),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade400),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
