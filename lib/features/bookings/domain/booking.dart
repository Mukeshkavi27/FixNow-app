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
    DateTime? updatedAt,
    this.imageUrl,
    this.technicianId,
    this.technicianName,
    this.branchId,
    this.branchName,
    this.latitude,
    this.longitude,
    this.holdReason,
    this.heldAt,
    this.servicePhotos = const [],
  }) : updatedAt = updatedAt ?? createdAt;

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
  final DateTime updatedAt;
  final String? imageUrl;
  final String? technicianId;
  final String? technicianName;
  final String? branchId;
  final String? branchName;
  final double? latitude;
  final double? longitude;
  final String? holdReason;
  final DateTime? heldAt;
  final List<ServicePhoto> servicePhotos;

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
      preferredDate:
          (data['preferredDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      preferredTime: data['preferredTime'] as String? ?? '',
      status: BookingStatus.fromString(data['status'] as String? ?? 'booked'),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      imageUrl: data['imageUrl'] as String?,
      technicianId: data['technicianId'] as String?,
      technicianName: data['technicianName'] as String?,
      branchId: data['branchId'] as String?,
      branchName: data['branchName'] as String?,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      holdReason: data['holdReason'] as String?,
      heldAt: (data['heldAt'] as Timestamp?)?.toDate(),
      servicePhotos: (data['servicePhotos'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ServicePhoto.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
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
      'servicePhotos': servicePhotos.map((photo) => photo.toJson()).toList(),
    };
    if (imageUrl != null && imageUrl!.isNotEmpty) data['imageUrl'] = imageUrl;
    if (technicianId != null && technicianId!.isNotEmpty) {
      data['technicianId'] = technicianId;
    }
    if (technicianName != null && technicianName!.isNotEmpty) {
      data['technicianName'] = technicianName;
    }
    if (branchId != null && branchId!.isNotEmpty) data['branchId'] = branchId;
    if (branchName != null && branchName!.isNotEmpty) {
      data['branchName'] = branchName;
    }
    if (latitude != null) data['latitude'] = latitude;
    if (longitude != null) data['longitude'] = longitude;
    if (holdReason != null && holdReason!.isNotEmpty) {
      data['holdReason'] = holdReason;
    }
    if (heldAt != null) data['heldAt'] = Timestamp.fromDate(heldAt!);
    return data;
  }
}

class ServicePhoto {
  const ServicePhoto({
    required this.stage,
    required this.url,
    required this.uploadedAt,
  });

  final String stage;
  final String url;
  final DateTime uploadedAt;

  factory ServicePhoto.fromJson(Map<String, dynamic> data) {
    return ServicePhoto(
      stage: data['stage'] as String? ?? '',
      url: data['url'] as String? ?? '',
      uploadedAt:
          (data['uploadedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'stage': stage,
        'url': url,
        'uploadedAt': Timestamp.fromDate(uploadedAt),
      };
}
