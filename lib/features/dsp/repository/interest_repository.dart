import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/models/interest_registration.dart';

final interestRepositoryProvider = Provider<InterestRepository>((ref) {
  return InterestRepository(FirebaseFirestore.instance);
});

class InterestRepository {
  final FirebaseFirestore _firestore;

  InterestRepository(this._firestore);

  Future<void> registerInterest({
    required String userId,
    required String service,
    required String country,
  }) async {
    final registration = InterestRegistration(
      userId: userId,
      service: service,
      country: country,
      timestamp: DateTime.now(),
    );

    // Use a composite ID to prevent duplicates (one vote per service per user)
    // We store in a root collection 'interest_registrations' for easy querying
    await _firestore
        .collection('interest_registrations')
        .doc('${userId}_$service')
        .set(registration.toMap());
  }

  Future<bool> checkInterest({
    required String userId,
    required String service,
  }) async {
    final doc = await _firestore
        .collection('interest_registrations')
        .doc('${userId}_$service')
        .get();

    return doc.exists;
  }
}
