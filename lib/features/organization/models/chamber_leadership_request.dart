import 'package:cloud_firestore/cloud_firestore.dart';

/// A user-submitted request to be appointed to a chamber leadership seat.
///
/// Stored in the top-level `leadershipRequests` collection so admin queries
/// can fan out across all chambers without sub-collection enumeration.
///
/// Lifecycle:
///   1. User calls `OrganizationRepository.requestChamberLeadership(...)`
///      → doc written with `approved: false`, `status: 'pending'`.
///   2. Admin flips `approved: true` (via CLI, console, or future UI).
///   3. Cloud Function `onChamberLeadershipRequestApproved` triggers,
///      performs the actual appointment (writes `councilRoles`,
///      `adminTitles`, `admins` on the chamber org), and updates the
///      request to `status: 'approved'` with `decidedAt`/`decidedBy`.
///   4. To reject: admin sets `status: 'rejected'` (leaves `approved: false`).
class ChamberLeadershipRequest {
  /// Status: still awaiting an admin decision.
  static const String statusPending = 'pending';

  /// Status: admin flipped `approved: true`; the trigger function has
  /// also performed the appointment.
  static const String statusApproved = 'approved';

  /// Status: admin explicitly declined. Appointment was NOT made.
  static const String statusRejected = 'rejected';

  final String id;
  final String chamberId;
  final String userId;
  final String role;
  final String message; // Optional pitch from the requester.
  final String status; // pending | approved | rejected
  final bool approved; // The boolean an admin flips to true to grant.
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final String? decidedBy; // uid of the admin who decided.
  final String? decisionNote;

  const ChamberLeadershipRequest({
    required this.id,
    required this.chamberId,
    required this.userId,
    required this.role,
    this.message = '',
    this.status = statusPending,
    this.approved = false,
    this.createdAt,
    this.decidedAt,
    this.decidedBy,
    this.decisionNote,
  });

  factory ChamberLeadershipRequest.fromJson(
    String id,
    Map<String, dynamic> data,
  ) {
    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      return null;
    }

    return ChamberLeadershipRequest(
      id: id,
      chamberId: data['chamberId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      role: data['role'] as String? ?? '',
      message: data['message'] as String? ?? '',
      status: data['status'] as String? ?? statusPending,
      approved: data['approved'] as bool? ?? false,
      createdAt: parseTs(data['createdAt']),
      decidedAt: parseTs(data['decidedAt']),
      decidedBy: data['decidedBy'] as String?,
      decisionNote: data['decisionNote'] as String?,
    );
  }
}
