import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:ui'; // Import for ImageFilter
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/models/chat.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_card.dart';
import 'package:diaspora_nearby/features/chat/screens/chats_list_screen.dart'; // Import for provider

class ForwardChatSelectionScreen extends ConsumerStatefulWidget {
  const ForwardChatSelectionScreen({super.key});

  @override
  ConsumerState<ForwardChatSelectionScreen> createState() => _ForwardChatSelectionScreenState();
}

class _ForwardChatSelectionScreenState extends ConsumerState<ForwardChatSelectionScreen> {
  final Set<String> _selectedChatIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Reuse the EXACT same stream provider from ChatsListScreen for consistent data/caching
    final chatsAsync = ref.watch(userChatsStreamProvider);
    final greenColor = theme.colorScheme.primary; // Global accent

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      extendBodyBehindAppBar: true, // Enable content behind app bar for glass effect
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Transparent for glass effect
        elevation: 0,
        leading: null,
        automaticallyImplyLeading: false,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: theme.colorScheme.surface.withOpacity(0.8), // Semi-transparent background
            ),
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Forward message to...',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              icon: Icon(LucideIcons.x, color: greenColor, size: 24),
              onPressed: () => context.pop(),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            // Removed border: Border(bottom: ...)
            // Glassmorphism usually relies on shadow or subtle color diff, or just clean space
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search chats...',
                hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                prefixIcon: const Icon(LucideIcons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none, // Remove visible border
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none, // Remove visible border
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: greenColor.withOpacity(0.5)), // Subtle focus
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // List Content
          chatsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(child: Text('Error: $error')),
            data: (chats) {
                 final filteredChats = _searchQuery.isEmpty
                    ? chats
                    : chats.where((chat) {
                        return chat.name.toLowerCase().contains(_searchQuery.toLowerCase());
                      }).toList();

                if (filteredChats.isEmpty) {
                  return Center(child: Text('No chats found'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 120, left: 8, right: 8, bottom: 120), // Increased bottom padding for floating bar
                  itemCount: filteredChats.length,
                  itemBuilder: (context, index) {
                    final chat = filteredChats[index];
                    final isSelected = _selectedChatIds.contains(chat.id);

                    return GestureDetector(
                      onTap: () {
                         setState(() {
                           if (isSelected) {
                             _selectedChatIds.remove(chat.id);
                           } else {
                             _selectedChatIds.add(chat.id);
                           }
                         });
                      },
                      child: Stack(
                        children: [
                          // Base Chat Card (pixel perfect reuse)
                          AbsorbPointer( // Absorb tap so GestureDetector above handles it
                            child: ChatCard(
                              chat: chat,
                              searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
                              onTap: () {}, // Handled by parent
                            ),
                          ),
                          
                          // Selection Overlay
                          if (isSelected) 
                             Positioned.fill(
                               child: Container(
                                 margin: const EdgeInsets.symmetric(vertical: 4), // Match ChatCard margin if any?
                                 decoration: BoxDecoration(
                                    color: greenColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12), // Match typical card radius
                                    border: Border.all(color: greenColor, width: 2),
                                 ),
                               ),
                             ),

                           // Checkmark Badge
                           Positioned(
                              right: 16,
                              bottom: 18, // Aligned with bottom row (last message) to avoid timestamp overlap
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? greenColor : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected ? greenColor : theme.colorScheme.outline.withOpacity(0.3),
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(LucideIcons.check, size: 16, color: Colors.white)
                                    : null,
                              ),
                           ),
                        ],
                      ),
                    );
                  },
                );
              }
            ),
          
          // Sticky Bottom Bar
          if (_selectedChatIds.isNotEmpty)
             Positioned(
               bottom: 0,
               left: 0,
               right: 0,
               child: ClipRRect(
                 child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: theme.colorScheme.surface.withOpacity(0.8), 
                      child: SafeArea(
                        top: false, // Ensure top doesn't add padding if keyboard moves it?
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                context.pop(_selectedChatIds.toList());
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: greenColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                'Forward to ${_selectedChatIds.length} chat${_selectedChatIds.length > 1 ? 's' : ''}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                 ),
               ),
             ),
        ],
      ),
    );
  }
}


