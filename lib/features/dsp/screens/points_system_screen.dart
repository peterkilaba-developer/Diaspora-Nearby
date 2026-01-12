import 'package:flutter/material.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/models/user_points.dart';
import 'package:diaspora_nearby/models/points_transaction.dart';
import 'package:diaspora_nearby/features/dsp/widgets/share_options_sheet.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

class PointsSystemScreen extends ConsumerWidget {
  const PointsSystemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    final userId = user.uid;
    // debugPrint('PointsSystemScreen: Loading data for userId: $userId'); // [DEBUG] Removed

    final pointsStream = ref.watch(pointsRepositoryProvider).streamUserPoints(userId);
    final transactionsStream = ref.watch(pointsRepositoryProvider).streamTransactionHistory(userId, limit: 50);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diaspora Social Points - DSP'),
        elevation: 0,
      ),
      body: StreamBuilder<UserPoints?>(
        stream: pointsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final userPoints = snapshot.data;

          if (userPoints == null) {
            return const Center(child: Text('No points data available'));
          }

          return SingleChildScrollView(
            padding: AppTheme.pagePaddingEdgeInsets,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, // Ensure full width
              children: [
                // Points Balance Card
                _buildBalanceCard(context, userPoints, ref),
                const SizedBox(height: 8),

                // Mining Schedule Card
                _buildMiningScheduleCard(context, ref),
                const SizedBox(height: 8),
                const SizedBox(height: 8),

                // Streak Progress Card
                _buildStreakCard(context, userPoints),
                const SizedBox(height: 8),

                // Referral Card
                _buildReferralCard(context, userId, ref),
                const SizedBox(height: 8),

                // How to Earn Section
                _buildHowToEarnSection(context),
                const SizedBox(height: 8),

                // Transaction History
                _buildTransactionHistory(context, transactionsStream),
                
                // Safe Area Padding
                SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, UserPoints userPoints, WidgetRef ref) {
    final user = ref.read(authRepositoryProvider).currentUser;
    final signupDate = user?.metadata.creationTime ?? DateTime.now();
    final daysSinceSignup = DateTime.now().difference(signupDate).inDays;
    
    // Calculate current parity
    // Period 0 (0-29 days): 1
    // Period 1 (30-59 days): 10
    // Period n: 10 * n (for n >= 1)
    
    int currentParity = 1;
    if (daysSinceSignup >= 30) {
      final periodIndex = daysSinceSignup ~/ 30; // 0-indexed period. 0-29=0, 30-59=1
      // However logic is: 1st 30 days = 1.
      // 2nd 30 days = 10.
      // 3rd = 20.
      // So if periodIndex is 0 (first 30 days), parity is 1.
      // If periodIndex >= 1, parity is periodIndex * 10.
      currentParity = periodIndex * 10; 
    }

    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(AppTheme.cardPadding), // Use standard card padding
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: Theme.of(context).brightness == Brightness.dark
              ? [AppTheme.accent.withOpacity(0.15), AppTheme.accent.withOpacity(0.05)]
              : [AppTheme.accent.withOpacity(0.1), AppTheme.accent.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.accent.withOpacity(0.3),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            LucideIcons.coins,
            size: 60,
            color: AppTheme.accent,
          ),
          const SizedBox(height: 16),
          Text(
            'Your Balance',
            style: TextStyle(
              color: Theme.of(context).hintColor,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${userPoints.availablePoints}',
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'DSP Points',
            style: TextStyle(
              color: Theme.of(context).hintColor,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Current Rate: $currentParity ${currentParity > 1 ? 'DSPs' : 'DSP'} = 1 \$DSP Token',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiningScheduleCard(BuildContext context, WidgetRef ref) {
    final user = ref.read(authRepositoryProvider).currentUser;
    // Calculate User's current day
    final signupDate = user?.metadata.creationTime ?? DateTime.now();
    final daysSinceSignup = DateTime.now().difference(signupDate).inDays;
    
    // Determine current period index (0-based)
    // 0-29 days => index 0
    // 30-59 days => index 1
    final currentPeriodIndex = daysSinceSignup ~/ 30;

    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(AppTheme.cardPadding),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.timer,
                  color: Colors.purple,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DSP Rewarding Schedule',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Points difficulty increases every 30 days',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Expanded(child: Text('Period', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 2, child: Text('Days Since Signup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('Reward Parity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Generate 12 Rows
          ...List.generate(12, (index) {
            String daysRange = '${index * 30 + 1} - ${(index + 1) * 30}';
            String parity = index == 0 ? '1 DSP = 1 Token' : '${index * 10} DSPs = 1 Token';
            bool isCurrent = index == currentPeriodIndex;

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(
                color: isCurrent 
                    ? AppTheme.accent.withOpacity(0.1) 
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: isCurrent 
                    ? Border.all(color: AppTheme.accent.withOpacity(0.5)) 
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${index + 1}${_getOrdinal(index + 1)}',
                      style: TextStyle(
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: isCurrent ? AppTheme.accent : null,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      daysRange,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      parity,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: isCurrent ? AppTheme.accent : null,
                         fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.2)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.alertTriangle, size: 16, color: Colors.red),
                SizedBox(width: 8),
                Text(
                  'Rewards System Ends: Dec 31, 2026',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getOrdinal(int number) {
    if (number >= 11 && number <= 13) return 'th';
    switch (number % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }

  Widget _buildStreakCard(BuildContext context, UserPoints userPoints) {
    final streak = userPoints.currentStreak;
    final progress7 = (streak / 7).clamp(0.0, 1.0);
    final progress30 = (streak / 30).clamp(0.0, 1.0);

    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(AppTheme.cardPadding),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.flame,
                  color: AppTheme.accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daily Streak',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$streak ${streak == 1 ? 'day' : 'days'}',
                      style: TextStyle(
                        color: Theme.of(context).hintColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // 7-day progress
          _buildStreakProgress(
            context,
            '7-Day Bonus',
            '10 DSPs',
            progress7,
            streak >= 7,
          ),
          const SizedBox(height: 16),
          
          // 30-day progress
          _buildStreakProgress(
            context,
            '30-Day Bonus',
            '60 DSPs',
            progress30,
            streak >= 30,
          ),
        ],
      ),
    );
  }

  Widget _buildStreakProgress(
    BuildContext context,
    String title,
    String reward,
    double progress,
    bool completed,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                if (completed)
                  const Icon(
                    LucideIcons.checkCircle,
                    color: Colors.green,
                    size: 16,
                  ),
                if (completed) const SizedBox(width: 4),
                Text(
                  reward,
                  style: TextStyle(
                    fontSize: 14,
                    color: completed ? Colors.green : Theme.of(context).hintColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade800
                : Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
              completed ? Colors.green : Colors.orange,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReferralCard(BuildContext context, String userId, WidgetRef ref) {
    // This card has been moved to a dedicated screen (ShareInviteScreen).
    // Returning SizedBox.shrink() effectively removes it from the UI.
    return const SizedBox.shrink();
  }

  Widget _buildHowToEarnSection(BuildContext context) {
    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(AppTheme.cardPadding),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How to Earn DSPs',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildEarnMethod(
            context,
            LucideIcons.userPlus,
            'Invite a Friend',
            '100 DSPs',
            AppTheme.accent,
          ),
          _buildEarnMethod(
            context,
            LucideIcons.sunrise,
            'Open App Daily',
            '1 DSP',
            AppTheme.accent,
          ),
          _buildEarnMethod(
            context,
            LucideIcons.messageCircle,
            'Send Messages',
            '1 DSP',
            AppTheme.accent,
          ),
          _buildEarnMethod(
            context,
            LucideIcons.flame,
            '7-Day Streak',
            '10 DSPs',
            AppTheme.accent,
          ),
          _buildEarnMethod(
            context,
            LucideIcons.trophy,
            '30-Day Streak',
            '60 DSPs',
            AppTheme.accent,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildEarnMethod(
    BuildContext context,
    IconData icon,
    String title,
    String points,
    Color color, {
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            points,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionHistory(
    BuildContext context,
    Stream<List<PointsTransaction>> transactionsStream,
  ) {
    return StreamBuilder<List<PointsTransaction>>(
      stream: transactionsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }

        final transactions = snapshot.data ?? [];

        if (transactions.isEmpty) {
          return Container(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    LucideIcons.inbox,
                    size: 48,
                    color: Theme.of(context).hintColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No activity yet',
                    style: TextStyle(
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Updated Container with Label INSIDE
        return Container(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(AppTheme.cardPadding), // Standard padding for container
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recent Activity',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: transactions.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final transaction = transactions[index];
                  return _buildTransactionItem(context, transaction);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTransactionItem(BuildContext context, PointsTransaction transaction) {
    IconData icon;
    Color color;

    switch (transaction.action) {
      case 'referral_signup':
        icon = LucideIcons.userPlus;
        color = AppTheme.accent;
        break;
      case 'daily_open':
        icon = LucideIcons.sunrise;
        color = AppTheme.accent;
        break;
      case 'message_sent':
        icon = LucideIcons.messageCircle;
        color = AppTheme.accent;
        break;
      case 'streak_7':
        icon = LucideIcons.flame;
        color = AppTheme.accent;
        break;
      case 'streak_30':
        icon = LucideIcons.trophy;
        color = AppTheme.accent;
        break;
      default:
        icon = LucideIcons.plus;
        color = AppTheme.accent;
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        transaction.displayAction,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        DateFormat('MMM d, y • h:mm a').format(transaction.timestamp),
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).hintColor,
        ),
      ),
      trailing: Text(
        '${transaction.points > 0 ? '+' : ''}${transaction.points}',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: transaction.points > 0 ? Colors.green : Colors.red, // [FIX] Color coding
        ),
      ),
    );
  }
}
