import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/enums/booking_status.dart';
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
  bool _profileLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_profileLoaded) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    _name.text = user.name;
    _phone.text = user.phone;
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
      return Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Location timed out'),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in before booking.')),
      );
      return;
    }

    final preferredTime = _time.format(context);
    setState(() => _isSaving = true);
    try {
      String? imageUrl;
      if (_image != null) {
        imageUrl = await ref.read(storageRepositoryProvider).uploadXFile(
              file: _image!,
              folder: 'customer_uploads/${user.uid}',
              fileName: '${const Uuid().v4()}.jpg',
            );
      }
      final location = await _position();
      final id = await ref.read(bookingRepositoryProvider).createBooking(
            Booking(
              id: '',
              customerId: user.uid,
              customerName: _name.text.trim(),
              phone: _phone.text.trim(),
              address: _address.text.trim(),
              applianceType: widget.appliance,
              problemDescription: _problem.text.trim(),
              preferredDate: _date,
              preferredTime: preferredTime,
              status: BookingStatus.booked,
              createdAt: DateTime.now(),
              imageUrl: imageUrl,
              latitude: location?.latitude,
              longitude: location?.longitude,
            ),
          );
      if (!mounted) return;
      context.go('/booking/$id/confirmed');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
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
    if (!_profileLoaded && user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _profileLoaded) return;
        setState(() {
          _name.text = user.name;
          _phone.text = user.phone;
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
                    Expanded(child: _bookingForm(profile: profile)),
                  ],
                )
              : Column(
                  children: [
                    _ServiceIntro(profile),
                    const SizedBox(height: 16),
                    _bookingForm(profile: profile),
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

  Widget _bookingForm({required _ServiceProfile profile}) {
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
                  decoration: const InputDecoration(
                    labelText: 'Service address',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  minLines: 2,
                  maxLines: 4,
                  validator: _required,
                ),
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
              child: Image.asset(profile.assetName, fit: BoxFit.cover),
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
