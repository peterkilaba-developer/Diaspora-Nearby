import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Empty state for a chat with no messages
class ChatEmptyState extends StatelessWidget {
  final bool isListingChat;
  final String? listingType;
  final bool isSeller;
  final ValueChanged<String>? onQuickPromptTap;

  const ChatEmptyState({
    super.key,
    this.isListingChat = false,
    this.listingType,
    this.isSeller = false,
    this.onQuickPromptTap,
  });

  List<String> _getPrompts() {
    if (isSeller) {
      switch (listingType) {
        case 'job':
          return const [
            'This position is open and accepting applications.',
            'Feel free to share your experience or ask about the role!',
            'Interviews are being scheduled this week.',
          ];
        case 'service':
          return const [
            'I am available and taking new bookings.',
            'Feel free to ask about rates, availability, or custom requests!',
            'Fast turnaround and reliable service guaranteed.',
          ];
        default:
          return const [
            'Welcome! Let me know if you have any questions.',
            'This item is available and ready for pickup/delivery.',
            'Feel free to make an offer!',
          ];
      }
    }
    switch (listingType) {
      case 'service':
        return const [
          'Hi! Are you available for this service?',
          'Can I get a quote?',
          'What areas do you cover?',
        ];
      case 'job':
        return const [
          'Hi! Is this position still open?',
          'What are the next steps to apply?',
          'Can you share more details about the role?',
        ];
      default:
        return const [
          'Hi! Is this still available?',
          'Is the price negotiable?',
          'Where can we meet for pickup?',
          'Can you share more photos?',
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isListingChat) {
      final prompts = _getPrompts();
      final isJob = listingType == 'job';
      final isService = listingType == 'service';
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isJob
                      ? LucideIcons.briefcase
                      : isService
                      ? LucideIcons.wrench
                      : LucideIcons.shoppingCart,
                  size: 40,
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isSeller
                    ? (isJob
                          ? 'Your Job Chat is Ready'
                          : isService
                          ? 'Your Service Chat is Ready'
                          : 'Your Shop is Ready')
                    : (isService
                          ? 'Ask About This Service'
                          : isJob
                          ? 'Ask About This Job'
                          : 'Ask About This Product'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isSeller
                    ? (isJob
                          ? 'Share role updates or welcome applicants to your job chat.'
                          : isService
                          ? 'Share updates or welcome clients to your service chat.'
                          : 'Post an update or welcome shoppers to your shop.')
                    : 'Tap a quick question below or type a message to start.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (onQuickPromptTap != null) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: prompts.map((prompt) {
                    return ActionChip(
                      avatar: Icon(
                        LucideIcons.sparkles,
                        size: 14,
                        color: Colors.green.shade700,
                      ),
                      label: Text(
                        prompt,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onPressed: () => onQuickPromptTap!(prompt),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.messageCircle,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a message to start the conversation',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
