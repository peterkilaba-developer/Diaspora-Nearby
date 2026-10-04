import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Leadership seats on a corridor Chamber of Commerce.
/// The Chamber of Commerce is managed and governed by the elected Home & Host Country Community Councils,
/// who hire and appoint two dedicated on-the-ground professional Trade Representatives:
///  - Host Trade Rep (Located in host country > 1 year)
///  - Home Trade Rep (Located in home country > 1 year)
class ChamberRoles {
  static const String hostTradeRep = 'host_trade_rep';
  static const String homeTradeRep = 'home_trade_rep';

  // Legacy/executive seats for backward compatibility
  static const String president = 'president';
  static const String vicePresident = 'vice_president';
  static const String treasurer = 'treasurer';
  static const String secretary = 'secretary';

  /// Primary operational seats on a bilateral chamber
  static const List<String> all = [hostTradeRep, homeTradeRep];

  /// Roles that may only be held by a candidate residing in the chamber's HOME country (> 1 yr).
  static const Set<String> homePinned = {homeTradeRep};

  /// Roles that may only be held by a candidate residing in the chamber's HOST country (> 1 yr).
  static const Set<String> hostPinned = {hostTradeRep};

  /// Single-occupant roles.
  static const Set<String> singleOccupant = {
    hostTradeRep,
    homeTradeRep,
    president,
    vicePresident,
    treasurer,
    secretary,
  };

  static bool isValid(String role) =>
      role == hostTradeRep ||
      role == homeTradeRep ||
      role == president ||
      role == vicePresident ||
      role == treasurer ||
      role == secretary;

  static String displayName(String role) {
    switch (role) {
      case hostTradeRep:
        return 'Host Trade Rep';
      case homeTradeRep:
        return 'Home Trade Rep';
      case president:
        return 'President';
      case vicePresident:
        return 'Vice President';
      case treasurer:
        return 'Treasurer';
      case secretary:
        return 'Secretary';
      default:
        return role;
    }
  }

  static String description(String role) {
    switch (role) {
      case hostTradeRep:
        return 'Appointed by Host Country Community Council. On-the-ground trade & business development representative located in the host country (lived there 1+ yr).';
      case homeTradeRep:
        return 'Appointed by Home Country Community Council. On-the-ground trade & logistics representative located in the home country (lived there 1+ yr).';
      case president:
        return 'Leads the chamber and represents the corridor externally.';
      case vicePresident:
        return 'Supports the President and facilitates bilateral relations.';
      case treasurer:
        return 'Stewards chamber finances and economic activity.';
      case secretary:
        return 'Maintains records, documentation, and chamber communications.';
      default:
        return '';
    }
  }

  static IconData icon(String role) {
    switch (role) {
      case hostTradeRep:
        return LucideIcons.mapPin;
      case homeTradeRep:
        return LucideIcons.home;
      case president:
        return LucideIcons.crown;
      case vicePresident:
        return LucideIcons.userCheck;
      case treasurer:
        return LucideIcons.wallet;
      case secretary:
        return LucideIcons.clipboardList;
      default:
        return LucideIcons.briefcase;
    }
  }
}
