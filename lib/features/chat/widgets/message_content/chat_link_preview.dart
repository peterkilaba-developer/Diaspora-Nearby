import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/chat/services/link_preview_service.dart';

/// Renders a clean, resilient link preview card inside chat messages.
/// Displays a branded compact platform card when a social post/Reel is behind
/// an age-gate or login wall and no thumbnail image is publicly accessible.
class ChatLinkPreview extends StatefulWidget {
  final String url;
  final bool isOwn;
  final VoidCallback? onTap;

  const ChatLinkPreview({
    super.key,
    required this.url,
    required this.isOwn,
    this.onTap,
  });

  @override
  State<ChatLinkPreview> createState() => _ChatLinkPreviewState();
}

class _ChatLinkPreviewState extends State<ChatLinkPreview> {
  Future<LinkPreviewData?>? _previewFuture;
  bool _imageLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _previewFuture = LinkPreviewService.getPreview(widget.url);
  }

  @override
  void didUpdateWidget(covariant ChatLinkPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _imageLoadFailed = false;
      _previewFuture = LinkPreviewService.getPreview(widget.url);
    }
  }

  Future<void> _defaultLaunchUrl() async {
    final uri = Uri.tryParse(widget.url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<LinkPreviewData?>(
      future: _previewFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data;
        if (data == null || !data.hasValidContent) {
          return const SizedBox.shrink();
        }

        final hasImage =
            !_imageLoadFailed &&
            data.imageUrl != null &&
            data.imageUrl!.trim().isNotEmpty;
        final hasDescription =
            data.description != null && data.description!.trim().isNotEmpty;

        final cardBgColor = theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.3);
        final titleColor = widget.isOwn
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface;
        final bodyColor = widget.isOwn
            ? theme.colorScheme.onPrimary.withValues(alpha: 0.85)
            : theme.colorScheme.onSurfaceVariant;

        // Compact branded horizontal card when no thumbnail image is available
        // (e.g. age-restricted/login-walled Instagram Reel or text-only preview)
        if (!hasImage) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Material(
                color: cardBgColor,
                child: InkWell(
                  onTap: widget.onTap ?? _defaultLaunchUrl,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPlatformBadge(data.siteName, data.url),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                data.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    (theme.textTheme.titleSmall ??
                                            const TextStyle(fontSize: 14))
                                        .copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: titleColor,
                                        ),
                              ),
                              if (hasDescription) ...[
                                const SizedBox(height: 2),
                                Text(
                                  data.description!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      (theme.textTheme.bodySmall ??
                                              const TextStyle(fontSize: 12))
                                          .copyWith(color: bodyColor),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          LucideIcons.externalLink,
                          size: 16,
                          color: bodyColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Material(
              color: cardBgColor,
              child: InkWell(
                onTap: widget.onTap ?? _defaultLaunchUrl,
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 160,
                        minWidth: double.infinity,
                      ),
                      child: CachedNetworkImage(
                        imageUrl: data.imageUrl!,
                        width: double.infinity,
                        height: 150,
                        fit: BoxFit.cover,
                        placeholder: (context, _) =>
                            Container(height: 150, color: cardBgColor),
                        errorWidget: (context, url, error) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && !_imageLoadFailed) {
                              setState(() {
                                _imageLoadFailed = true;
                              });
                            }
                          });
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            data.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (theme.textTheme.titleSmall ??
                                        const TextStyle(fontSize: 14))
                                    .copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: titleColor,
                                    ),
                          ),
                          if (hasDescription) ...[
                            const SizedBox(height: 3),
                            Text(
                              data.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (theme.textTheme.bodySmall ??
                                          const TextStyle(fontSize: 12))
                                      .copyWith(color: bodyColor),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlatformBadge(String? siteName, String url) {
    final site = (siteName ?? '').toLowerCase();
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';

    if (site == 'instagram' || host.contains('instagram.com')) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: [
              Color(0xFFF58529),
              Color(0xFFDD2A7B),
              Color(0xFF8134AF),
              Color(0xFF515BD4),
            ],
          ),
        ),
        child: const Icon(LucideIcons.instagram, color: Colors.white, size: 22),
      );
    }

    if (site == 'tiktok' || host.contains('tiktok.com')) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(LucideIcons.video, color: Colors.white, size: 20),
      );
    }

    if (site == 'facebook' ||
        host.contains('facebook.com') ||
        host == 'fb.watch') {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF1877F2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(LucideIcons.facebook, color: Colors.white, size: 22),
      );
    }

    if (site == 'youtube' ||
        host.contains('youtube.com') ||
        host.contains('youtu.be')) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFFF0000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(LucideIcons.youtube, color: Colors.white, size: 22),
      );
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(LucideIcons.globe, color: Colors.white, size: 20),
    );
  }
}
