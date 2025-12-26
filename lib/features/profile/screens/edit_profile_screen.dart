import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/shared/widgets/diaspora_app_bar.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:go_router/go_router.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _occupationController = TextEditingController();
  final _occupationController = TextEditingController();
  final _professionController = TextEditingController();
  final _industryController = TextEditingController();
  
  // Socials
  final _instagramController = TextEditingController();
  final _twitterController = TextEditingController();
  final _linkedinController = TextEditingController();
  final _facebookController = TextEditingController();

  // Lists
  List<String> _interests = [];
  List<String> _languages = [];
  List<String> _servicesOffered = [];
  List<String> _lookingFor = [];

  bool _isLoading = true;
  bool _isSaving = false;
  ProfileData? _currentProfile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      final profile = await ref.read(profileRepositoryProvider).getUserProfile(user.uid);
      if (profile != null) {
        setState(() {
          _currentProfile = profile;
          _firstNameController.text = profile.firstName;
          _lastNameController.text = profile.lastName;
          _bioController.text = profile.bio ?? '';
          _occupationController.text = profile.occupation ?? '';
          _occupationController.text = profile.occupation ?? '';
          _professionController.text = profile.profession ?? '';
          _industryController.text = profile.industry ?? '';
          
          _interests = List.from(profile.interests ?? []);
          _languages = List.from(profile.languages ?? []);
          _servicesOffered = List.from(profile.servicesOffered ?? []);
          _lookingFor = List.from(profile.lookingFor ?? []);

          if (profile.socialLinks != null) {
            _instagramController.text = profile.socialLinks!.instagram ?? '';
            _twitterController.text = profile.socialLinks!.twitter ?? '';
            _linkedinController.text = profile.socialLinks!.linkedin ?? '';
            _facebookController.text = profile.socialLinks!.facebook ?? '';
          }
          
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _bioController.dispose();
    _occupationController.dispose();
    _occupationController.dispose();
    _professionController.dispose();
    _industryController.dispose();
    _instagramController.dispose();
    _twitterController.dispose();
    _linkedinController.dispose();
    _facebookController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_currentProfile == null) return;

    setState(() => _isSaving = true);

    try {
      final updatedProfile = ProfileData(
        uid: _currentProfile!.uid,
        homeLocation: _currentProfile!.homeLocation,
        hostLocation: _currentProfile!.hostLocation,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _currentProfile!.phone,
        profileImage: _currentProfile!.profileImage, // To update image, use setup flow or add image picker here
        bio: _bioController.text.trim(),
        occupation: _occupationController.text.trim(),
        profession: _professionController.text.trim(),
        industry: _industryController.text.trim(),
        interests: _interests,
        languages: _languages,
        servicesOffered: _servicesOffered,
        lookingFor: _lookingFor,
        socialLinks: SocialLinks(
          instagram: _instagramController.text.trim().isEmpty ? null : _instagramController.text.trim(),
          twitter: _twitterController.text.trim().isEmpty ? null : _twitterController.text.trim(),
          linkedin: _linkedinController.text.trim().isEmpty ? null : _linkedinController.text.trim(),
          facebook: _facebookController.text.trim().isEmpty ? null : _facebookController.text.trim(),
        ),
        // Preserve other fields
        homeCountry: _currentProfile!.homeCountry,
        hostCountry: _currentProfile!.hostCountry,
        homeCountryCode: _currentProfile!.homeCountryCode,
        hostCountryCode: _currentProfile!.hostCountryCode,
        currentLocation: _currentProfile!.currentLocation,
        communityMemberships: _currentProfile!.communityMemberships,
        organizationMemberships: _currentProfile!.organizationMemberships,
        createdAt: _currentProfile!.createdAt,
        advertReportCount: _currentProfile!.advertReportCount,
        isBanned: _currentProfile!.isBanned,
        isAdmin: _currentProfile!.isAdmin,
        yearsInHostCountry: null,
      );

      await ref.read(profileRepositoryProvider).saveUserProfile(_currentProfile!.uid!, updatedProfile);
      
      // Update local provider
      ref.read(userProfileProvider.notifier).updateProfile(updatedProfile);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {int maxLines = 1, TextCapitalization textCapitalization = TextCapitalization.sentences}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
        ),
      ),
    );
  }

  // Tag Editor Helper using a Dialog
  Future<void> _editTags(String title, List<String> currentTags, Function(List<String>) onSave) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Edit $title'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    children: currentTags.map((tag) => Chip(
                      label: Text(tag),
                      onDeleted: () {
                        setState(() {
                          currentTags.remove(tag);
                        });
                      },
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Add new item',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          if (controller.text.isNotEmpty) {
                            setState(() {
                              currentTags.add(controller.text.trim());
                              controller.clear();
                            });
                          }
                        },
                      ),
                    ),
                    onSubmitted: (val) {
                       if (val.isNotEmpty) {
                            setState(() {
                              currentTags.add(val.trim());
                              controller.clear();
                            });
                          }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
            ],
          );
        }
      ),
    );
    onSave(currentTags);
    setState(() {}); // Rebuild main screen
  }

  Widget _buildTagSection(String title, IconData icon, List<String> tags, Function(List<String>) onSave) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title, icon),
        InkWell(
          onTap: () => _editTags(title, tags, onSave),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withOpacity(0.5)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: tags.isEmpty 
              ? const Text('Tap to add items...', style: TextStyle(color: Colors.grey))
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tags.map((t) => Chip(label: Text(t))).toList(),
                ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving 
              ? const CircularProgressIndicator(strokeWidth: 2)
              : const Text('Save', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Basic Info', LucideIcons.user),
              Row(
                children: [
                  Expanded(child: _buildTextField(_firstNameController, 'First Name', textCapitalization: TextCapitalization.words)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildTextField(_lastNameController, 'Last Name', textCapitalization: TextCapitalization.words)),
                ],
              ),
              _buildTextField(_bioController, 'Bio', maxLines: 3),
              _buildTextField(_occupationController, 'Occupation (e.g. Software Engineer)'),
              _buildTextField(_occupationController, 'Occupation (e.g. Software Engineer)'),
              
              _buildSectionHeader('Work Details', LucideIcons.briefcase),
              _buildTextField(_professionController, 'Profession'),
              _buildTextField(_industryController, 'Industry'),

              _buildTagSection('Interests', LucideIcons.heart, _interests, (l) => _interests = l),
              _buildTagSection('Languages', LucideIcons.languages, _languages, (l) => _languages = l),
              _buildTagSection('Services Offered', LucideIcons.star, _servicesOffered, (l) => _servicesOffered = l),
              _buildTagSection('Looking For', LucideIcons.search, _lookingFor, (l) => _lookingFor = l),

              _buildSectionHeader('Social Links', LucideIcons.link),
              _buildTextField(_instagramController, 'Instagram Username', textCapitalization: TextCapitalization.none),
              _buildTextField(_twitterController, 'Twitter/X Username', textCapitalization: TextCapitalization.none),
              _buildTextField(_linkedinController, 'LinkedIn URL', textCapitalization: TextCapitalization.none),
              _buildTextField(_facebookController, 'Facebook URL', textCapitalization: TextCapitalization.none),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
