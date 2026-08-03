import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// The 6 leadership seats on a corridor Chamber of Commerce.
/// The Chamber of Commerce is run by the elected Community Council, who oversee and hire these chamber officers.
///
/// Shape is intentionally compatible with [GovernanceRoles] in
/// `lib/features/governance/models/governance_roles.dart` so that when
/// chambers move from system-appointed leadership to fully-elected
/// governance, the `councilRoles` map can be ported into a
/// [GovernanceUnit] without a data migration.
class ChamberRoles {
  static const String president = 'president';
  static const String vicePresident = 'vice_president';
  static const String treasurer = 'treasurer';
  static const String secretary = 'secretary';
  static const String homeTradeRep = 'home_trade_rep';
  static const String hostTradeRep = 'host_trade_rep';

  /// Canonical ordering used in UI lists.
  static const List<String> all = [
    president,
    vicePresident,
    treasurer,
    secretary,
    homeTradeRep,
    hostTradeRep,
  ];

  /// Roles that may only be held by a national of the chamber's HOME country.
  static const Set<String> homePinned = {homeTradeRep};

  /// Roles that may only be held by a national of (or resident in) the
  /// chamber's HOST country.
  static const Set<String> hostPinned = {hostTradeRep};

  /// Single-occupant roles. (All 6 chamber seats are single-occupant — there
  /// is no "council member" multi-seat tier like communities have.)
  static const Set<String> singleOccupant = {
    president,
    vicePresident,
    treasurer,
    secretary,
    homeTradeRep,
    hostTradeRep,
  };

  static bool isValid(String role) => all.contains(role);

  static String displayName(String role) {
    switch (role) {
      case president:
        return 'President';
      case vicePresident:
        return 'Vice President';
      case treasurer:
        return 'Treasurer';
      case secretary:
        return 'Secretary';
      case homeTradeRep:
        return 'Home Trade Rep';
      case hostTradeRep:
        return 'Host Trade Rep';
      default:
        return role;
    }
  }

  static String description(String role) {
    switch (role) {
      case president:
        return 'Leads the chamber, sets the agenda, and represents the corridor externally.';
      case vicePresident:
        return 'Supports the President. Held by the OPPOSITE nationality from the President to keep the council bilateral.';
      case treasurer:
        return 'Stewards chamber funds and reports finances. (Reserved — chambers do not yet hold treasuries.)';
      case secretary:
        return 'Maintains records, runs onboarding, and facilitates chamber comms.';
      case homeTradeRep:
        return 'Lived-experience representative for the home country. Speaks for home-country businesses and diaspora interests.';
      case hostTradeRep:
        return 'Lived-experience representative for the host country. Speaks for host-country businesses and native partners.';
      default:
        return '';
    }
  }

  static IconData icon(String role) {
    switch (role) {
      case president:
        return LucideIcons.crown;
      case vicePresident:
        return LucideIcons.userCheck;
      case treasurer:
        return LucideIcons.wallet;
      case secretary:
        return LucideIcons.clipboardList;
      case homeTradeRep:
        return LucideIcons.home;
      case hostTradeRep:
        return LucideIcons.mapPin;
      default:
        return LucideIcons.users;
    }
  }
}
