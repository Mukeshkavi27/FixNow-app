import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/resilient_asset_image.dart';
import '../../../core/branches/branch_info.dart';
import '../../../core/branches/branch_repository.dart';
import '../../../core/branches/branch_resolver.dart';
import '../../../core/enums/booking_status.dart';
import '../../../core/maps/google_static_map.dart';
import '../../../core/services/reverse_geocoding_service.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/data/auth_repository.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';
import '../../shared/data/storage_repository.dart';

class BookServiceScreen extends ConsumerStatefulWidget {
  const BookServiceScreen({required this.appliance, super.key});

  final String appliance;

  @override
  ConsumerState<BookServiceScreen> createState() => _BookServiceScreenState();
}

class _BookServiceScreenState extends ConsumerState<BookServiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _problem = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  XFile? _image;
  bool _isSaving = false;
  bool _isLocating = false;
  bool _isFindingAddressPin = false;
  bool _profileLoaded = false;
  Position? _detectedPosition;
  bool _addressPinIsApproximate = false;
  _ConfirmedServiceLocation? _confirmedLocation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_profileLoaded) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    _name.text = user.name;
    _phone.text = user.phone;
    if ((user.lastServiceAddress ?? '').isNotEmpty) {
      _address.text = user.lastServiceAddress!;
      if (user.lastServiceLatitude != null &&
          user.lastServiceLongitude != null) {
        _detectedPosition = _storedPosition(
          latitude: user.lastServiceLatitude!,
          longitude: user.lastServiceLongitude!,
        );
        _addressPinIsApproximate = false;
      }
    }
    _profileLoaded = true;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _problem.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (image != null) setState(() => _image = image);
  }

  Future<Position?> _position({bool reportFailure = false}) async {
    try {
      if (!kIsWeb) {
        final enabled = await Geolocator.isLocationServiceEnabled();
        if (!enabled) {
          if (reportFailure) {
            throw StateError('Turn on device location services and try again.');
          }
          return null;
        }
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        if (reportFailure) {
          throw StateError('Allow location permission to use current location.');
        }
        return null;
      }
      if (permission == LocationPermission.deniedForever) {
        if (reportFailure) {
          throw StateError(
            'Location is blocked. Enable it from browser or app settings.',
          );
        }
        return null;
      }
      return Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Location timed out'),
      );
    } on TimeoutException {
      Position? lastKnown;
      try {
        lastKnown = await Geolocator.getLastKnownPosition();
      } catch (_) {
        lastKnown = null;
      }
      if (lastKnown != null) return lastKnown;
      if (reportFailure) {
        throw StateError('Location request timed out. Please try again.');
      }
      return null;
    } catch (_) {
      if (reportFailure) rethrow;
      return null;
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final position = await _position(reportFailure: true);
      if (!mounted) return;
      if (position == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Could not access live location. Enter address manually.'),
          ),
        );
        return;
      }
      String? resolvedAddress;
      try {
        final result = await ref.read(reverseGeocodingServiceProvider).reverse(
              latitude: position.latitude,
              longitude: position.longitude,
            );
        resolvedAddress = result?.address;
      } catch (_) {
        resolvedAddress = null;
      }
      if (!mounted) return;
      setState(() {
        _detectedPosition = position;
        _addressPinIsApproximate = false;
        _address.text = resolvedAddress?.trim().isNotEmpty == true
            ? resolvedAddress!.trim()
            : 'Current location pin selected';
      });
      await _openLocationPicker(
        initial: position,
        initialQuery: resolvedAddress ?? _address.text.trim(),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _useSavedAddress(AppUser user) {
    final address = user.lastServiceAddress;
    if (address == null || address.trim().isEmpty) return;
    setState(() {
      _address.text = address.trim();
      if (user.lastServiceLatitude != null &&
          user.lastServiceLongitude != null) {
        _detectedPosition = _storedPosition(
          latitude: user.lastServiceLatitude!,
          longitude: user.lastServiceLongitude!,
        );
        _addressPinIsApproximate = false;
        _confirmedLocation = null;
      }
    });
  }

  Future<Position?> _approximateAddressPosition(String address) async {
    if (address.trim().isEmpty) return null;
    try {
      final result =
          await ref.read(addressGeocodingServiceProvider).search(address);
      if (result == null) return null;
      return _storedPosition(
        latitude: result.latitude,
        longitude: result.longitude,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _findAddressPin() async {
    final address = _address.text.trim();
    if (address.isEmpty) {
      _formKey.currentState?.validate();
      return;
    }
    setState(() => _isFindingAddressPin = true);
    try {
      final position =
          await _approximateAddressPosition(address) ?? _detectedPosition;
      if (!mounted) return;
      if (position == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No matching address found. Try area or landmark, or use current location.',
            ),
          ),
        );
        return;
      }
      await _openLocationPicker(initial: position, initialQuery: address);
    } finally {
      if (mounted) setState(() => _isFindingAddressPin = false);
    }
  }

  Future<void> _adjustPin() async {
    final initial = _detectedPosition ??
        await _approximateAddressPosition(_address.text.trim());
    if (!mounted) return;
    if (initial == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Find the address first or use current location before adjusting the pin.',
          ),
        ),
      );
      return;
    }
    await _openLocationPicker(initial: initial, initialQuery: _address.text);
  }

  Future<void> _openLocationPicker({
    required Position initial,
    required String initialQuery,
  }) async {
    final selected = await showModalBottomSheet<_ConfirmedServiceLocation>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _PinPickerSheet(
        initial: initial,
        initialQuery: initialQuery,
        branches: ref.read(branchesProvider).valueOrNull ??
            BranchInfo.fallbackBranches,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _detectedPosition = _storedPosition(
        latitude: selected.latitude,
        longitude: selected.longitude,
      );
      _confirmedLocation = selected;
      _address.text = selected.displayAddress;
      _addressPinIsApproximate = false;
    });
    _formKey.currentState?.validate();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    final branches =
        ref.read(branchesProvider).valueOrNull ?? BranchInfo.fallbackBranches;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in before booking.')),
      );
      return;
    }
    if (_confirmedLocation == null ||
        _confirmedLocation!.serviceArea.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please confirm the service location on the map.'),
        ),
      );
      return;
    }

    final preferredTime = _time.format(context);
    setState(() => _isSaving = true);
    try {
      String? imageUrl;
      if (_image != null) {
        try {
          imageUrl = await ref.read(storageRepositoryProvider).uploadXFile(
                file: _image!,
                folder: 'customer_uploads/${user.uid}',
                fileName: '${const Uuid().v4()}.jpg',
              );
        } catch (_) {
          imageUrl = null;
        }
      }
      final confirmed = _confirmedLocation!;
      final branchResolution = BranchResolver.resolve(
        branches: branches,
        address: confirmed.displayAddress,
        latitude: confirmed.latitude,
        longitude: confirmed.longitude,
      );
      final id = await ref.read(bookingRepositoryProvider).createBooking(
            Booking(
              id: '',
              customerId: user.uid,
              customerName: _name.text.trim(),
              phone: _phone.text.trim(),
              address: confirmed.displayAddress,
              applianceType: widget.appliance,
              problemDescription: _problem.text.trim(),
              preferredDate: _date,
              preferredTime: preferredTime,
              status: BookingStatus.booked,
              createdAt: DateTime.now(),
              imageUrl: imageUrl,
              branchId: branchResolution.branch.id,
              branchName: branchResolution.branch.name,
              latitude: confirmed.latitude,
              longitude: confirmed.longitude,
              placeId: confirmed.placeId,
              pincode: confirmed.pincode,
              city: confirmed.city,
              stateName: confirmed.state,
              serviceArea: confirmed.serviceArea,
              landmark: confirmed.landmark,
            ),
          );
      try {
        await ref.read(authRepositoryProvider).updateUserBranch(
              uid: user.uid,
              branchId: branchResolution.branch.id,
              branchName: branchResolution.branch.name,
            );
        await ref.read(authRepositoryProvider).updateLastServiceLocation(
              uid: user.uid,
              address: confirmed.displayAddress,
              latitude: confirmed.latitude,
              longitude: confirmed.longitude,
            );
      } catch (_) {
        // Profile updates are conveniences; booking creation already succeeded.
      }
      if (!mounted) return;
      context.go('/booking/$id/confirmed');
    } catch (error) {
      if (mounted) {
        final message = error is FirebaseException
            ? 'Booking could not be saved: ${error.code}. ${error.message ?? ''}'
            : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted && _isSaving) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final branches =
        ref.watch(branchesProvider).valueOrNull ?? BranchInfo.fallbackBranches;
    if (!_profileLoaded && user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _profileLoaded) return;
        setState(() {
          _name.text = user.name;
          _phone.text = user.phone;
          if ((user.lastServiceAddress ?? '').isNotEmpty &&
              _address.text.trim().isEmpty) {
            _address.text = user.lastServiceAddress!;
            if (user.lastServiceLatitude != null &&
                user.lastServiceLongitude != null) {
              _detectedPosition = _storedPosition(
                latitude: user.lastServiceLatitude!,
                longitude: user.lastServiceLongitude!,
              );
            }
          }
          _profileLoaded = true;
        });
      });
    }

    final profile = _ServiceProfile.forAppliance(widget.appliance);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(profile.title)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final content = isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 340, child: _ServiceIntro(profile)),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _bookingForm(
                        profile: profile,
                        user: user,
                        branches: branches,
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _ServiceIntro(profile),
                    const SizedBox(height: 16),
                    _bookingForm(
                      profile: profile,
                      user: user,
                      branches: branches,
                    ),
                  ],
                );

          return SingleChildScrollView(
            padding: EdgeInsets.all(isWide ? 28 : 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: content,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _bookingForm({
    required _ServiceProfile profile,
    required AppUser? user,
    required List<BranchInfo> branches,
  }) {
    final savedAddress = user?.lastServiceAddress?.trim();
    final branchResolution = _address.text.trim().isEmpty
        ? null
        : BranchResolver.resolve(
            branches: branches,
            address: _address.text.trim(),
            latitude: _detectedPosition?.latitude,
            longitude: _detectedPosition?.longitude,
          );
    return Form(
      key: _formKey,
      child: _Panel(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 680;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Book your visit',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tell us what is happening so the technician arrives prepared.',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                if (twoColumns)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _nameField()),
                      const SizedBox(width: 12),
                      Expanded(child: _phoneField()),
                    ],
                  )
                else ...[
                  _nameField(),
                  const SizedBox(height: 12),
                  _phoneField(),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address,
                  onChanged: (_) => setState(() {
                    _detectedPosition = null;
                    _addressPinIsApproximate = false;
                    _confirmedLocation = null;
                  }),
                  decoration: const InputDecoration(
                    labelText: 'Service address',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  minLines: 2,
                  maxLines: 4,
                  validator: _required,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isLocating ? null : _useCurrentLocation,
                      icon: _isLocating
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_outlined),
                      label: Text(
                        _isLocating ? 'Detecting...' : 'Use current location',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _isFindingAddressPin ? null : _findAddressPin,
                      icon: _isFindingAddressPin
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.travel_explore_outlined),
                      label: Text(
                        _isFindingAddressPin
                            ? 'Finding...'
                            : 'Find address pin',
                      ),
                    ),
                    if (_detectedPosition != null)
                      FilledButton.tonalIcon(
                        onPressed: _adjustPin,
                        icon: const Icon(Icons.edit_location_alt_outlined),
                        label: const Text('Adjust pin'),
                      ),
                    if (user != null &&
                        savedAddress != null &&
                        savedAddress.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _useSavedAddress(user),
                        icon: const Icon(Icons.history_outlined),
                        label: const Text('Use saved address'),
                      ),
                  ],
                ),
                if (branchResolution != null) ...[
                  const SizedBox(height: 10),
                  _BranchPreview(
                    branchName: branchResolution.branch.name,
                    reason: branchResolution.reason,
                    hasLiveLocation: _detectedPosition != null,
                  ),
                ],
                if (_detectedPosition != null) ...[
                  const SizedBox(height: 10),
                  _AddressPinPreview(
                    position: _detectedPosition!,
                    approximate: _addressPinIsApproximate,
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _problem,
                  decoration: InputDecoration(
                    labelText: 'Problem description',
                    hintText: profile.problemHint,
                    prefixIcon: const Icon(Icons.description_outlined),
                  ),
                  minLines: 3,
                  maxLines: 5,
                  validator: _required,
                ),
                const SizedBox(height: 14),
                if (twoColumns)
                  Row(
                    children: [
                      Expanded(child: _DateTile(date: _date, onTap: _pickDate)),
                      const SizedBox(width: 12),
                      Expanded(child: _TimeTile(time: _time, onTap: _pickTime)),
                    ],
                  )
                else ...[
                  _DateTile(date: _date, onTap: _pickDate),
                  const SizedBox(height: 10),
                  _TimeTile(time: _time, onTap: _pickTime),
                ],
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(
                    _image == null
                        ? 'Upload appliance image'
                        : 'Selected: ${_image!.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _submit,
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isSaving ? 'Submitting...' : 'Submit booking'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _nameField() => TextFormField(
        controller: _name,
        decoration: const InputDecoration(
          labelText: 'Name',
          prefixIcon: Icon(Icons.person_outline),
        ),
        validator: _required,
      );

  Widget _phoneField() => TextFormField(
        controller: _phone,
        decoration: const InputDecoration(
          labelText: 'Phone number',
          prefixIcon: Icon(Icons.phone_outlined),
        ),
        keyboardType: TextInputType.phone,
        validator: _required,
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      initialDate: _date,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}

class _ServiceIntro extends StatelessWidget {
  const _ServiceIntro(this.profile);

  final _ServiceProfile profile;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: ResilientAssetImage(
                assetName: profile.assetName,
                fit: BoxFit.cover,
                fallbackIcon: Icons.home_repair_service_outlined,
                fallbackIconSize: 40,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            profile.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            profile.subtitle,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(icon: Icons.currency_rupee, label: profile.price),
              _InfoChip(icon: Icons.schedule, label: profile.duration),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Common issues',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...profile.commonIssues.map(
            (issue) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: AppTheme.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      issue,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PickTile(
      title: 'Preferred date',
      value: DateFormat.yMMMd().format(date),
      icon: Icons.calendar_month,
      onTap: onTap,
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.time, required this.onTap});

  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PickTile(
      title: 'Preferred time',
      value: time.format(context),
      icon: Icons.schedule,
      onTap: onTap,
    );
  }
}

class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchPreview extends StatelessWidget {
  const _BranchPreview({
    required this.branchName,
    required this.reason,
    required this.hasLiveLocation,
  });

  final String branchName;
  final String reason;
  final bool hasLiveLocation;

  @override
  Widget build(BuildContext context) {
    final label = switch (reason) {
      'matched_branch_by_address' => 'Matched from address',
      'nearest_branch_by_location' => 'Nearest to live location',
      _ => hasLiveLocation
          ? 'Selected from live location'
          : 'Default service branch',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_tree_outlined, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  branchName,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
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

class _AddressPinPreview extends StatelessWidget {
  const _AddressPinPreview({
    required this.position,
    required this.approximate,
  });

  final Position position;
  final bool approximate;

  @override
  Widget build(BuildContext context) {
    final point = GoogleMapPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      label: 'H',
      color: approximate ? const Color(0xFFF08C00) : AppTheme.accent,
      icon: approximate ? Icons.location_searching : Icons.home_outlined,
    );
    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: approximate
              ? const Color(0xFFFFD8A8)
              : AppTheme.accent.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InAppLiveMap(
            points: [point],
            zoom: 15,
            badge: approximate ? 'Approximate pin' : 'Exact pin',
          ),
          Positioned(
            left: 10,
            top: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      approximate
                          ? Icons.info_outline
                          : Icons.check_circle_outline,
                      color: approximate
                          ? const Color(0xFFF08C00)
                          : AppTheme.accent,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      approximate
                          ? 'Approximate address pin'
                          : 'Exact current location pin',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
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
    );
  }
}

class _ConfirmedServiceLocation {
  const _ConfirmedServiceLocation({
    required this.latitude,
    required this.longitude,
    required this.displayAddress,
    required this.serviceArea,
    this.placeId,
    this.pincode,
    this.city,
    this.state,
    this.landmark,
  });

  final double latitude;
  final double longitude;
  final String displayAddress;
  final String serviceArea;
  final String? placeId;
  final String? pincode;
  final String? city;
  final String? state;
  final String? landmark;
}

class _PinPickerSheet extends ConsumerStatefulWidget {
  const _PinPickerSheet({
    required this.initial,
    required this.initialQuery,
    required this.branches,
  });

  final Position initial;
  final String initialQuery;
  final List<BranchInfo> branches;

  @override
  ConsumerState<_PinPickerSheet> createState() => _PinPickerSheetState();
}

class _PinPickerSheetState extends ConsumerState<_PinPickerSheet> {
  final _search = TextEditingController();
  final _mapController = MapController();
  Timer? _debounce;
  late LatLng _selected = LatLng(
    widget.initial.latitude,
    widget.initial.longitude,
  );
  AddressGeocodingResult? _address;
  List<AddressSearchSuggestion> _suggestions = const [];
  final _suggestionCache = <String, List<AddressSearchSuggestion>>{};
  bool _searching = false;
  bool _resolving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _search.text = widget.initialQuery;
    _reverseSelected();
    if (widget.initialQuery.trim().length >= 3) {
      _loadSuggestions(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _loadSuggestions(value);
    });
  }

  Future<void> _loadSuggestions(String value) async {
    final query = value.trim();
    if (query.length < 3) {
      if (mounted) setState(() => _suggestions = const []);
      return;
    }
    final cacheKey = query.toLowerCase();
    final cached = _suggestionCache[cacheKey];
    if (cached != null) {
      setState(() {
        _suggestions = cached;
        _message = cached.isEmpty
            ? 'No matching address found. Try area, landmark, or move the map manually.'
            : null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _message = null;
    });
    try {
      final suggestions =
          await ref.read(addressSearchServiceProvider).suggestions(query);
      if (!mounted) return;
      _suggestionCache[cacheKey] = suggestions;
      setState(() {
        _suggestions = suggestions;
        _message = suggestions.isEmpty
            ? 'No matching address found. Try area, landmark, or move the map manually.'
            : null;
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectSuggestion(AddressSearchSuggestion suggestion) async {
    setState(() {
      _resolving = true;
      _suggestions = const [];
      _message = null;
    });
    try {
      final result =
          await ref.read(addressSearchServiceProvider).resolve(suggestion);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _message = 'Could not open that result. Move the map manually.';
        });
        return;
      }
      final point = LatLng(result.latitude, result.longitude);
      _mapController.move(point, 16);
      setState(() {
        _selected = point;
        _address = result;
        _search.text = result.displayAddress;
      });
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _reverseSelected() async {
    setState(() => _resolving = true);
    try {
      final result = await ref.read(reverseGeocodingServiceProvider).reverse(
            latitude: _selected.latitude,
            longitude: _selected.longitude,
          );
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _message = 'Address lookup failed. Move the map or search nearby landmark.';
        });
        return;
      }
      final enriched =
          await ref.read(addressGeocodingServiceProvider).search(result.address);
      if (!mounted) return;
      setState(() {
        _address = enriched ??
            AddressGeocodingResult(
              latitude: _selected.latitude,
              longitude: _selected.longitude,
              formattedAddress: result.address,
              provider: result.provider,
            );
        _search.text = _address!.displayAddress;
      });
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  void _movePin(LatLng point) {
    setState(() => _selected = point);
    _reverseSelected();
  }

  _ConfirmedServiceLocation? _confirmedLocation() {
    final address = _address;
    if (address == null) return null;
    final serviceArea = address.serviceArea ??
        BranchResolver.resolve(
          branches: widget.branches,
          address: address.displayAddress,
          latitude: _selected.latitude,
          longitude: _selected.longitude,
        ).branch.name;
    if (serviceArea.trim().isEmpty) return null;
    return _ConfirmedServiceLocation(
      latitude: _selected.latitude,
      longitude: _selected.longitude,
      displayAddress: address.displayAddress,
      placeId: address.placeId,
      pincode: address.pincode,
      city: address.city,
      state: address.state,
      serviceArea: serviceArea,
      landmark: address.landmark,
    );
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _confirmedLocation();
    final address = _address;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.94,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Confirm service location',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selected,
                    initialZoom: 16,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.drag |
                          InteractiveFlag.pinchZoom |
                          InteractiveFlag.doubleTapZoom,
                    ),
                    onTap: (_, point) => _movePin(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.fixnow.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _selected,
                          width: 58,
                          height: 58,
                          child: const Icon(
                            Icons.location_pin,
                            color: AppTheme.accent,
                            size: 46,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  top: 14,
                  child: Column(
                    children: [
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        elevation: 4,
                        child: TextField(
                          controller: _search,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Search building, area, landmark',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searching || _resolving
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      if (_suggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          constraints: const BoxConstraints(maxHeight: 220),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _suggestions.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final suggestion = _suggestions[index];
                              return ListTile(
                                leading: const Icon(Icons.place_outlined),
                                title: Text(suggestion.title),
                                subtitle: Text(
                                  suggestion.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => _selectSuggestion(suggestion),
                              );
                            },
                          ),
                        ),
                      if (_message != null)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4E6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFFFD8A8),
                            ),
                          ),
                          child: Text(
                            _message!,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: _ConfirmAddressCard(
                    address: address,
                    serviceArea: confirmed?.serviceArea,
                    resolving: _resolving,
                    onConfirm: confirmed == null
                        ? null
                        : () => Navigator.pop(context, confirmed),
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

class _ConfirmAddressCard extends StatelessWidget {
  const _ConfirmAddressCard({
    required this.address,
    required this.serviceArea,
    required this.resolving,
    required this.onConfirm,
  });

  final AddressGeocodingResult? address;
  final String? serviceArea;
  final bool resolving;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final display = address?.displayAddress ?? 'Move the pin to your address';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Service Address',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              display,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                height: 1.35,
              ),
            ),
            if ((address?.landmark ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Near: ${address!.landmark}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if ((serviceArea ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Service area: $serviceArea',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: resolving ? null : onConfirm,
                icon: resolving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: const Text('Confirm Location'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

Position _storedPosition({
  required double latitude,
  required double longitude,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.now(),
    accuracy: 0,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

class _ServiceProfile {
  const _ServiceProfile({
    required this.title,
    required this.subtitle,
    required this.assetName,
    required this.price,
    required this.duration,
    required this.problemHint,
    required this.commonIssues,
  });

  final String title;
  final String subtitle;
  final String assetName;
  final String price;
  final String duration;
  final String problemHint;
  final List<String> commonIssues;

  static _ServiceProfile forAppliance(String appliance) {
    final name = appliance.toLowerCase();
    if (name.contains('air') || name.contains('ac repair')) {
      return const _ServiceProfile(
        title: 'Air Conditioner',
        subtitle:
            'Cooling, leakage and maintenance support for split and window AC units.',
        assetName: 'assets/images/ac.png',
        price: 'Starts Rs. 499',
        duration: '60-90 min',
        problemHint: 'Example: not cooling, water leakage, noise, servicing',
        commonIssues: [
          'Gas check and cooling diagnosis',
          'Water leakage fix',
          'Filter and coil cleaning'
        ],
      );
    }
    if (name.contains('refrigerator') || name.contains('fridge')) {
      return const _ServiceProfile(
        title: 'Refrigerator',
        subtitle:
            'Diagnosis for cooling problems, noises, frosting and compressor-related symptoms.',
        assetName: 'assets/images/refrigerator.png',
        price: 'Starts Rs. 399',
        duration: '45-75 min',
        problemHint: 'Example: not cooling, over freezing, water leakage',
        commonIssues: [
          'Cooling inspection',
          'Door seal and frost checks',
          'Noise and compressor diagnosis'
        ],
      );
    }
    if (name.contains('washing')) {
      return const _ServiceProfile(
        title: 'Washing Machine',
        subtitle:
            'Repair support for top-load, front-load and semi-automatic washing machines.',
        assetName: 'assets/images/washing_machine.png',
        price: 'Starts Rs. 449',
        duration: '45-90 min',
        problemHint:
            'Example: not spinning, drainage issue, vibration, error code',
        commonIssues: [
          'Drain and spin issues',
          'Water inlet problems',
          'Vibration and error-code diagnosis'
        ],
      );
    }
    if (name.contains('microwave')) {
      return const _ServiceProfile(
        title: 'Microwave',
        subtitle:
            'Inspection and repair for heating, turntable, panel and power issues.',
        assetName: 'assets/images/microwave.png',
        price: 'Starts Rs. 299',
        duration: '30-60 min',
        problemHint: 'Example: not heating, sparks, plate not rotating',
        commonIssues: [
          'Heating diagnosis',
          'Turntable and panel checks',
          'Power and fuse inspection'
        ],
      );
    }
    if (name.contains('purifier')) {
      return const _ServiceProfile(
        title: 'Water Purifier',
        subtitle:
            'RO/UV purifier service for filter replacement, leakage and water-flow issues.',
        assetName: 'assets/images/water_purifier.png',
        price: 'Starts Rs. 349',
        duration: '40-70 min',
        problemHint:
            'Example: low water flow, leakage, bad taste, filter change',
        commonIssues: [
          'Filter and membrane checks',
          'Leakage repair',
          'Water-flow and taste diagnosis'
        ],
      );
    }
    if (name.contains('television') || name.contains('tv')) {
      return const _ServiceProfile(
        title: 'Television',
        subtitle:
            'Screen, sound, power and connectivity diagnosis for LED and smart TVs.',
        assetName: 'assets/images/television.png',
        price: 'Starts Rs. 399',
        duration: '45-75 min',
        problemHint: 'Example: no display, no sound, lines on screen',
        commonIssues: [
          'Display and sound diagnosis',
          'Power issue checks',
          'Smart TV connectivity support'
        ],
      );
    }
    if (name.contains('fan')) {
      return const _ServiceProfile(
        title: 'Fan',
        subtitle:
            'Ceiling, table and exhaust fan service for noise, speed and wiring problems.',
        assetName: 'assets/images/fan.png',
        price: 'Starts Rs. 199',
        duration: '30-45 min',
        problemHint: 'Example: slow speed, noise, not starting',
        commonIssues: [
          'Speed and capacitor checks',
          'Noise reduction',
          'Wiring and regulator inspection'
        ],
      );
    }
    return const _ServiceProfile(
      title: 'Other Appliances',
      subtitle:
          'Tell us about the appliance and the issue so we can route the right technician.',
      assetName: 'assets/images/other_services.png',
      price: 'Starts Rs. 249',
      duration: '30-90 min',
      problemHint: 'Describe the appliance, model and issue',
      commonIssues: [
        'General inspection',
        'Repair feasibility check',
        'Estimate before repair'
      ],
    );
  }
}
