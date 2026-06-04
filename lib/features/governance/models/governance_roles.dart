import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Defines the 4 leadership roles available in Voice of Diaspora governance.
class GovernanceRoles {
  static const String president = 'president';
  static const String treasurer = 'treasurer';
  static const String secretary = 'secretary';
  static const String councilMember = 'council_member';

  static const List<String> all = [
    president,
    treasurer,
    secretary,
    councilMember,
  ];

  static String displayName(String role) {
    switch (role) {
      case president:
        return 'President';
      case treasurer:
        return 'Treasurer';
      case secretary:
        return 'Secretary';
      case councilMember:
        return 'Council Member';
      default:
        return role;
    }
  }

  static String emoji(String role) {
    switch (role) {
      case president:
        return '🏛️';
      case treasurer:
        return '💰';
      case secretary:
        return '📝';
      case councilMember:
        return '👥';
      default:
        return '🗳️';
    }
  }

  static IconData icon(String role) {
    switch (role) {
      case president:
        return LucideIcons.landmark;
      case treasurer:
        return LucideIcons.wallet;
      case secretary:
        return LucideIcons.clipboardList;
      case councilMember:
        return LucideIcons.users;
      default:
        return LucideIcons.vote;
    }
  }

  static String description(String role) {
    switch (role) {
      case president:
        return 'Leads the community council and represents the community externally.';
      case treasurer:
        return 'Manages community treasury and financial operations.';
      case secretary:
        return 'Maintains community records and facilitates communication.';
      case councilMember:
        return 'Serves on the community council and participates in governance decisions.';
      default:
        return '';
    }
  }
}

/// Vote verdicts for Yay/Nay/Abstain voting system.
class VoteVerdict {
  static const String yay = 'yay';
  static const String nay = 'nay';
  static const String abstain = 'abstain';

  static const List<String> all = [yay, nay, abstain];
}

/// Vote summary for a candidate.
class VoteSummary {
  final String candidateId;
  final String role;
  final int yayCount;
  final int nayCount;
  final int abstainCount;

  VoteSummary({
    required this.candidateId,
    required this.role,
    this.yayCount = 0,
    this.nayCount = 0,
    this.abstainCount = 0,
  });

  int get totalVotes => yayCount + nayCount + abstainCount;
  int get decisiveVotes => yayCount + nayCount; // Exclude abstain from ratio
  double get favorableRate =>
      decisiveVotes > 0 ? yayCount / decisiveVotes : 0.0;
  bool get isWinning => favorableRate > 0.5 && decisiveVotes > 0;
  bool get shouldBeVotedOut => decisiveVotes > 0 && favorableRate < 0.5;
}
