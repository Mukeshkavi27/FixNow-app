import 'package:cloud_firestore/cloud_firestore.dart';

class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.actorId,
    required this.actorRole,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.summary,
    required this.createdAt,
    this.branchId,
  });

  final String id;
  final String actorId;
  final String actorRole;
  final String action;
  final String targetType;
  final String targetId;
  final String summary;
  final DateTime createdAt;
  final String? branchId;

  factory AuditLogEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AuditLogEntry(
      id: doc.id,
      actorId: data['actorId'] as String? ?? '',
      actorRole: data['actorRole'] as String? ?? '',
      action: data['action'] as String? ?? '',
      targetType: data['targetType'] as String? ?? '',
      targetId: data['targetId'] as String? ?? '',
      summary: data['summary'] as String? ?? '',
      branchId: data['branchId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
