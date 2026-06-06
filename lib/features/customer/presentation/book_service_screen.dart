import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

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
  File? _image;
  bool _isSaving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _problem.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (image != null) setState(() => _image = File(image.path));
  }

  Future<Position?> _position() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
    return Geolocator.getCurrentPosition();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final user = ref.read(currentUserProvider).valueOrNull!;
      String? imageUrl;
      if (_image != null) {
        imageUrl = await ref.read(storageRepositoryProvider).uploadFile(
              file: _image!,
              folder: 'before_service',
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
              preferredTime: _time.format(context),
              status: BookingStatus.booked,
              createdAt: DateTime.now(),
              imageUrl: imageUrl,
              latitude: location?.latitude,
              longitude: location?.longitude,
            ),
          );
      if (!mounted) return;
      context.go('/booking/$id');
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.appliance)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone Number'),
              keyboardType: TextInputType.phone,
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address'),
              minLines: 2,
              maxLines: 4,
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _problem,
              decoration: const InputDecoration(labelText: 'Problem Description'),
              minLines: 3,
              maxLines: 5,
              validator: _required,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Preferred Date'),
              subtitle: Text(DateFormat.yMMMd().format(_date)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 60)),
                  initialDate: _date,
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Preferred Time'),
              subtitle: Text(_time.format(context)),
              trailing: const Icon(Icons.schedule),
              onTap: () async {
                final picked = await showTimePicker(context: context, initialTime: _time);
                if (picked != null) setState(() => _time = picked);
              },
            ),
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.photo_camera),
              label: Text(_image == null ? 'Upload Appliance Image' : 'Change Appliance Image'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving ? null : _submit,
              icon: const Icon(Icons.send),
              label: Text(_isSaving ? 'Submitting...' : 'Submit Booking'),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;
}
