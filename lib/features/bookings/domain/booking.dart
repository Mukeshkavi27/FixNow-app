import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/enums/booking_status.dart';

class Booking {
  const Booking({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.address,
    required this.applianceType,
    required this.problemDescription,
    required this.preferredDate,
    required this.preferredTime,
    required this.status,
    required this.createdAt,
    this.imageUrl,
    this.technicianId,
    this.technicianName,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String customerId;
  final String customerName;
  final String phone;
  final String address;
  final String applianceType;
  final String problemDescription;
  final DateTime preferredDate;
  final String preferredTime;
  final BookingStatus status;
  final DateTime createdAt;
  final String? imageUrl;
  final String? technicianId;
  final String? technicianName;
  final double? latitude;
  final double? longitude;

  factory Booking.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Booking(
      id: doc.id,
      customerId: data['customerId'] as String? ?? '',
      customerName: data['customerName'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      address: data['address'] as String? ?? '',
      applianceType: data['applianceType'] as String? ?? '',
      problemDescription: data['problemDescription'] as String? ?? '',
      preferredDate: (data['preferredDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      preferredTime: data['preferredTime'] as String? ?? '',
      status: BookingStatus.fromString(data['status'] as String? ?? 'booked'),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      imageUrl: data['imageUrl'] as String?,
      technicianId: data['technicianId'] as String?,
      technicianName: data['technicianName'] as String?,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'customerId': customerId,
      'customerName': customerName,
      'phone': phone,
      'address': address,
      'applianceType': applianceType,
      'problemDescription': problemDescription,
      'preferredDate': Timestamp.fromDate(preferredDate),
      'preferredTime': preferredTime,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'imageUrl': imageUrl,
      'technicianId': technicianId,
      'technicianName': technicianName,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}
