import 'package:cloud_firestore/cloud_firestore.dart';

class Review {
  const Review({
    required this.id,
    required this.bookingId,
    required this.technicianId,
    required this.customerId,
    required this.rating,
    required this.text,
    required this.createdAt,
    this.branchId,
    this.reviewerRole = 'customer',
    this.reviewerName = '',
    this.reviewerId,
  });

  final String id;
  final String bookingId;
  final String technicianId;
  final String customerId;
  final int rating;
  final String text;
  final DateTime createdAt;
  final String? branchId;
  final String reviewerRole;
  final String reviewerName;
  final String? reviewerId;

  factory Review.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return Review(
      id: doc.id,
      bookingId: data['bookingId'] as String? ?? '',
      technicianId: data['technicianId'] as String? ?? '',
      customerId: data['customerId'] as String? ?? '',
      rating: (data['rating'] as num?)?.toInt() ?? 0,
      text: data['text'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      branchId: data['branchId'] as String?,
      reviewerRole: data['reviewerRole'] as String? ?? 'customer',
      reviewerName: data['reviewerName'] as String? ?? '',
      reviewerId: data['reviewerId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'bookingId': bookingId,
        'technicianId': technicianId,
        'customerId': customerId,
        'rating': rating,
        'text': text,
        'createdAt': Timestamp.fromDate(createdAt),
        'branchId': branchId,
        'reviewerRole': reviewerRole,
        'reviewerName': reviewerName,
        'reviewerId': reviewerId,
      };
}
