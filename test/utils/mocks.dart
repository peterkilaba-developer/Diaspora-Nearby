import 'package:mockito/annotations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';

@GenerateMocks([
  AuthRepository,
  ProfileRepository,
  CommunityRepository,
  PointsRepository,
  PointsService,
  TrustService,
  FirebaseFirestore,
  FirebaseAuth,
  WriteBatch,
  DocumentReference,
  CollectionReference,
  DocumentSnapshot,
  QuerySnapshot,
  QueryDocumentSnapshot,
])
void main() {}
