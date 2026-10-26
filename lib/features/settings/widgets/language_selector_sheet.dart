import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/core/data/countries.dart';
import 'package:diaspora_nearby/core/data/world_languages.dart';
import 'package:diaspora_nearby/core/localization/app_localizations.dart';
import 'package:diaspora_nearby/core/providers/locale_provider.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

Future<void> showLanguageSelectorSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (sheetContext) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: _LanguageSelectorSheetContent(),
        ),
      );
    },
  );
}

class _LanguageSelectorSheetContent extends ConsumerStatefulWidget {
  const _LanguageSelectorSheetContent();

  @override
  ConsumerState<_LanguageSelectorSheetContent> createState() =>
      _LanguageSelectorSheetContentState();
}

class _LanguageSelectorSheetContentState
    extends ConsumerState<_LanguageSelectorSheetContent> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _byCountryMode = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectLanguage(WorldLanguage lang) {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    ref.read(localeProvider.notifier).setLanguage(lang.code, uid: uid);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${lang.primaryFlag}  ${lang.nativeName} (${lang.name})'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCode = ref.watch(localeProvider);
    final profile = ref.watch(userProfileProvider).value;

    // Collect recommended languages from user's Home & Host countries
    final Set<String> userCountryCodes = {
      if (profile?.homeCountryCode != null &&
          profile!.homeCountryCode!.trim().isNotEmpty)
        profile.homeCountryCode!.trim().toUpperCase(),
      if (profile?.hostCountryCode != null &&
          profile!.hostCountryCode!.trim().isNotEmpty)
        profile.hostCountryCode!.trim().toUpperCase(),
    };

    final List<WorldLanguage> recommendedLanguages = [];
    final Set<String> seenRecommended = {};
    for (final cCode in userCountryCodes) {
      for (final lang in getOfficialLanguagesForCountry(cCode)) {
        if (seenRecommended.add(lang.code)) {
          recommendedLanguages.add(lang);
        }
      }
    }

    final q = _query.trim().toLowerCase();

    // Filter languages
    final List<WorldLanguage> filteredLanguages = worldLanguages.where((lang) {
      if (q.isEmpty) return true;
      if (lang.name.toLowerCase().contains(q) ||
          lang.nativeName.toLowerCase().contains(q) ||
          lang.code.toLowerCase().contains(q)) {
        return true;
      }
      // Also match if any country where this language is official matches query
      for (final c in getCountriesForLanguage(lang)) {
        if (c.name.toLowerCase().contains(q) ||
            c.code.toLowerCase() == q ||
            c.continent.displayName.toLowerCase().contains(q)) {
          return true;
        }
      }
      return false;
    }).toList();

    // Filter countries
    final List<Country> filteredCountries = countries.where((country) {
      if (q.isEmpty) return true;
      if (country.name.toLowerCase().contains(q) ||
          country.code.toLowerCase().contains(q) ||
          country.continent.displayName.toLowerCase().contains(q)) {
        return true;
      }
      final officialLangs = getOfficialLanguagesForCountry(country.code);
      return officialLangs.any(
        (l) =>
            l.name.toLowerCase().contains(q) ||
            l.nativeName.toLowerCase().contains(q),
      );
    }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.elevationColor(context, 2),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.standardBorderRadius),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.hintColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 4),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        LucideIcons.languages,
                        color: AppTheme.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.tr(ref, 'Select Language'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            AppLocalizations.tr(
                              ref,
                              'Choose from official languages of all countries',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Search bar (strictly borderless)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.tr(
                      ref,
                      'Search country or language...',
                    ),
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: AppTheme.elevationColor(context, 3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // View Mode Toggle (All Languages vs By Country) — strictly borderless
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.elevationColor(context, 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildModeTab(
                          context,
                          label:
                              '${AppLocalizations.tr(ref, 'All Languages')} (${worldLanguages.length})',
                          icon: LucideIcons.languages,
                          active: !_byCountryMode,
                          onTap: () => setState(() => _byCountryMode = false),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildModeTab(
                          context,
                          label:
                              '${AppLocalizations.tr(ref, 'By Country')} (${countries.length})',
                          icon: LucideIcons.globe,
                          active: _byCountryMode,
                          onTap: () => setState(() => _byCountryMode = true),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Main scrollable list
              Expanded(
                child: _byCountryMode
                    ? _buildByCountryList(
                        context,
                        scrollController,
                        filteredCountries,
                        selectedCode,
                      )
                    : _buildAllLanguagesList(
                        context,
                        scrollController,
                        filteredLanguages,
                        recommendedLanguages,
                        selectedCode,
                        q.isEmpty,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeTab(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? AppTheme.accent : theme.hintColor,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active
                      ? AppTheme.accent
                      : theme.textTheme.bodyMedium?.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllLanguagesList(
    BuildContext context,
    ScrollController scrollController,
    List<WorldLanguage> languages,
    List<WorldLanguage> recommended,
    String selectedCode,
    bool showRecommended,
  ) {
    final theme = Theme.of(context);
    if (languages.isEmpty) {
      return Center(
        child: Text(
          'No matching languages found.',
          style: TextStyle(color: theme.hintColor),
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: [
        if (showRecommended && recommended.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 2),
            child: Text(
              AppLocalizations.tr(
                ref,
                'Recommended for Your Countries',
              ).toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: theme.hintColor,
              ),
            ),
          ),
          ...recommended.map(
            (lang) => _buildLanguageTile(
              context,
              lang,
              isSelected: lang.code == selectedCode,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              AppLocalizations.tr(ref, 'All Languages').toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: theme.hintColor,
              ),
            ),
          ),
        ],
        ...languages.map(
          (lang) => _buildLanguageTile(
            context,
            lang,
            isSelected: lang.code == selectedCode,
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageTile(
    BuildContext context,
    WorldLanguage lang, {
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    final langCountries = getCountriesForLanguage(lang);
    final countrySample = langCountries.take(4).map((c) => c.name).join(', ');
    final moreCount = langCountries.length > 4 ? langCountries.length - 4 : 0;
    final countriesLabel = moreCount > 0
        ? '$countrySample +$moreCount more'
        : countrySample;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _selectLanguage(lang),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accent.withValues(alpha: 0.14)
                : AppTheme.elevationColor(context, 3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Text(lang.primaryFlag, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            lang.nativeName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? AppTheme.accent
                                  : theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                        ),
                        if (lang.nativeName.toLowerCase() !=
                            lang.name.toLowerCase()) ...[
                          const SizedBox(width: 6),
                          Text(
                            '• ${lang.name}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (countriesLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        countriesLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.hintColor.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.check,
                    size: 16,
                    color: AppTheme.accent,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    lang.code.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: theme.hintColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildByCountryList(
    BuildContext context,
    ScrollController scrollController,
    List<Country> countryList,
    String selectedCode,
  ) {
    final theme = Theme.of(context);
    if (countryList.isEmpty) {
      return Center(
        child: Text(
          'No matching countries found.',
          style: TextStyle(color: theme.hintColor),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: countryList.length,
      itemBuilder: (context, index) {
        final country = countryList[index];
        final officialLangs = getOfficialLanguagesForCountry(country.code);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.elevationColor(context, 3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(country.flag, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        country.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      country.continent.displayName,
                      style: TextStyle(fontSize: 11, color: theme.hintColor),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: officialLangs.map((lang) {
                    final active = lang.code == selectedCode;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _selectLanguage(lang),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: active
                              ? AppTheme.accent.withValues(alpha: 0.18)
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.07,
                                ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              lang.nativeName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: active
                                    ? AppTheme.accent
                                    : theme.textTheme.bodyMedium?.color,
                              ),
                            ),
                            if (lang.nativeName.toLowerCase() !=
                                lang.name.toLowerCase()) ...[
                              const SizedBox(width: 4),
                              Text(
                                '(${lang.name})',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: active
                                      ? AppTheme.accent
                                      : theme.hintColor,
                                ),
                              ),
                            ],
                            if (active) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                LucideIcons.check,
                                size: 13,
                                color: AppTheme.accent,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
