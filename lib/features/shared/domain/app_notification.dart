import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.isRead,
    this.bookingId,
  });

  final String id;
  final String userId;
  final String title;
  final String body;
  final String type;
  final DateTime createdAt;
  final bool isRead;
  final String? bookingId;

  factory AppNotification.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return AppNotification(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      title: data['title'] as String? ?? 'Notification',
      body: data['body'] as String? ?? '',
      type: data['type'] as String? ?? 'general',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] as bool? ?? false,
      bookingId: data['bookingId'] as String?,
    );
  }
}
