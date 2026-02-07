/// Defines all the unique IDs for trackable exploration actions.
class ExplorationAction {
  // More Screen
  static const String moreScreenAccount = 'more_screen_account';
  static const String moreScreenFeedback = 'more_screen_feedback';
  static const String moreScreenSettings = 'more_screen_settings';
  static const String moreScreenAbout = 'more_screen_about';
  static const String moreScreenPrivacy = 'more_screen_privacy';
  static const String moreScreenNotifications = 'more_screen_notifications';
  static const String moreScreenTrust = 'more_screen_trust';

  // Tab Bar
  static const String tabChats =
      'explore_tab_chats'; // Renamed to match existing usage or standard
  static const String tabNearby = 'explore_tab_nearby';
  static const String tabEvents = 'explore_tab_events';

  // Toggles
  static const String toggleViewNearby = 'action_toggle_view_nearby';
  static const String toggleViewEvents = 'action_toggle_view_events';
  static const String toggleViewCommunities = 'action_toggle_view_communities';
  static const String toggleViewRadio = 'action_toggle_view_radio';
  static const String toggleViewChats = 'action_toggle_view_chats';

  // FAB
  static const String fabInvite = 'action_invite_friends';

  // Profile
  static const String profileEdit = 'profile_edit';
  static const String profileShare = 'profile_share';

  // Profile - Quick Actions
  static const String profileInvite = 'action_profile_more_invite';
  static const String profileFeedback = 'action_profile_more_feedback';
  static const String profileEventsCreate = 'action_profile_more_events_create';
  static const String profileOrgs = 'action_profile_more_orgs';

  // Profile - Support
  static const String profileRateApp = 'action_profile_rate_app';
  static const String profileHelpCenter = 'action_profile_help_center';

  // Profile - App Info
  static const String profileThemeToggle = 'action_profile_theme_toggle';

  // Profile - Completion Rewards
  static const String profileSetupPhoto = 'profile_setup_photo';
  static const String profileSetupBio = 'profile_setup_bio';
  static const String profileSetupOccupation = 'profile_setup_occupation';
  static const String profileSetupProfession = 'profile_setup_profession';
  static const String profileSetupIndustry = 'profile_setup_industry';
  static const String profileSetupLanguages = 'profile_setup_languages';
  static const String profileSetupInterests = 'profile_setup_interests';
  static const String profileSetupServices = 'profile_setup_services';
  static const String profileSetupLookingFor = 'profile_setup_looking_for';
  static const String profileSetupAvailability = 'profile_setup_availability';
  static const String profileSetupMeetingPrefs = 'profile_setup_meeting_prefs';
  static const String profileSetupPastLocations =
      'profile_setup_past_locations';

  // DSP
  static const String walletView = 'wallet_view';

  // AppBar Shortcuts
  static const String appbarCommunity = 'action_appbar_community';
  static const String appbarRadio = 'action_appbar_radio';

  // Radio
  static const String radioPlay = 'action_radio_play';
  static const String radioFavorite = 'action_radio_favorite';

  // Events
  static const String eventInterest = 'action_event_interest';

  // Communities
  static const String communityViewMembers = 'action_community_members';
  static const String communityExpand = 'action_community_expand';

  // Economy Ecosystem Cards
  static const String economyCrypto = 'economy_crypto';
  static const String economyRemittances = 'economy_remittances';
  static const String economyBereavement = 'economy_bereavement';
  static const String economyAirline = 'economy_airline';
  static const String economyDfdi = 'economy_dfdi';

  static final List<String> allActions = [
    moreScreenAccount,
    moreScreenFeedback,
    moreScreenSettings,
    moreScreenAbout,
    moreScreenPrivacy,
    moreScreenNotifications,
    moreScreenTrust,
    tabChats,
    tabNearby,
    tabEvents,
    toggleViewNearby,
    toggleViewEvents,
    toggleViewCommunities,
    toggleViewRadio,
    toggleViewChats,
    fabInvite,
    profileEdit,
    profileShare,
    profileInvite,
    profileFeedback,
    profileEventsCreate,
    profileOrgs,
    profileRateApp,
    profileHelpCenter,
    profileThemeToggle,
    profileSetupPhoto,
    profileSetupBio,
    profileSetupOccupation,
    profileSetupProfession,
    profileSetupIndustry,
    profileSetupLanguages,
    profileSetupInterests,
    profileSetupServices,
    profileSetupLookingFor,
    profileSetupAvailability,
    profileSetupMeetingPrefs,
    profileSetupPastLocations,
    profileSetupPastLocations,
    walletView,
    economyCrypto,
    economyRemittances,
    economyBereavement,
    economyAirline,
    economyDfdi,
    appbarCommunity,
    appbarRadio,
    radioPlay,
    radioFavorite,
    eventInterest,
    communityViewMembers,
    communityExpand,
  ];
}

class ExplorationRegistry {
  static int get totalPossiblePoints => ExplorationAction.allActions.length;

  static int getEarnedPoints(List<String> exploredActions) {
    // Only count actions that are currently in our registry (handling deprecated IDs gracefully)
    return exploredActions
        .where((id) => ExplorationAction.allActions.contains(id))
        .length;
  }
}
