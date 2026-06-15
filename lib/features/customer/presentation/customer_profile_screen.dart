import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../../shared/data/storage_repository.dart';

class CustomerProfileScreen extends ConsumerStatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  ConsumerState<CustomerProfileScreen> createState() =>
      _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends ConsumerState<CustomerProfileScreen> {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  bool initialized = false;
  bool saving = false;
  XFile? selectedPhoto;
  Uint8List? selectedPhotoBytes;

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  void populate() {
    if (initialized) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    nameController.text = user.name;
    phoneController.text = user.phone;
    initialized = true;
  }

  Future<void> pickPhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1200,
    );
    if (photo != null) {
      final bytes = await photo.readAsBytes();
      if (mounted) {
        setState(() {
          selectedPhoto = photo;
          selectedPhotoBytes = bytes;
        });
      }
    }
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    setState(() => saving = true);
    try {
      String? photoUrl;
      if (selectedPhoto != null) {
        photoUrl = await ref.read(storageRepositoryProvider).uploadXFile(
              file: selectedPhoto!,
              folder: 'profile_photos/${user.uid}',
              fileName: 'profile.jpg',
            );
      }
      await ref.read(authRepositoryProvider).updateCustomerProfile(
            uid: user.uid,
            name: nameController.text,
            phone: phoneController.text,
            profilePhoto: photoUrl,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update profile: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    populate();

    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Profile is unavailable.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: AppTheme.primary,
                      foregroundImage: selectedPhotoBytes != null
                          ? MemoryImage(selectedPhotoBytes!)
                          : user.profilePhoto == null ||
                                  user.profilePhoto!.isEmpty
                              ? null
                              : NetworkImage(user.profilePhoto!)
                                  as ImageProvider,
                      child: selectedPhoto == null &&
                              (user.profilePhoto == null ||
                                  user.profilePhoto!.isEmpty)
                          ? Text(
                              _initials(user.name),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: IconButton.filled(
                        tooltip: 'Change profile photo',
                        onPressed: pickPhoto,
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Form(
                key: formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) =>
                          value == null || value.trim().length < 2
                              ? 'Enter your full name'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (value) => value == null ||
                              value.replaceAll(RegExp(r'\D'), '').length < 8
                          ? 'Enter a valid phone number'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: user.email,
                      enabled: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(saving ? 'Saving...' : 'Save changes'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Account',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              _AccountTile(
                icon: Icons.lock_reset,
                title: 'Reset password',
                subtitle: 'Receive a secure reset link by email',
                onTap: () async {
                  try {
                    await ref.read(authRepositoryProvider).sendPasswordReset();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Reset link sent to ${user.email}.'),
                      ),
                    );
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 10),
              _AccountTile(
                icon: Icons.logout,
                title: 'Sign out',
                subtitle: 'Sign out of this device',
                destructive: true,
                onTap: () async {
                  await ref.read(authRepositoryProvider).signOut();
                  if (context.mounted) context.go('/login');
                },
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
      ),
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.red : AppTheme.textPrimary;
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppTheme.divider),
      ),
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.chevron_right, color: color),
    );
  }
}
