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

/// Compact website-style language toggle pill (`.lang-toggle` from diasporanearby.com):
/// Displays the active language flag and uppercase ISO code (e.g. `🇹🇿 SW` or `🇬🇧 EN`)
/// inside a strictly borderless surface pill.
class LanguageTogglePill extends ConsumerWidget {
  final bool showNativeName;

  const LanguageTogglePill({super.key, this.showNativeName = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLang = ref.watch(currentWorldLanguageProvider);
    final theme = Theme.of(context);
    final shortCode = currentLang.code.split('-').first.toUpperCase();

    return NoTranslate(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => showLanguageSelectorSheet(context, ref),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.elevationColor(context, 2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentLang.primaryFlag,
                  style: const TextStyle(fontSize: 15, height: 1),
                ),
                const SizedBox(width: 6),
                if (showNativeName) ...[
                  Flexible(
                    child: Text(
                      currentLang.nativeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  shortCode,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppTheme.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the website-matched World Language & Country Selector modal
/// (`Select World Language` — strictly borderless, max 8px horizontal margin,
/// and 10px blurred screen backdrop).
Future<void> showLanguageSelectorSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: const Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          child: _LanguageSelectorModalContent(),
        ),
      );
    },
  );
}

class _LanguageSelectorModalContent extends ConsumerStatefulWidget {
  const _LanguageSelectorModalContent();

  @override
  ConsumerState<_LanguageSelectorModalContent> createState() =>
      _LanguageSelectorModalContentState();
}

class _LanguageSelectorModalContentState
    extends ConsumerState<_LanguageSelectorModalContent> {
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
    final screenHeight = MediaQuery.of(context).size.height;

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

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 680,
        maxHeight: screenHeight * 0.86,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 2),
          borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header (matches .lang-modal-header from website)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 14, 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '🌐',
                      style: TextStyle(fontSize: 18, height: 1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.tr(ref, 'Select World Language'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.elevationColor(context, 3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        LucideIcons.x,
                        size: 18,
                        color: theme.hintColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Controls (Search + Mode Tabs — matches .lang-modal-controls)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.tr(
                        ref,
                        'Search country (e.g. Tanzania, Brazil) or language...',
                      ),
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: theme.hintColor,
                      ),
                      prefixIcon: const Icon(LucideIcons.search, size: 17),
                      suffixIcon: _query.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppTheme.elevationColor(context, 1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    LucideIcons.x,
                                    size: 14,
                                    color: theme.hintColor,
                                  ),
                                ),
                              ),
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: AppTheme.elevationColor(context, 3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.elevationColor(context, 1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildModeTab(
                            context,
                            label:
                                '${AppLocalizations.tr(ref, 'All Official Languages')} (${worldLanguages.length})',
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
                            active: _byCountryMode,
                            onTap: () => setState(() => _byCountryMode = true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: _byCountryMode
                  ? _buildByCountryList(context, filteredCountries, selectedCode)
                  : _buildAllLanguagesList(
                      context,
                      filteredLanguages,
                      recommendedLanguages,
                      selectedCode,
                      q.isEmpty,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTab(
    BuildContext context, {
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            color: active ? AppTheme.accent : theme.hintColor,
          ),
        ),
      ),
    );
  }

  Widget _buildAllLanguagesList(
    BuildContext context,
    List<WorldLanguage> languages,
    List<WorldLanguage> recommended,
    String selectedCode,
    bool showRecommended,
  ) {
    final theme = Theme.of(context);
    if (languages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            AppLocalizations.tr(
              ref,
              'No matching languages or countries found.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.hintColor, fontSize: 14),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 460;

        Widget buildGrid(List<WorldLanguage> items) {
          if (!isWide) {
            return Column(
              children: items
                  .map(
                    (lang) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildLanguageItem(
                        context,
                        lang,
                        isSelected:
                            lang.code.toLowerCase() ==
                            selectedCode.toLowerCase(),
                      ),
                    ),
                  )
                  .toList(),
            );
          }
          final List<Widget> rows = [];
          for (var i = 0; i < items.length; i += 2) {
            final first = items[i];
            final second = i + 1 < items.length ? items[i + 1] : null;
            rows.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildLanguageItem(
                        context,
                        first,
                        isSelected:
                            first.code.toLowerCase() ==
                            selectedCode.toLowerCase(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: second != null
                          ? _buildLanguageItem(
                              context,
                              second,
                              isSelected:
                                  second.code.toLowerCase() ==
                                  selectedCode.toLowerCase(),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            );
          }
          return Column(children: rows);
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          children: [
            if (showRecommended && recommended.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 8, top: 2),
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
              buildGrid(recommended),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 8),
                child: Text(
                  AppLocalizations.tr(
                    ref,
                    'All Official Languages',
                  ).toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: theme.hintColor,
                  ),
                ),
              ),
            ],
            buildGrid(languages),
          ],
        );
      },
    );
  }

  Widget _buildLanguageItem(
    BuildContext context,
    WorldLanguage lang, {
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    final langCountries = getCountriesForLanguage(lang);
    final countrySample = langCountries.take(4).map((c) => c.name).join(', ');
    final moreCount = langCountries.length > 4 ? langCountries.length - 4 : 0;
    final countryPreview = moreCount > 0
        ? '$countrySample +$moreCount more'
        : countrySample;
    final subLabel = countryPreview.isNotEmpty
        ? '${lang.name} • $countryPreview'
        : lang.name;

    return NoTranslate(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _selectLanguage(lang),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accent.withValues(alpha: 0.16)
                : AppTheme.elevationColor(context, 3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Text(
                lang.primaryFlag,
                style: const TextStyle(fontSize: 22, height: 1),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lang.nativeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? AppTheme.accent
                            : theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent
                      : theme.colorScheme.onSurface.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isSelected ? '✓' : lang.code.split('-').first.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? const Color(0xFF111111)
                        : theme.hintColor,
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
    List<Country> countryList,
    String selectedCode,
  ) {
    final theme = Theme.of(context);
    if (countryList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            AppLocalizations.tr(ref, 'No matching countries found.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.hintColor, fontSize: 14),
          ),
        ),
      );
    }

    return NoTranslate(
      child: ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      itemCount: countryList.length,
      itemBuilder: (context, index) {
        final country = countryList[index];
        final officialLangs = getOfficialLanguagesForCountry(country.code);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppTheme.elevationColor(context, 3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(country.flag, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        country.name,
                        style: const TextStyle(
                          fontSize: 14,
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
                    final active =
                        lang.code.toLowerCase() == selectedCode.toLowerCase();
                    final label =
                        lang.nativeName.toLowerCase() ==
                            lang.name.toLowerCase()
                        ? lang.name
                        : '${lang.nativeName} (${lang.name})';
                    return InkWell(
                      borderRadius: BorderRadius.circular(7),
                      onTap: () => _selectLanguage(lang),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: active
                              ? AppTheme.accent.withValues(alpha: 0.18)
                              : AppTheme.elevationColor(context, 1),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          active ? '$label ✓' : label,
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
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    ),
    );
  }
}
