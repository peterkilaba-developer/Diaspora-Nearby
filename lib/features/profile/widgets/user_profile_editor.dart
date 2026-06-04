import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';

import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/widgets/user_profile_form.dart';

class UserProfileEditor extends ConsumerStatefulWidget {
  final ProfileData initialProfile;
  final Future<void> Function(ProfileData, XFile?) onSave;
  final VoidCallback onCancel;
  final List<String>? highlightFields;

  const UserProfileEditor({
    super.key,
    required this.initialProfile,
    required this.onSave,
    required this.onCancel,
    this.highlightFields,
  });

  @override
  ConsumerState<UserProfileEditor> createState() => _UserProfileEditorState();
}

class _UserProfileEditorState extends ConsumerState<UserProfileEditor> {
  final GlobalKey<UserProfileFormState> _formKey =
      GlobalKey<UserProfileFormState>();
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: _isSaving ? null : widget.onCancel,
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: () {
                setState(() => _isSaving = true);
                _formKey.currentState?.submit();
              },
              child: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: UserProfileForm(
        key: _formKey,
        initialProfile: widget.initialProfile,
        onSave: widget.onSave,
        onCancel: widget.onCancel,
        highlightFields: widget.highlightFields,
        onSavingStateChanged: (val) => setState(() => _isSaving = val),
      ),
    );
  }
}
