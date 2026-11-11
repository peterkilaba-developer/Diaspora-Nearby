import 'dart:async';
import 'dart:convert';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diaspora_nearby/core/localization/system_ui_strings.dart';
import 'package:diaspora_nearby/core/providers/locale_provider.dart';

/// Marker widget (equivalent to `class="notranslate"` on the website) that
/// prevents [AppLocalizations]'s automatic render-tree translator from
/// translating native language names or ISO codes inside its subtree.
class NoTranslate extends StatelessWidget {
  final Widget child;

  const NoTranslate({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// Root scope placed inside `MaterialApp.router(builder: ...)` that keeps the
/// entire live Flutter render tree (`RenderParagraph`s across all screens,
/// cards, tabs, dialogs, bottom sheets, and input hints) translated into the
/// active world language—matching the website's full-DOM translation behavior.
class GlobalTranslationScope extends StatefulWidget {
  final String langCode;
  final int revision;
  final Widget child;

  const GlobalTranslationScope({
    super.key,
    required this.langCode,
    required this.revision,
    required this.child,
  });

  @override
  State<GlobalTranslationScope> createState() => _GlobalTranslationScopeState();
}

class _GlobalTranslationScopeState extends State<GlobalTranslationScope> {
  @override
  void initState() {
    super.initState();
    AppLocalizations.attachRootScope(
      context: context,
      langCode: widget.langCode,
      revision: widget.revision,
    );
  }

  @override
  void didUpdateWidget(covariant GlobalTranslationScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    AppLocalizations.attachRootScope(
      context: context,
      langCode: widget.langCode,
      revision: widget.revision,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Full-app localization & neural translation engine covering all 105 official
/// world languages (matching the website's language selector & neural translator).
///
/// Combines:
/// 1. 0ms synchronous static dictionary for high-frequency core UI strings.
/// 2. Persistent `SharedPreferences` + in-memory cache (`_dynamicCache`).
/// 3. Automatic batched neural translation fallback (`translate.googleapis.com`)
///    plus a live `RenderParagraph` tree walker so EVERY screen, modal, card,
///    tab, and label in the app adopts the selected language.
class AppLocalizations {
  static SharedPreferences? _prefs;
  static VoidCallback? _onCacheUpdated;

  static final Map<String, Map<String, String>> _dynamicCache = {};
  static final Set<String> _loadedPrefsLangs = {};
  static final Map<String, Set<String>> _pendingQueue = {};
  static final Map<String, Set<String>> _inFlight = {};
  static final Map<String, Set<String>> _knownTranslationsByLang = {};
  static final Map<String, String> _reverseToEnglish = {};
  static bool _staticIndexed = false;
  static Timer? _batchTimer;

  // RenderParagraph tree-translation state
  static final Expando<InlineSpan> _origSpan = Expando<InlineSpan>(
    'dn_orig_span',
  );
  static final Expando<InlineSpan> _lastAppliedSpan = Expando<InlineSpan>(
    'dn_last_applied_span',
  );
  static final Expando<String> _lastStamp = Expando<String>('dn_last_stamp');
  static final Expando<int> _origMaxLines = Expando<int>('dn_orig_max_lines');
  static final Expando<TextOverflow> _origOverflow = Expando<TextOverflow>(
    'dn_orig_overflow',
  );

  static Element? _rootElement;
  static String _activeNormLang = 'en';
  static int _activeRevision = 0;
  static bool _needsEnglishRestore = false;
  static bool _persistentHookInstalled = false;
  static bool _postFrameScheduled = false;

  static const Set<String> _protectedAcronyms = {
    'DSP',
    'PCT',
    'DDI',
    'POH',
    'PoH',
    'TDE',
    'TGE',
    'DEX',
    'PWA',
    'IOS',
    'iOS',
    'API',
    'GPS',
    'QR',
    'ID',
    'USDC',
    'ETH',
  };

  static void _ensureStaticIndexed() {
    if (_staticIndexed) return;
    _staticIndexed = true;
    _translations.forEach((lang, map) {
      final norm = _normalizeLang(lang);
      map.forEach((enKey, translatedVal) {
        _registerTranslationPair(norm, enKey, translatedVal);
      });
    });
  }

  static void _registerTranslationPair(
    String normLang,
    String enKey,
    String translatedVal,
  ) {
    final cleanKey = enKey.trim();
    final cleanVal = translatedVal.trim();
    if (cleanKey.isEmpty || cleanVal.isEmpty) return;
    _knownTranslationsByLang
        .putIfAbsent(normLang, () => <String>{})
        .add(cleanVal);
    if (cleanVal != cleanKey) {
      _reverseToEnglish.putIfAbsent(cleanVal, () => cleanKey);
    }
  }

  static void attachRootScope({
    required BuildContext context,
    required String langCode,
    required int revision,
  }) {
    _ensureStaticIndexed();
    if (context is Element) {
      _rootElement = context;
    }
    final nextNorm = _normalizeLang(langCode);
    if (_activeNormLang != 'en' && nextNorm == 'en') {
      _needsEnglishRestore = true;
    } else if (nextNorm != 'en') {
      _needsEnglishRestore = false;
    }
    _activeNormLang = nextNorm;
    _activeRevision = revision;

    if (!_persistentHookInstalled) {
      _persistentHookInstalled = true;
      WidgetsBinding.instance.addPersistentFrameCallback((_) {
        _onPersistentFrame();
      });
    }
    scheduleTreeTranslation();
  }

  static void _onPersistentFrame() {
    if (_activeNormLang == 'en' && !_needsEnglishRestore) return;
    if (_postFrameScheduled) return;
    final root = WidgetsBinding.instance.rootElement ?? _rootElement;
    if (root == null || !root.mounted) return;
    final stamp = '$_activeNormLang:$_activeRevision';
    if (_hasDirtyParagraphs(root, stamp)) {
      scheduleTreeTranslation();
    }
  }

  static void scheduleTreeTranslation() {
    if (_postFrameScheduled) return;
    _postFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postFrameScheduled = false;
      final root = WidgetsBinding.instance.rootElement ?? _rootElement;
      if (root == null || !root.mounted) return;
      final stamp = '$_activeNormLang:$_activeRevision';
      _visitAndTranslateElement(root, _activeNormLang, stamp);
      if (_activeNormLang == 'en') {
        _needsEnglishRestore = false;
      }
    });
  }

  static bool _hasDirtyParagraphs(Element el, String stamp) {
    if (!el.mounted) return false;
    if (el.widget is NoTranslate || el.widget is EditableText) return false;
    if (el is RenderObjectElement) {
      final ro = el.renderObject;
      if (ro is RenderParagraph && ro.attached) {
        if (!identical(ro.text, _lastAppliedSpan[ro]) ||
            _lastStamp[ro] != stamp) {
          return true;
        }
      }
    }
    bool found = false;
    el.visitChildren((child) {
      if (!found && _hasDirtyParagraphs(child, stamp)) {
        found = true;
      }
    });
    return found;
  }

  static void _visitAndTranslateElement(
    Element el,
    String normLang,
    String stamp,
  ) {
    if (!el.mounted) return;
    if (el.widget is NoTranslate || el.widget is EditableText) return;

    if (el is RenderObjectElement) {
      final ro = el.renderObject;
      if (ro is RenderParagraph && ro.attached) {
        _processRenderParagraph(ro, normLang, stamp);
      }
    }
    el.visitChildren((child) {
      _visitAndTranslateElement(child, normLang, stamp);
    });
  }

  static void _processRenderParagraph(
    RenderParagraph ro,
    String normLang,
    String stamp,
  ) {
    final currentSpan = ro.text;
    final lastApplied = _lastAppliedSpan[ro];

    if (!identical(currentSpan, lastApplied)) {
      _origSpan[ro] = _recoverOriginalSpan(currentSpan);
      _origMaxLines[ro] = ro.maxLines ?? -1;
      _origOverflow[ro] = ro.overflow;
    } else if (_lastStamp[ro] == stamp) {
      return;
    }

    final orig = _origSpan[ro] ?? currentSpan;
    final savedMaxLines = _origMaxLines[ro];
    final origMaxLines = (savedMaxLines == null || savedMaxLines == -1)
        ? null
        : savedMaxLines;
    final origOverflow = _origOverflow[ro] ?? ro.overflow;

    if (normLang == 'en') {
      if (ro.maxLines != origMaxLines) {
        ro.maxLines = origMaxLines;
      }
      if (ro.overflow != origOverflow) {
        ro.overflow = origOverflow;
      }
      if (!identical(currentSpan, orig)) {
        _lastAppliedSpan[ro] = orig;
        ro.text = orig;
      } else {
        _lastAppliedSpan[ro] = currentSpan;
      }
      _lastStamp[ro] = stamp;
      return;
    }

    InlineSpan translated = _translateInlineSpan(orig, normLang);
    if (!identical(translated, orig) && ro.hasSize) {
      translated = _guardParagraphOverflow(
        ro: ro,
        orig: orig,
        translated: translated,
        origMaxLines: origMaxLines,
        origOverflow: origOverflow,
      );
    }
    _lastAppliedSpan[ro] = translated;
    _lastStamp[ro] = stamp;
    if (!identical(currentSpan, translated)) {
      ro.text = translated;
    }
  }

  static InlineSpan _guardParagraphOverflow({
    required RenderParagraph ro,
    required InlineSpan orig,
    required InlineSpan translated,
    required int? origMaxLines,
    required TextOverflow origOverflow,
  }) {
    try {
      final constraints = ro.constraints;
      if (constraints.hasBoundedWidth && constraints.maxWidth > 0) {
        // Check if inside a bounded-height ancestor (before any viewport)
        bool hasBoundedHeightAncestor = constraints.hasBoundedHeight;
        double minSlack = double.infinity;

        RenderObject? parent = ro.parent;
        int depth = 0;
        while (parent != null && depth < 6) {
          if (parent is RenderAbstractViewport || parent is RenderSliver) {
            break;
          }
          if (parent is RenderBox && parent.hasSize) {
            if (parent.constraints.hasBoundedHeight) {
              hasBoundedHeightAncestor = true;
            }
            if (parent is RenderFlex &&
                parent.direction == Axis.vertical &&
                parent.constraints.hasBoundedHeight) {
              double childrenHeight = 0;
              RenderBox? child = parent.firstChild;
              while (child != null) {
                if (child.hasSize) {
                  childrenHeight += child.size.height;
                }
                final pd = child.parentData;
                child = pd is ContainerBoxParentData<RenderBox>
                    ? pd.nextSibling
                    : null;
              }
              final slack = parent.constraints.maxHeight - childrenHeight;
              if (slack < minSlack) {
                minSlack = slack;
              }
            }
          }
          parent = parent.parent;
          depth++;
        }

        if (hasBoundedHeightAncestor) {
          final origTp = TextPainter(
            text: orig,
            textDirection: ro.textDirection,
            textAlign: ro.textAlign,
            textScaler: ro.textScaler,
            maxLines: origMaxLines,
            strutStyle: ro.strutStyle,
          )..layout(maxWidth: constraints.maxWidth);

          final origLines = origTp.computeLineMetrics().length;
          final origHeight = origTp.height;
          origTp.dispose();

          final transTp = TextPainter(
            text: translated,
            textDirection: ro.textDirection,
            textAlign: ro.textAlign,
            textScaler: ro.textScaler,
            maxLines: origMaxLines,
            strutStyle: ro.strutStyle,
          )..layout(maxWidth: constraints.maxWidth);

          final transLines = transTp.computeLineMetrics().length;
          double transHeight = transTp.height;
          transTp.dispose();

          // Prevent unexpected line-wrapping expansion inside bounded-height containers
          if (origLines > 0 && transLines > origLines) {
            if (ro.maxLines != origLines) {
              ro.maxLines = origLines;
            }
            if (ro.overflow != TextOverflow.ellipsis) {
              ro.overflow = TextOverflow.ellipsis;
            }
            final clampedTp = TextPainter(
              text: translated,
              textDirection: ro.textDirection,
              textAlign: ro.textAlign,
              textScaler: ro.textScaler,
              maxLines: origLines,
              ellipsis: '…',
              strutStyle: ro.strutStyle,
            )..layout(maxWidth: constraints.maxWidth);
            transHeight = clampedTp.height;
            clampedTp.dispose();
          }

          final allowedExtra =
              (minSlack.isFinite && minSlack > 0) ? minSlack : 0.0;
          if (transHeight > origHeight + allowedExtra + 0.5 &&
              transHeight > 0) {
            final scale = ((origHeight + allowedExtra) / transHeight).clamp(
              0.82,
              0.94,
            );
            return _scaleInlineSpan(translated, scale, compactHeight: true);
          }
        }
        return translated;
      }

      // Unbounded width (e.g. direct/nested child of a horizontal Row without Expanded/Flexible)
      RenderFlex? enclosingRow;
      RenderBox? rowDirectChild;
      RenderObject? curr = ro;
      RenderObject? parent = ro.parent;
      int depth = 0;
      while (parent != null && depth < 5) {
        if (parent is RenderAbstractViewport || parent is RenderSliver) {
          break;
        }
        if (parent is RenderFlex &&
            parent.direction == Axis.horizontal &&
            parent.hasSize &&
            parent.constraints.hasBoundedWidth) {
          enclosingRow = parent;
          if (curr is RenderBox) {
            rowDirectChild = curr;
          }
          break;
        }
        curr = parent;
        parent = parent.parent;
        depth++;
      }

      if (enclosingRow != null &&
          rowDirectChild != null &&
          rowDirectChild.hasSize) {
        double totalRowChildrenWidth = 0;
        RenderBox? child = enclosingRow.firstChild;
        while (child != null) {
          if (child.hasSize) {
            totalRowChildrenWidth += child.size.width;
          }
          final pd = child.parentData;
          child = pd is ContainerBoxParentData<RenderBox>
              ? pd.nextSibling
              : null;
        }

        final nonTextInSubtree = (rowDirectChild.size.width - ro.size.width)
            .clamp(0.0, double.infinity);
        final otherSiblingsWidth =
            totalRowChildrenWidth - rowDirectChild.size.width;
        final maxAllowedTextWidth =
            enclosingRow.constraints.maxWidth -
            otherSiblingsWidth -
            nonTextInSubtree;

        if (maxAllowedTextWidth > 20) {
          final transTp = TextPainter(
            text: translated,
            textDirection: ro.textDirection,
            textAlign: ro.textAlign,
            textScaler: ro.textScaler,
            maxLines: 1,
            strutStyle: ro.strutStyle,
          )..layout();
          final transWidth = transTp.width;
          transTp.dispose();

          if (transWidth > maxAllowedTextWidth) {
            final ratio = (maxAllowedTextWidth / transWidth).clamp(0.80, 0.96);
            InlineSpan adjusted = _scaleInlineSpan(translated, ratio);

            final scaledTp = TextPainter(
              text: adjusted,
              textDirection: ro.textDirection,
              textAlign: ro.textAlign,
              textScaler: ro.textScaler,
              maxLines: 1,
              strutStyle: ro.strutStyle,
            )..layout();
            final scaledWidth = scaledTp.width;
            scaledTp.dispose();

            if (scaledWidth > maxAllowedTextWidth) {
              adjusted = _truncateInlineSpanToWidth(
                span: adjusted,
                ro: ro,
                maxWidth: maxAllowedTextWidth,
              );
            }
            if (ro.maxLines != 1) {
              ro.maxLines = 1;
            }
            if (ro.overflow != TextOverflow.ellipsis) {
              ro.overflow = TextOverflow.ellipsis;
            }
            return adjusted;
          }
        }
      }
    } catch (_) {
      // Never fail rendering if layout inspection encounters an unexpected tree state
    }
    return translated;
  }

  static InlineSpan _scaleInlineSpan(
    InlineSpan span,
    double scale, {
    bool compactHeight = false,
  }) {
    if (span is TextSpan) {
      final baseStyle = span.style ?? const TextStyle();
      final baseFontSize = baseStyle.fontSize ?? 14.0;
      final newStyle = baseStyle.copyWith(
        fontSize: baseFontSize * scale,
        height: compactHeight ? 1.05 : baseStyle.height,
      );
      List<InlineSpan>? scaledChildren;
      if (span.children != null && span.children!.isNotEmpty) {
        scaledChildren = span.children!
            .map(
              (c) => _scaleInlineSpan(
                c,
                scale,
                compactHeight: compactHeight,
              ),
            )
            .toList();
      }
      return TextSpan(
        text: span.text,
        children: scaledChildren,
        style: newStyle,
        recognizer: span.recognizer,
        mouseCursor: span.mouseCursor,
        onEnter: span.onEnter,
        onExit: span.onExit,
        semanticsLabel: span.semanticsLabel,
        locale: span.locale,
        spellOut: span.spellOut,
      );
    }
    return span;
  }

  static InlineSpan _truncateInlineSpanToWidth({
    required InlineSpan span,
    required RenderParagraph ro,
    required double maxWidth,
  }) {
    if (span is! TextSpan) return span;
    final fullText = span.toPlainText().trimRight();
    if (fullText.length <= 2) return span;

    int low = 1;
    int high = fullText.length - 1;
    String best = '${fullText.substring(0, 1)}…';

    while (low <= high) {
      final mid = (low + high) >> 1;
      final candidateText = '${fullText.substring(0, mid).trimRight()}…';
      final candidateSpan = TextSpan(
        text: candidateText,
        style: span.style,
      );
      final tp = TextPainter(
        text: candidateSpan,
        textDirection: ro.textDirection,
        textAlign: ro.textAlign,
        textScaler: ro.textScaler,
        maxLines: 1,
        strutStyle: ro.strutStyle,
      )..layout();
      final w = tp.width;
      tp.dispose();

      if (w <= maxWidth) {
        best = candidateText;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return TextSpan(
      text: best,
      style: span.style,
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel: fullText,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }

  static InlineSpan _recoverOriginalSpan(InlineSpan span) {
    if (span is TextSpan) {
      String? newText = span.text;
      bool changed = false;

      if (newText != null && newText.trim().isNotEmpty) {
        final leading = RegExp(r'^\s*').firstMatch(newText)?.group(0) ?? '';
        final trailing = RegExp(r'\s*$').firstMatch(newText)?.group(0) ?? '';
        final core = newText.trim();
        final englishCore = _reverseToEnglish[core];
        if (englishCore != null && englishCore != core) {
          newText = '$leading$englishCore$trailing';
          changed = true;
        }
      }

      List<InlineSpan>? newChildren;
      final children = span.children;
      if (children != null && children.isNotEmpty) {
        for (var i = 0; i < children.length; i++) {
          final child = children[i];
          final recoveredChild = _recoverOriginalSpan(child);
          if (!identical(recoveredChild, child)) {
            newChildren ??= List<InlineSpan>.from(children);
            newChildren[i] = recoveredChild;
            changed = true;
          }
        }
      }

      if (!changed) return span;
      return TextSpan(
        text: newText,
        children: newChildren ?? span.children,
        style: span.style,
        recognizer: span.recognizer,
        mouseCursor: span.mouseCursor,
        onEnter: span.onEnter,
        onExit: span.onExit,
        semanticsLabel: span.semanticsLabel,
        locale: span.locale,
        spellOut: span.spellOut,
      );
    }
    return span;
  }

  static InlineSpan _translateInlineSpan(InlineSpan span, String normLang) {
    if (span is TextSpan) {
      String? newText = span.text;
      bool changed = false;

      if (newText != null && newText.trim().isNotEmpty) {
        final leading = RegExp(r'^\s*').firstMatch(newText)?.group(0) ?? '';
        final trailing = RegExp(r'\s*$').firstMatch(newText)?.group(0) ?? '';
        final core = newText.trim();
        final translatedCore = translate(normLang, core);
        if (translatedCore != core) {
          newText = '$leading$translatedCore$trailing';
          changed = true;
        }
      }

      List<InlineSpan>? newChildren;
      final children = span.children;
      if (children != null && children.isNotEmpty) {
        for (var i = 0; i < children.length; i++) {
          final child = children[i];
          final translatedChild = _translateInlineSpan(child, normLang);
          if (!identical(translatedChild, child)) {
            newChildren ??= List<InlineSpan>.from(children);
            newChildren[i] = translatedChild;
            changed = true;
          }
        }
      }

      if (!changed) return span;
      return TextSpan(
        text: newText,
        children: newChildren ?? span.children,
        style: span.style,
        recognizer: span.recognizer,
        mouseCursor: span.mouseCursor,
        onEnter: span.onEnter,
        onExit: span.onExit,
        semanticsLabel: span.semanticsLabel,
        locale: span.locale,
        spellOut: span.spellOut,
      );
    }
    return span;
  }

  static void bindPersistence({
    required SharedPreferences prefs,
    required VoidCallback onCacheUpdated,
  }) {
    _ensureStaticIndexed();
    _prefs = prefs;
    _onCacheUpdated = () {
      onCacheUpdated();
      scheduleTreeTranslation();
    };
  }

  static void loadPersistedLanguageCache(String langCode) {
    _ensureStaticIndexed();
    final norm = _normalizeLang(langCode);
    if (norm == 'en' || _loadedPrefsLangs.contains(norm)) return;
    final prefs = _prefs;
    if (prefs == null) return;
    _loadedPrefsLangs.add(norm);
    try {
      // Purge legacy cache versions that may contain translated user names or user messages
      unawaited(prefs.remove('dn_i18n_cache_v1_$norm'));
      unawaited(prefs.remove('dn_i18n_cache_v2_$norm'));
      final raw = prefs.getString('dn_i18n_cache_v3_$norm');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final bucket = _dynamicCache.putIfAbsent(norm, () => {});
          decoded.forEach((k, v) {
            if (k is String &&
                v is String &&
                v.trim().isNotEmpty &&
                _isExactSystemUiString(k)) {
              bucket[k] = v;
              _registerTranslationPair(norm, k, v);
            }
          });
        }
      }
    } catch (_) {}
  }

  static void _savePersistedLanguageCache(String normLang) {
    final prefs = _prefs;
    if (prefs == null) return;
    final bucket = _dynamicCache[normLang];
    if (bucket == null || bucket.isEmpty) return;
    try {
      unawaited(
        prefs.setString('dn_i18n_cache_v3_$normLang', jsonEncode(bucket)),
      );
    } catch (_) {}
  }

  static String _normalizeLang(String code) {
    final clean = code.trim();
    if (clean.isEmpty) return 'en';
    if (clean.toLowerCase() == 'zh-cn' || clean.toLowerCase() == 'zh') {
      return 'zh-CN';
    }
    if (clean.toLowerCase() == 'zh-tw') return 'zh-TW';
    return clean.split('-').first.toLowerCase();
  }

  /// Reactive translation helper for ConsumerWidget / ConsumerStatefulWidget.
  static String tr(WidgetRef ref, String text) {
    final lang = ref.watch(localeProvider);
    ref.watch(translationRevisionProvider);
    return translate(lang, text);
  }

  /// Context-based translation helper for any widget with a BuildContext.
  static String of(BuildContext context, String text) {
    try {
      final container = ProviderScope.containerOf(context, listen: true);
      final lang = container.read(localeProvider);
      container.read(translationRevisionProvider);
      return translate(lang, text);
    } catch (_) {
      return text;
    }
  }

  static String translate(String langCode, String text) {
    if (text.trim().isEmpty) return text;
    final norm = _normalizeLang(langCode);
    if (norm == 'en') return text;

    _ensureStaticIndexed();

    // Handle multi-line text line by line so neural queue items never contain '\n'
    if (text.contains('\n')) {
      final lines = text.split('\n');
      bool anyChanged = false;
      final outLines = lines.map((line) {
        if (line.trim().isEmpty) return line;
        final leading = RegExp(r'^\s*').firstMatch(line)?.group(0) ?? '';
        final trailing = RegExp(r'\s*$').firstMatch(line)?.group(0) ?? '';
        final core = line.trim();
        final translatedCore = translate(norm, core);
        if (translatedCore != core) anyChanged = true;
        return '$leading$translatedCore$trailing';
      }).toList();
      return anyChanged ? outLines.join('\n') : text;
    }

    final base = norm.split('-').first;
    loadPersistedLanguageCache(norm);

    // If text is already a known translation in the target language, return as-is
    if (_knownTranslationsByLang[norm]?.contains(text) == true ||
        _knownTranslationsByLang[base]?.contains(text) == true) {
      return text;
    }

    // 1. Exact System UI string allowlist check
    if (_isExactSystemUiString(text)) {
      return _translateExactSystemString(norm, text);
    }

    // 2. Parameterized System UI templates (times, counts, and name-preserving system actions)
    return _translateSystemUiTemplate(norm, text);
  }

  static const Set<String> _templateSystemTokens = {
    'AM',
    'PM',
    'ago',
    'second',
    'seconds',
    'minute',
    'minutes',
    'hour',
    'hours',
    'day',
    'days',
    'week',
    'weeks',
    'month',
    'months',
    'year',
    'years',
    'people typing...',
    'typing...',
    'joined the community',
    'joined the community.',
    'joined the group',
    'joined the group.',
    'left the community',
    'left the group',
    'was added',
    'was removed',
    'is typing...',
    'sent you a request',
    'wants to host you!',
    'selected as your host!',
    'wants you to be their emergency fund proxy.',
    'wants you to be their emergency fund proxy. Tap to respond.',
    'Sovereign Bond Treasury',
    'Continental Treasury',
    'Reserve Treasury',
    'DDI Treasury',
    'Community',
    'Replying to',
    'To:',
    'Bereaving',
    'Hosted by',
    'Organized by',
    'Remittance',
    'sent',
    'received',
    'Sent',
    'Received',
    'Converted',
    'member',
    'members',
    'members worldwide',
    'going',
    'interested',
    'listeners',
    'countries',
    'online',
    'more',
  };

  static const List<String> _namePreservingSystemSuffixes = [
    ' wants you to be their emergency fund proxy. Tap to respond.',
    ' wants you to be their emergency fund proxy.',
    ' joined the community.',
    ' joined the community',
    ' joined the group.',
    ' joined the group',
    ' left the community',
    ' left the group',
    ' selected as your host!',
    ' wants to host you!',
    ' sent you a request',
    ' is typing...',
    ' was removed',
    ' was added',
    ' Sovereign Bond Treasury',
    ' Continental Treasury',
    ' Reserve Treasury',
    ' DDI Treasury',
    ' Community',
  ];

  static const List<String> _namePreservingSystemPrefixes = [
    'Replying to ',
    'Organized by ',
    'Hosted by ',
    'Bereaving ',
    'To: ',
  ];

  static bool _isExactSystemUiString(String text) {
    final trimmed = text.trim();
    if (trimmed.length < 2 || trimmed.length > 1200) return false;
    if (_protectedAcronyms.contains(trimmed)) return false;
    if (trimmed == r'$DIASPORA' || trimmed == 'Diaspora Nearby') return false;
    if ( _templateSystemTokens.contains(trimmed)) return true;
    if (RegExp(r'^[A-Z]{2}$').hasMatch(trimmed)) return false;
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('0x') ||
        (trimmed.contains('@') && !trimmed.contains(' '))) {
      return false;
    }
    return kSystemUiLiterals.contains(trimmed) ||
        _coreVocabulary.contains(trimmed) ||
        (_translations['es']?.containsKey(trimmed) ?? false) ||
        (_translations['fr']?.containsKey(trimmed) ?? false);
  }

  static String _translateExactSystemString(String norm, String text) {
    final base = norm.split('-').first;
    if (_knownTranslationsByLang[norm]?.contains(text) == true ||
        _knownTranslationsByLang[base]?.contains(text) == true) {
      return text;
    }

    final dict = _translations[norm] ?? _translations[base];
    if (dict != null && dict.containsKey(text)) {
      return dict[text]!;
    }

    final cached = _dynamicCache[norm]?[text] ?? _dynamicCache[base]?[text];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    _enqueueDynamicTranslation(norm, text);
    return text;
  }

  static String _translateSystemUiTemplate(String norm, String text) {
    final trimmed = text.trim();
    if (trimmed.length < 2 || trimmed.length > 300) return text;

    // A. Clock time (e.g., "8:44 PM", "10:15 AM")
    final timeMatch = RegExp(
      r'^(\d{1,2}:\d{2}(?::\d{2})?)\s+(AM|PM|am|pm)$',
    ).firstMatch(trimmed);
    if (timeMatch != null) {
      final timePart = timeMatch.group(1)!;
      final period = timeMatch.group(2)!.toUpperCase();
      return '$timePart ${_translateExactSystemString(norm, period)}';
    }

    // B. Relative time (e.g., "5m ago", "2 hours ago", "3d ago")
    final agoMatch = RegExp(
      r'^(\d+)\s*(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days|w|wk|wks|week|weeks|mo|month|months|y|yr|yrs|year|years)\s+ago$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (agoMatch != null) {
      final numPart = agoMatch.group(1)!;
      final unitPart = agoMatch.group(2)!;
      final agoTranslated = _translateExactSystemString(norm, 'ago');
      if (unitPart.length <= 2) {
        return '$numPart$unitPart $agoTranslated';
      }
      final unitTranslated = _isExactSystemUiString(unitPart.toLowerCase())
          ? _translateExactSystemString(norm, unitPart.toLowerCase())
          : unitPart;
      return '$numPart $unitTranslated $agoTranslated';
    }

    // C. Count + "people typing..."
    final typingCountMatch = RegExp(
      r'^(\d+)\s+(people typing\.\.\.)$',
    ).firstMatch(trimmed);
    if (typingCountMatch != null) {
      return '${typingCountMatch.group(1)} ${_translateExactSystemString(norm, 'people typing...')}';
    }

    // D. Remittance / Token / DSP transfer system preview
    final remittanceMatch = RegExp(
      r'^Remittance\s+([A-Z]{3})\s+([\d,.]+)\s+(sent|received)$',
    ).firstMatch(trimmed);
    if (remittanceMatch != null) {
      final remLabel = _translateExactSystemString(norm, 'Remittance');
      final dirLabel = _translateExactSystemString(
        norm,
        remittanceMatch.group(3)!,
      );
      return '$remLabel ${remittanceMatch.group(1)} ${remittanceMatch.group(2)} $dirLabel';
    }

    final dspTransferMatch = RegExp(
      r'^([\d,.]+)\s+(DSP|\$DIASPORA)\s+(Sent|Received|Converted)$',
    ).firstMatch(trimmed);
    if (dspTransferMatch != null) {
      final dirLabel = _translateExactSystemString(
        norm,
        dspTransferMatch.group(3)!,
      );
      return '${dspTransferMatch.group(1)} ${dspTransferMatch.group(2)} $dirLabel';
    }

    // E. System UI label with parenthesized count/number (e.g., "All Official Languages (105)")
    final parenMatch = RegExp(
      r'^(.+?)\s*(\([\d,.\s/+%-]+\))$',
    ).firstMatch(trimmed);
    if (parenMatch != null) {
      final label = parenMatch.group(1)!.trim();
      final countPart = parenMatch.group(2)!;
      if (_isExactSystemUiString(label)) {
        return '${_translateExactSystemString(norm, label)} $countPart';
      }
    }

    // F. Multi-segment bullet stats (e.g., "5 going • 2 interested", "10 listeners • 3 countries")
    if (trimmed.contains(' • ')) {
      final parts = trimmed.split(' • ');
      bool anyPartTranslated = false;
      final outParts = parts.map((p) {
        final cleanP = p.trim();
        final trP = _isExactSystemUiString(cleanP)
            ? _translateExactSystemString(norm, cleanP)
            : _translateSingleNumericSystemSegment(norm, cleanP);
        if (trP != cleanP) anyPartTranslated = true;
        return trP;
      }).toList();
      if (anyPartTranslated) {
        return outParts.join(' • ');
      }
    }

    // G. Name-Preserving System UI Suffixes (e.g., "Paul Kab joined the community", "Paul Kab is typing...")
    // The user name or place/code prefix is NEVER translated; only the fixed System UI suffix is translated.
    for (final suffix in _namePreservingSystemSuffixes) {
      if (trimmed.endsWith(suffix) && trimmed.length > suffix.length) {
        final nameOrPlacePrefix = trimmed
            .substring(0, trimmed.length - suffix.length)
            .trim();
        if (nameOrPlacePrefix.isNotEmpty) {
          final cleanSuffix = suffix.trim();
          final translatedSuffix = _translateExactSystemString(
            norm,
            cleanSuffix,
          );
          return '$nameOrPlacePrefix $translatedSuffix';
        }
      }
    }

    // H. Name-Preserving System UI Prefixes (e.g., "Replying to Paul Kab", "To: Paul Kab", "Bereaving John")
    // The user name suffix is NEVER translated; only the fixed System UI prefix is translated.
    for (final prefix in _namePreservingSystemPrefixes) {
      if (trimmed.startsWith(prefix) && trimmed.length > prefix.length) {
        final userNameSuffix = trimmed.substring(prefix.length).trim();
        if (userNameSuffix.isNotEmpty) {
          final cleanPrefix = prefix.trim();
          final translatedPrefix = _translateExactSystemString(
            norm,
            cleanPrefix,
          );
          return '$translatedPrefix $userNameSuffix';
        }
      }
    }

    // I. Single numeric prefix/suffix + exact System UI unit/label (e.g., "12 members", "+5 more", "Step 1")
    return _translateSingleNumericSystemSegment(norm, trimmed);
  }

  static String _translateSingleNumericSystemSegment(
    String norm,
    String segment,
  ) {
    final numPrefixMatch = RegExp(
      r'^([+\-≈$]?\d[\d,.\s/+%:-]*?)\s+([A-Za-z][A-Za-z\s.]*)$',
    ).firstMatch(segment);
    if (numPrefixMatch != null) {
      final numPart = numPrefixMatch.group(1)!.trim();
      final labelPart = numPrefixMatch.group(2)!.trim();
      if (_isExactSystemUiString(labelPart)) {
        return '$numPart ${_translateExactSystemString(norm, labelPart)}';
      }
    }

    final numSuffixMatch = RegExp(
      r'^([A-Za-z][A-Za-z\s:.-]*?)\s+([#$]?\d[\d,.\s/+%:-]*)$',
    ).firstMatch(segment);
    if (numSuffixMatch != null) {
      final labelPart = numSuffixMatch.group(1)!.trim();
      final numPart = numSuffixMatch.group(2)!.trim();
      if (_isExactSystemUiString(labelPart)) {
        return '${_translateExactSystemString(norm, labelPart)} $numPart';
      }
    }

    return segment;
  }

  static void _enqueueDynamicTranslation(String normLang, String text) {
    if (_inFlight[normLang]?.contains(text) == true) return;
    final queue = _pendingQueue.putIfAbsent(normLang, () => <String>{});
    if (!queue.add(text)) return;

    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 16), _flushPendingQueues);
  }

  static void _flushPendingQueues() {
    for (final entry in _pendingQueue.entries.toList()) {
      final lang = entry.key;
      final items = entry.value.toList();
      entry.value.clear();
      if (items.isNotEmpty) {
        unawaited(_translateBatch(lang, items));
      }
    }
  }

  static Future<void> preloadCoreVocabulary(String langCode) async {
    final norm = _normalizeLang(langCode);
    if (norm == 'en') return;
    loadPersistedLanguageCache(norm);

    final base = norm.split('-').first;
    final dict = _translations[norm] ?? _translations[base];
    final cached = _dynamicCache[norm] ?? const <String, String>{};

    final missing = <String>[];
    for (final phrase in _coreVocabulary) {
      if ((dict == null || !dict.containsKey(phrase)) &&
          !cached.containsKey(phrase)) {
        missing.add(phrase);
      }
    }
    if (missing.isNotEmpty) {
      await _translateBatch(norm, missing);
    }
  }

  static Future<void> _translateBatch(
    String normLang,
    List<String> phrases,
  ) async {
    final flightSet = _inFlight.putIfAbsent(normLang, () => <String>{});
    final toFetch = phrases.where((p) => flightSet.add(p)).toList();
    if (toFetch.isEmpty) return;

    const int chunkSize = 12;
    const int parallelWaves = 4;
    final List<List<String>> chunks = [];
    for (var i = 0; i < toFetch.length; i += chunkSize) {
      chunks.add(
        toFetch.sublist(
          i,
          i + chunkSize > toFetch.length ? toFetch.length : i + chunkSize,
        ),
      );
    }

    for (var w = 0; w < chunks.length; w += parallelWaves) {
      final wave = chunks.sublist(
        w,
        w + parallelWaves > chunks.length ? chunks.length : w + parallelWaves,
      );
      bool waveUpdated = false;

      await Future.wait(
        wave.map((chunk) async {
          try {
            final joined = chunk.join('\n');
            final uri = Uri.https(
              'translate.googleapis.com',
              '/translate_a/single',
              <String, String>{
                'client': 'gtx',
                'sl': 'en',
                'tl': normLang,
                'dt': 't',
                'q': joined,
              },
            );
            final response = await http
                .get(uri)
                .timeout(const Duration(seconds: 6));
            if (response.statusCode == 200) {
              final decoded = jsonDecode(utf8.decode(response.bodyBytes));
              if (decoded is List && decoded.isNotEmpty && decoded[0] is List) {
                final segments = decoded[0] as List;
                final buffer = StringBuffer();
                for (final seg in segments) {
                  if (seg is List && seg.isNotEmpty && seg[0] is String) {
                    buffer.write(seg[0] as String);
                  }
                }
                final translatedLines = buffer.toString().split('\n');
                final bucket = _dynamicCache.putIfAbsent(normLang, () => {});
                if (translatedLines.length == chunk.length) {
                  for (var j = 0; j < chunk.length; j++) {
                    final clean = _restoreProtectedTokens(
                      chunk[j],
                      translatedLines[j].trim(),
                    );
                    if (clean.isNotEmpty) {
                      bucket[chunk[j]] = clean;
                      _registerTranslationPair(normLang, chunk[j], clean);
                      waveUpdated = true;
                    }
                  }
                } else {
                  await Future.wait(
                    chunk.map((item) async {
                      final single = await _translateSingle(normLang, item);
                      if (single != null && single.isNotEmpty) {
                        bucket[item] = single;
                        _registerTranslationPair(normLang, item, single);
                        waveUpdated = true;
                      }
                    }),
                  );
                }
              }
            }
          } catch (_) {
          } finally {
            for (final item in chunk) {
              flightSet.remove(item);
            }
          }
        }),
      );

      if (waveUpdated) {
        _savePersistedLanguageCache(normLang);
        _onCacheUpdated?.call();
      }
    }
  }

  static Future<String?> _translateSingle(String normLang, String item) async {
    try {
      final uri = Uri.https(
        'translate.googleapis.com',
        '/translate_a/single',
        <String, String>{
          'client': 'gtx',
          'sl': 'en',
          'tl': normLang,
          'dt': 't',
          'q': item,
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is List && decoded.isNotEmpty && decoded[0] is List) {
          final segments = decoded[0] as List;
          final buffer = StringBuffer();
          for (final seg in segments) {
            if (seg is List && seg.isNotEmpty && seg[0] is String) {
              buffer.write(seg[0] as String);
            }
          }
          return _restoreProtectedTokens(item, buffer.toString().trim());
        }
      }
    } catch (_) {}
    return null;
  }

  static String _restoreProtectedTokens(String source, String translated) {
    var out = translated;
    if (source.contains(r'$DIASPORA') && !out.contains(r'$DIASPORA')) {
      out = out.replaceAll(
        RegExp(r'\$\s*DIASPORA', caseSensitive: false),
        r'$DIASPORA',
      );
    }
    return out;
  }

  static const List<String> _coreVocabulary = [
    'Diaspora Ecosystem',
    'Chats',
    'Nearby',
    'Events',
    'Communities',
    'Community',
    'joined the community',
    'Voice call',
    'Voice message',
    'Photo message',
    'Video message',
    'No messages yet',
    'Yesterday',
    'AM',
    'PM',
    'Radio',
    'Theme Mode',
    'Light',
    'Dark',
    'System',
    'Light Mode',
    'Dark Mode',
    'System Default',
    'Select World Language',
    'All main official languages of every country in the world',
    'Search country (e.g. Tanzania, Brazil) or language...',
    'All Official Languages',
    'All Languages',
    'By Country',
    'Recommended for Your Countries',
    'No matching languages or countries found.',
    'No matching countries found.',
    'SAFETY NET',
    'Ubuntu Emergency Fund',
    'Medical, Legal, Bereavement & Repatriation',
    'MARKETPLACE',
    'Products',
    'Buy from diaspora businesses',
    'Services',
    'Find diaspora services',
    'Jobs',
    'Find jobs',
    'TRAVEL',
    'Flights',
    'Book flights',
    'Hotels',
    'Find hotels',
    'Stays',
    'Short-term stays',
    'Car Rental',
    'Rent a car',
    'REAL ESTATE',
    'Land & Plots',
    'Farms',
    'Houses',
    'Rent, Lease or Buy',
    'MY WALLET',
    'Diaspora Social Points (DSP)',
    'Earn & convert to tokens',
    r'$DIASPORA Token',
    'Hold, Invest, Spend, Swap or Trade',
    'International Remittances',
    'Town DDI Loans',
    'Country DDI Loans',
    'Coming Soon',
    'QUICK SETTINGS',
    'Push Notifications',
    'Receive updates & alerts',
    'Location Always',
    'Allow background location updates',
    'App Language',
    'My Profile',
    'View & edit your profile',
    'Settings',
    'Account, language, privacy & theme',
    'Profile',
    'Edit',
    'Edit Profile',
    'Save',
    'Cancel',
    'Close',
    'Search',
    'Search chats...',
    'Search nearby people...',
    'Search events...',
    'Search communities...',
    'Search radio stations...',
    'All Nearby Members Connected',
    'You are already in active chats with all nearby community members in your area.',
    'View Active Chats',
    'Refresh Location',
    'Notifications',
    'Invite Friends',
    'Share Invite',
    'Log Out',
    'Sign out of your account',
    'Delete My Account',
    'Permanently delete your account and data',
    'Privacy & Safety',
    'Control your privacy settings',
    'Trust & Verification',
    'View your Community Trust breakdown',
  ];

  static const Map<String, Map<String, String>> _translations = {
    'sw': {
      'Diaspora Ecosystem': 'Mfumo wa Diaspora',
      'Chats': 'Mazungumzo',
      'Nearby': 'Karibu',
      'Events': 'Matukio',
      'Communities': 'Jumuiya',
      'Radio': 'Redio',
      'Settings': 'Mipangilio',
      'Profile': 'Wasifu',
      'Edit': 'Hariri',
      'Edit Profile': 'Hariri Wasifu',
      'Save': 'Hifadhi',
      'Cancel': 'Ghairi',
      'Close': 'Funga',
      'App Language': 'Lugha ya Programu',
      'Select World Language': 'Chagua Lugha ya Dunia',
      'All main official languages of every country in the world':
          'Lugha rasmi kuu zote za kila nchi duniani',
      'Choose from official languages of all countries':
          'Chagua kutoka lugha rasmi za nchi zote',
      'Select Language': 'Chagua Lugha',
      'Search country (e.g. Tanzania, Brazil) or language...':
          'Tafuta nchi (mf. Tanzania, Brazil) au lugha...',
      'Search country or language...': 'Tafuta nchi au lugha...',
      'All Official Languages': 'Lugha Rasmi Zote',
      'All Languages': 'Lugha Zote',
      'By Country': 'Kwa Nchi',
      'Recommended for Your Countries': 'Inapendekezwa kwa Nchi Zako',
      'No matching languages or countries found.':
          'Hakuna lugha au nchi inayolingana iliyopatikana.',
      'No matching countries found.': 'Hakuna nchi inayolingana iliyopatikana.',
      'Theme Mode': 'Mwonekano wa Rangi',
      'Light': 'angavu',
      'Dark': 'Giza',
      'System': 'Mfumo',
      'Light Mode': 'Mwonekano Angavu',
      'Dark Mode': 'Mwonekano wa Giza',
      'System Default': 'Chaguo la Mfumo',
      'SAFETY NET': 'MFUKO WA KINGA NA DHARURA',
      'Ubuntu Emergency Fund': 'Mfuko wa Dharura wa Ubuntu',
      'Medical, Legal, Bereavement & Repatriation':
          'Matibabu, Sheria, Msiba na Kusafirisha Mwili',
      'MARKETPLACE': 'SOKO LA BIASHARA',
      'Products': 'Bidhaa',
      'Buy from diaspora businesses': 'Nunua kutoka biashara za diaspora',
      'Services': 'Huduma',
      'Find diaspora services': 'Pata huduma za wanadiaspora',
      'Jobs': 'Ajira na Kazi',
      'Find jobs': 'Tafuta nafasi za kazi',
      'TRAVEL': 'USAFIRI NA MALAZI',
      'Flights': 'Safari za Ndege',
      'Book flights': 'Kata tiketi za ndege',
      'Hotels': 'Hoteli',
      'Find hotels': 'Tafuta hoteli',
      'Stays': 'Malazi ya Jamii',
      'Short-term stays': 'Malazi ya muda mfupi',
      'Car Rental': 'Kukodisha Magari',
      'Rent a car': 'Kodisha gari',
      'REAL ESTATE': 'ARDHI NA NYUMBA',
      'Land & Plots': 'Ardhi na Viwanja',
      'Farms': 'Mashamba',
      'Houses': 'Nyumba',
      'Rent, Lease or Buy': 'Panga, Kodisha au Nunua',
      'MY WALLET': 'POCHI YANGU',
      'Diaspora Social Points (DSP)': 'Pointi za Kijamii za Diaspora (DSP)',
      'Earn & convert to tokens': 'Kusanya na ubadilishe kuwa tokeni',
      r'$DIASPORA Token': r'Tokeni ya $DIASPORA',
      'Hold, Invest, Spend, Swap or Trade':
          'Hifadhi, Wekeza, Tumia, Badilisha au Fanya Biashara',
      'International Remittances': 'Kutuma Pesa Kimataifa',
      'Town DDI Loans': 'Mikopo ya Uwekezaji wa Mji (DDI)',
      'Country DDI Loans': 'Mikopo ya Uwekezaji wa Taifa (DDI)',
      'Coming Soon': 'Inakuja Hivi Karibuni',
      'QUICK ACTIONS': 'HATUA ZA HARAKA',
      'Invite family and friends': 'Alika familia na marafiki',
      'Share the app with others': 'Shiriki programu na wengine',
      'Send Feedback': 'Tuma Maoni',
      'Help us improve the app': 'Tusaidie kuboresha programu',
      'SUPPORT': 'MSAADA',
      'Rate App': 'Kadiria Programu',
      'Share your experience': 'Shiriki uzoefu wako',
      'Help Center': 'Kituo cha Msaada',
      'Get answers': 'Pata majibu',
      'ACCOUNT SETTINGS': 'MIPANGILIO YA AKAUNTI',
      'Push Notifications': 'Arifa za Simu',
      'Receive updates & alerts': 'Pokea taarifa na arifa za karibu',
      'Location Always': 'Mahali Muda Wote',
      'Allow background location updates':
          'Ruhusu utambuzi wa mahali ukiwa chinichini',
      'Manage notification preferences': 'Dhibiti mapendeleo ya arifa',
      'Privacy & Safety': 'Faragha na Usalama',
      'Control your privacy settings': 'Dhibiti mipangilio yako ya faragha',
      'Trust & Verification': 'Uaminifu na Uthibitisho',
      'View your Community Trust breakdown':
          'Angalia mchanganuo wa Uaminifu wa Jamii',
      'APP INFO': 'TAARIFA ZA PROGRAMU',
      'Log Out': 'Ondoka',
      'Sign out of your account': 'Ondoka kwenye akaunti yako',
      'Delete My Account': 'Futa Akaunti Yangu',
      'Permanently delete your account and data':
          'Futa kabisa akaunti na taarifa zako',
      'My Profile': 'Wasifu Wangu',
      'View & edit your profile': 'Angalia na uhariri wasifu wako',
      'Account, language, privacy & theme':
          'Akaunti, lugha, faragha na mwonekano',
      'QUICK SETTINGS': 'MIPANGILIO YA HARAKA',
      'Search chats...': 'Tafuta mazungumzo...',
      'Search nearby people...': 'Tafuta watu walio karibu...',
      'Search events...': 'Tafuta matukio...',
      'Search communities...': 'Tafuta jumuiya...',
      'Search radio stations...': 'Tafuta vituo vya redio...',
      'All Nearby Members Connected': 'Wanajamii Wote wa Karibu Wameunganishwa',
      'You are already in active chats with all nearby community members in your area.':
          'Tayari uko kwenye mazungumzo na wanajamii wote walio karibu na eneo lako.',
      'View Active Chats': 'Angalia Mazungumzo Yanayoendelea',
      'Refresh Location': 'Sasisha Mahali',
    },
    'fr': {
      'Diaspora Ecosystem': 'Écosystème Diaspora',
      'Chats': 'Discussions',
      'Nearby': 'À proximité',
      'Events': 'Événements',
      'Communities': 'Communautés',
      'Radio': 'Radio',
      'Settings': 'Paramètres',
      'Profile': 'Profil',
      'Edit': 'Modifier',
      'Edit Profile': 'Modifier le profil',
      'Save': 'Enregistrer',
      'Cancel': 'Annuler',
      'Close': 'Fermer',
      'App Language': 'Langue de l\'application',
      'Select World Language': 'Choisir la langue mondiale',
      'All main official languages of every country in the world':
          'Toutes les principales langues officielles de chaque pays du monde',
      'Choose from official languages of all countries':
          'Choisir parmi les langues officielles de tous les pays',
      'Select Language': 'Choisir la langue',
      'Search country (e.g. Tanzania, Brazil) or language...':
          'Rechercher un pays (ex. Tanzanie, Brésil) ou une langue...',
      'Search country or language...': 'Rechercher un pays ou une langue...',
      'All Official Languages': 'Toutes les langues officielles',
      'All Languages': 'Toutes les langues',
      'By Country': 'Par pays',
      'Recommended for Your Countries': 'Recommandé pour vos pays',
      'No matching languages or countries found.':
          'Aucune langue ou pays correspondant trouvé.',
      'No matching countries found.': 'Aucun pays correspondant trouvé.',
      'Theme Mode': 'Mode de thème',
      'Light': 'Clair',
      'Dark': 'Sombre',
      'System': 'Système',
      'Light Mode': 'Mode clair',
      'Dark Mode': 'Mode sombre',
      'System Default': 'Par défaut du système',
      'SAFETY NET': 'FILET DE SÉCURITÉ',
      'Ubuntu Emergency Fund': 'Fonds d\'urgence Ubuntu',
      'Medical, Legal, Bereavement & Repatriation':
          'Médical, juridique, deuil et rapatriement',
      'MARKETPLACE': 'MARCHÉ',
      'Products': 'Produits',
      'Buy from diaspora businesses':
          'Acheter auprès d\'entreprises de la diaspora',
      'Services': 'Services',
      'Find diaspora services': 'Trouver des services de la diaspora',
      'Jobs': 'Emplois',
      'Find jobs': 'Trouver un emploi',
      'TRAVEL': 'VOYAGES',
      'Flights': 'Vols',
      'Book flights': 'Réserver des vols',
      'Hotels': 'Hôtels',
      'Find hotels': 'Trouver des hôtels',
      'Stays': 'Séjours',
      'Short-term stays': 'Locations de courte durée',
      'Car Rental': 'Location de voitures',
      'Rent a car': 'Louer une voiture',
      'REAL ESTATE': 'IMMOBILIER',
      'Land & Plots': 'Terrains et parcelles',
      'Farms': 'Fermes et terres agricoles',
      'Houses': 'Maisons',
      'Rent, Lease or Buy': 'Louer, prendre à bail ou acheter',
      'MY WALLET': 'MON PORTEFEUILLE',
      'Diaspora Social Points (DSP)': 'Points Sociaux Diaspora (DSP)',
      'Earn & convert to tokens': 'Gagner et convertir en jetons',
      r'$DIASPORA Token': r'Jeton $DIASPORA',
      'Hold, Invest, Spend, Swap or Trade':
          'Détenir, investir, dépenser, échanger',
      'International Remittances': 'Transferts internationaux',
      'Town DDI Loans': 'Prêts DDI municipaux',
      'Country DDI Loans': 'Prêts DDI nationaux',
      'Coming Soon': 'Bientôt disponible',
      'QUICK ACTIONS': 'ACTIONS RAPIDES',
      'Invite family and friends': 'Inviter famille et amis',
      'Share the app with others': 'Partager l\'application',
      'Send Feedback': 'Envoyer des commentaires',
      'Help us improve the app': 'Aidez-nous à améliorer l\'application',
      'SUPPORT': 'ASSISTANCE',
      'Rate App': 'Noter l\'application',
      'Share your experience': 'Partagez votre expérience',
      'Help Center': 'Centre d\'aide',
      'Get answers': 'Obtenir des réponses',
      'ACCOUNT SETTINGS': 'PARAMÈTRES DU COMPTE',
      'Push Notifications': 'Notifications push',
      'Receive updates & alerts': 'Recevoir les mises à jour et alertes',
      'Location Always': 'Localisation permanente',
      'Allow background location updates':
          'Autoriser la localisation en arrière-plan',
      'Manage notification preferences':
          'Gérer les préférences de notification',
      'Privacy & Safety': 'Confidentialité et sécurité',
      'Control your privacy settings':
          'Contrôler vos paramètres de confidentialité',
      'Trust & Verification': 'Confiance et vérification',
      'View your Community Trust breakdown':
          'Voir le détail de votre confiance communautaire',
      'APP INFO': 'INFOS APPLICATION',
      'Log Out': 'Se déconnecter',
      'Sign out of your account': 'Se déconnecter de votre compte',
      'Delete My Account': 'Supprimer mon compte',
      'Permanently delete your account and data':
          'Supprimer définitivement votre compte et vos données',
      'My Profile': 'Mon profil',
      'View & edit your profile': 'Voir et modifier votre profil',
      'Account, language, privacy & theme':
          'Compte, langue, confidentialité et thème',
      'QUICK SETTINGS': 'PARAMÈTRES RAPIDES',
      'Search chats...': 'Rechercher des discussions...',
      'Search nearby people...': 'Rechercher des personnes à proximité...',
      'Search events...': 'Rechercher des événements...',
      'Search communities...': 'Rechercher des communautés...',
      'Search radio stations...': 'Rechercher des stations de radio...',
      'All Nearby Members Connected': 'Tous les membres proches sont connectés',
      'You are already in active chats with all nearby community members in your area.':
          'Vous discutez déjà avec tous les membres de la communauté à proximité.',
      'View Active Chats': 'Voir les discussions actives',
      'Refresh Location': 'Actualiser la position',
    },
    'es': {
      'Diaspora Ecosystem': 'Ecosistema de la Diáspora',
      'Chats': 'Chats',
      'Nearby': 'Cerca',
      'Events': 'Eventos',
      'Communities': 'Comunidades',
      'Radio': 'Radio',
      'Settings': 'Configuración',
      'Profile': 'Perfil',
      'Edit': 'Editar',
      'Edit Profile': 'Editar perfil',
      'Save': 'Guardar',
      'Cancel': 'Cancelar',
      'Close': 'Cerrar',
      'App Language': 'Idioma de la aplicación',
      'Select World Language': 'Seleccionar idioma del mundo',
      'All main official languages of every country in the world':
          'Todos los idiomas oficiales principales de cada país del mundo',
      'Choose from official languages of all countries':
          'Elige entre los idiomas oficiales de todos los países',
      'Select Language': 'Seleccionar idioma',
      'Search country (e.g. Tanzania, Brazil) or language...':
          'Buscar país (ej. Tanzania, Brasil) o idioma...',
      'Search country or language...': 'Buscar país o idioma...',
      'All Official Languages': 'Todos los idiomas oficiales',
      'All Languages': 'Todos los idiomas',
      'By Country': 'Por país',
      'Recommended for Your Countries': 'Recomendado para tus países',
      'No matching languages or countries found.':
          'No se encontraron idiomas o países coincidentes.',
      'No matching countries found.': 'No se encontraron países coincidentes.',
      'Theme Mode': 'Modo de tema',
      'Light': 'Claro',
      'Dark': 'Oscuro',
      'System': 'Sistema',
      'Light Mode': 'Modo claro',
      'Dark Mode': 'Modo oscuro',
      'System Default': 'Predeterminado del sistema',
      'SAFETY NET': 'RED DE SEGURIDAD',
      'Ubuntu Emergency Fund': 'Fondo de Emergencia Ubuntu',
      'Medical, Legal, Bereavement & Repatriation':
          'Médico, legal, duelo y repatriación',
      'MARKETPLACE': 'MERCADO',
      'Products': 'Productos',
      'Buy from diaspora businesses': 'Compra en negocios de la diáspora',
      'Services': 'Servicios',
      'Find diaspora services': 'Encuentra servicios de la diáspora',
      'Jobs': 'Empleos',
      'Find jobs': 'Buscar empleos',
      'TRAVEL': 'VIAJES',
      'Flights': 'Vuelos',
      'Book flights': 'Reservar vuelos',
      'Hotels': 'Hoteles',
      'Find hotels': 'Buscar hoteles',
      'Stays': 'Alojamientos',
      'Short-term stays': 'Estancias cortas',
      'Car Rental': 'Alquiler de autos',
      'Rent a car': 'Alquilar un auto',
      'REAL ESTATE': 'BIENES RAÍCES',
      'Land & Plots': 'Terrenos y parcelas',
      'Farms': 'Granjas y fincas',
      'Houses': 'Casas',
      'Rent, Lease or Buy': 'Alquilar, arrendar o comprar',
      'MY WALLET': 'MI BILLETERA',
      'Diaspora Social Points (DSP)': 'Puntos Sociales de la Diáspora (DSP)',
      'Earn & convert to tokens': 'Gana y convierte en tokens',
      r'$DIASPORA Token': r'Token $DIASPORA',
      'Hold, Invest, Spend, Swap or Trade':
          'Guardar, invertir, gastar o intercambiar',
      'International Remittances': 'Remesas internacionales',
      'Town DDI Loans': 'Prêts DDI municipales',
      'Country DDI Loans': 'Préstamos DDI nacionales',
      'Coming Soon': 'Próximamente',
      'QUICK ACTIONS': 'ACCIONES RÁPIDAS',
      'Invite family and friends': 'Invitar a familiares y amigos',
      'Share the app with others': 'Compartir la aplicación',
      'Send Feedback': 'Enviar comentarios',
      'Help us improve the app': 'Ayúdanos a mejorar la aplicación',
      'SUPPORT': 'SOPORTE',
      'Rate App': 'Calificar aplicación',
      'Share your experience': 'Comparte tu experiencia',
      'Help Center': 'Centro de ayuda',
      'Get answers': 'Obtener respuestas',
      'ACCOUNT SETTINGS': 'CONFIGURACIÓN DE LA CUENTA',
      'Push Notifications': 'Notificaciones push',
      'Receive updates & alerts': 'Recibir actualizaciones y alertas',
      'Location Always': 'Ubicación siempre activa',
      'Allow background location updates':
          'Permitir ubicación en segundo plano',
      'Manage notification preferences':
          'Administrar preferencias de notificación',
      'Privacy & Safety': 'Privacidad y seguridad',
      'Control your privacy settings':
          'Controla tu configuración de privacidad',
      'Trust & Verification': 'Confianza y verificación',
      'View your Community Trust breakdown':
          'Ver el desglose de confianza comunitaria',
      'APP INFO': 'INFORMACIÓN DE LA APP',
      'Log Out': 'Cerrar sesión',
      'Sign out of your account': 'Salir de tu cuenta',
      'Delete My Account': 'Eliminar mi cuenta',
      'Permanently delete your account and data':
          'Eliminar permanentemente tu cuenta y datos',
      'My Profile': 'Mi perfil',
      'View & edit your profile': 'Ver y editar tu perfil',
      'Account, language, privacy & theme': 'Cuenta, idioma, privacidad y tema',
      'QUICK SETTINGS': 'AJUSTES RÁPIDOS',
      'Search chats...': 'Buscar chats...',
      'Search nearby people...': 'Buscar personas cercanas...',
      'Search events...': 'Buscar eventos...',
      'Search communities...': 'Buscar comunidades...',
      'Search radio stations...': 'Buscar estaciones de radio...',
      'Refresh Location': 'Actualizar ubicación',
    },
    'pt': {
      'Diaspora Ecosystem': 'Ecossistema da Diáspora',
      'Chats': 'Conversas',
      'Nearby': 'Próximos',
      'Events': 'Eventos',
      'Communities': 'Comunidades',
      'Radio': 'Rádio',
      'Settings': 'Configurações',
      'Profile': 'Perfil',
      'Edit': 'Editar',
      'Edit Profile': 'Editar perfil',
      'Save': 'Salvar',
      'Cancel': 'Cancelar',
      'Close': 'Fechar',
      'App Language': 'Idioma do aplicativo',
      'Select World Language': 'Selecionar idioma mundial',
      'All main official languages of every country in the world':
          'Todos os principais idiomas oficiais de cada país do mundo',
      'Choose from official languages of all countries':
          'Escolha entre os idiomas oficiais de todos os países',
      'Select Language': 'Selecionar idioma',
      'Search country (e.g. Tanzania, Brazil) or language...':
          'Pesquisar país (ex. Tanzânia, Brasil) ou idioma...',
      'Search country or language...': 'Pesquisar país ou idioma...',
      'All Official Languages': 'Todos os idiomas oficiais',
      'All Languages': 'Todos os idiomas',
      'By Country': 'Por país',
      'Recommended for Your Countries': 'Recomendado para seus países',
      'Theme Mode': 'Modo de tema',
      'Light': 'Claro',
      'Dark': 'Escuro',
      'System': 'Sistema',
      'Light Mode': 'Modo claro',
      'Dark Mode': 'Modo escuro',
      'System Default': 'Padrão do sistema',
      'SAFETY NET': 'REDE DE PROTEÇÃO',
      'Ubuntu Emergency Fund': 'Fundo de Emergência Ubuntu',
      'Medical, Legal, Bereavement & Repatriation':
          'Médico, jurídico, luto e repatriação',
      'MARKETPLACE': 'MERCADO',
      'Products': 'Produtos',
      'Buy from diaspora businesses': 'Compre de empresas da diáspora',
      'Services': 'Serviços',
      'Find diaspora services': 'Encontre serviços da diáspora',
      'Jobs': 'Vagas de emprego',
      'Find jobs': 'Encontrar empregos',
      'TRAVEL': 'VIAGENS',
      'Flights': 'Voos',
      'Book flights': 'Reservar voos',
      'Hotels': 'Hotéis',
      'Find hotels': 'Encontrar hotéis',
      'Stays': 'Hospedagens',
      'Short-term stays': 'Estadias de curta duração',
      'Car Rental': 'Aluguel de carros',
      'Rent a car': 'Alugar um carro',
      'REAL ESTATE': 'IMÓVEIS',
      'Land & Plots': 'Terrenos e lotes',
      'Farms': 'Fazendas e sítios',
      'Houses': 'Casas',
      'Rent, Lease or Buy': 'Alugar, arrendar ou comprar',
      'MY WALLET': 'MINHA CARTEIRA',
      'Diaspora Social Points (DSP)': 'Pontos Sociais da Diáspora (DSP)',
      'Earn & convert to tokens': 'Ganhe e converta em tokens',
      r'$DIASPORA Token': r'Token $DIASPORA',
      'Hold, Invest, Spend, Swap or Trade':
          'Guardar, investir, gastar ou negociar',
      'Coming Soon': 'Em breve',
      'QUICK ACTIONS': 'AÇÕES RÁPIDAS',
      'Invite family and friends': 'Convidar família e amigos',
      'Share the app with others': 'Compartilhar o aplicativo',
      'Send Feedback': 'Enviar comentários',
      'Help us improve the app': 'Ajude-nos a melhorar o aplicativo',
      'SUPPORT': 'SUPORTE',
      'Rate App': 'Avaliar aplicativo',
      'Share your experience': 'Compartilhe sua experiência',
      'Help Center': 'Central de ajuda',
      'Get answers': 'Obter respostas',
      'ACCOUNT SETTINGS': 'CONFIGURAÇÕES DA CONTA',
      'Push Notifications': 'Notificações push',
      'Receive updates & alerts': 'Receber atualizações e alertas',
      'Location Always': 'Localização sempre ativa',
      'Allow background location updates':
          'Permitir atualizações de localização em segundo plano',
      'Manage notification preferences':
          'Gerenciar preferências de notificação',
      'Privacy & Safety': 'Privacidade e segurança',
      'Control your privacy settings':
          'Controle suas configurações de privacidade',
      'Trust & Verification': 'Confiança e verificação',
      'View your Community Trust breakdown':
          'Ver detalhes da confiança comunitária',
      'APP INFO': 'INFO DO APP',
      'Log Out': 'Sair',
      'Sign out of your account': 'Sair da sua conta',
      'Delete My Account': 'Excluir minha conta',
      'Permanently delete your account and data':
          'Excluir permanentemente sua conta e dados',
      'My Profile': 'Meu perfil',
      'View & edit your profile': 'Ver e editar seu perfil',
      'Account, language, privacy & theme': 'Conta, idioma, privacidade e tema',
      'QUICK SETTINGS': 'CONFIGURAÇÕES RÁPIDAS',
    },
    'ar': {
      'Diaspora Ecosystem': 'منظومة الدياسبورا',
      'Chats': 'المحادثات',
      'Nearby': 'بالقرب مني',
      'Events': 'الفعاليات',
      'Communities': 'المجتمعات',
      'Radio': 'الراديو',
      'Settings': 'الإعدادات',
      'Profile': 'الملف الشخصي',
      'Edit': 'تعديل',
      'Edit Profile': 'تعديل الملف الشخصي',
      'Save': 'حفظ',
      'Cancel': 'إلغاء',
      'Close': 'إغلاق',
      'App Language': 'لغة التطبيق',
      'Select World Language': 'اختر لغة العالم',
      'All main official languages of every country in the world':
          'جميع اللغات الرسمية الرئيسية لكل دولة في العالم',
      'Choose from official languages of all countries':
          'اختر من اللغات الرسمية لجميع البلدان',
      'Select Language': 'اختر اللغة',
      'Search country (e.g. Tanzania, Brazil) or language...':
          'ابحث عن دولة (مثل تنزانيا، البرازيل) أو لغة...',
      'Search country or language...': 'ابحث عن دولة أو لغة...',
      'All Official Languages': 'جميع اللغات الرسمية',
      'All Languages': 'جميع اللغات',
      'By Country': 'حسب الدولة',
      'Recommended for Your Countries': 'موصى به لبلدانك',
      'Theme Mode': 'وضع المظهر',
      'Light': 'فاتح',
      'Dark': 'داكن',
      'System': 'النظام',
      'Light Mode': 'الوضع الفاتح',
      'Dark Mode': 'الوضع الداكن',
      'System Default': 'افتراضي النظام',
      'SAFETY NET': 'شبكة الأمان',
      'Ubuntu Emergency Fund': 'صندوق طوارئ أوبونتو',
      'Medical, Legal, Bereavement & Repatriation':
          'الطوارئ الطبية والقانونية والعزاء وإعادة الجثمان',
      'MARKETPLACE': 'السوق',
      'Products': 'المنتجات',
      'Buy from diaspora businesses': 'اشترِ من شركات المغتربين',
      'Services': 'الخدمات',
      'Find diaspora services': 'اعثر على خدمات المغتربين',
      'Jobs': 'الوظائف',
      'Find jobs': 'ابحث عن وظائف',
      'TRAVEL': 'السفر',
      'Flights': 'رحلات الطيران',
      'Book flights': 'حجز رحلات الطيران',
      'Hotels': 'الفنادق',
      'Find hotels': 'البحث عن فنادق',
      'Stays': 'الإقامات',
      'Short-term stays': 'إقامات قصيرة المدى',
      'Car Rental': 'تأجير السيارات',
      'Rent a car': 'استأجر سيارة',
      'REAL ESTATE': 'العقارات',
      'Land & Plots': 'الأراضي والقطع',
      'Farms': 'المزارع',
      'Houses': 'المنازل',
      'Rent, Lease or Buy': 'استئجار أو تأجير أو شراء',
      'MY WALLET': 'محفظتي',
      'Diaspora Social Points (DSP)': 'نقاط الدياسبورا الاجتماعية (DSP)',
      'Earn & convert to tokens': 'اكسب وحوّل إلى عملات رقمية',
      r'$DIASPORA Token': r'عملة $DIASPORA',
      'Hold, Invest, Spend, Swap or Trade': 'احتفظ أو استثمر أو أنفق أو تداول',
      'Coming Soon': 'قريباً',
      'QUICK ACTIONS': 'إجراءات سريعة',
      'Invite family and friends': 'دعوة العائلة والأصدقاء',
      'Share the app with others': 'مشاركة التطبيق مع الآخرين',
      'Send Feedback': 'إرسال ملاحظات',
      'Help us improve the app': 'ساعدنا في تحسين التطبيق',
      'SUPPORT': 'الدعم',
      'Rate App': 'تقييم التطبيق',
      'Share your experience': 'شارك تجربتك',
      'Help Center': 'مركز المساعدة',
      'Get answers': 'احصل على إجابات',
      'ACCOUNT SETTINGS': 'إعدادات الحساب',
      'Push Notifications': 'الإشعارات الفورية',
      'Receive updates & alerts': 'تلقي التحديثات والتنبيهات',
      'Location Always': 'الموقع دائماً',
      'Allow background location updates':
          'السماح بتحديثات الموقع في الخلفية',
      'Manage notification preferences': 'إدارة تفضيلات الإشعارات',
      'Privacy & Safety': 'الخصوصية والأمان',
      'Control your privacy settings': 'التحكم في إعدادات الخصوصية',
      'Trust & Verification': 'الثقة والتحقق',
      'View your Community Trust breakdown': 'عرض تفاصيل ثقة المجتمع',
      'APP INFO': 'معلومات التطبيق',
      'Log Out': 'تسجيل الخروج',
      'Sign out of your account': 'الخروج من حسابك',
      'Delete My Account': 'حذف حسابي',
      'Permanently delete your account and data': 'حذف حسابك وبياناتك نهائياً',
      'My Profile': 'ملفي الشخصي',
      'View & edit your profile': 'عرض وتعديل ملفك الشخصي',
      'Account, language, privacy & theme': 'الحساب، اللغة، الخصوصية والمظهر',
      'QUICK SETTINGS': 'إعدادات سريعة',
    },
    'am': {
      'Diaspora Ecosystem': 'የዲያስፖራ ስነ-ምህዳር',
      'Chats': 'ውይይቶች',
      'Nearby': 'በአቅራቢያ',
      'Events': 'ዝግጅቶች',
      'Communities': 'ማህበረሰቦች',
      'Radio': 'ሬዲዮ',
      'Settings': 'ቅንብሮች',
      'Profile': 'መገለጫ',
      'Edit': 'አርትዕ',
      'Edit Profile': 'መገለጫ አርትዕ',
      'Save': 'አስቀምጥ',
      'App Language': 'የመተግበሪያ ቋንቋ',
      'Select World Language': 'የዓለም ቋንቋ ይምረጡ',
      'Choose from official languages of all countries':
          'ከሁሉም ሀገራት ይፋዊ ቋንቋዎች ይምረጡ',
      'Select Language': 'ቋንቋ ይምረጡ',
      'Search country or language...': 'ሀገር ወይም ቋንቋ ይፈልጉ...',
      'All Official Languages': 'ሁሉም ይፋዊ ቋንቋዎች',
      'All Languages': 'ሁሉም ቋንቋዎች',
      'By Country': 'በሀገር',
      'Recommended for Your Countries': 'ለእርስዎ ሀገራት የሚመከር',
      'My Profile': 'የእኔ መገለጫ',
      'Log Out': 'ውጣ',
      'Theme Mode': 'የገጽታ ሁኔታ',
      'Light': 'ብሩህ',
      'Dark': 'ጨለማ',
      'System': 'ሲስተም',
    },
    'hi': {
      'Diaspora Ecosystem': 'डायस्पोरा इकोसिस्टम',
      'Chats': 'चैट',
      'Nearby': 'आस-पास',
      'Events': 'इवेंट्स',
      'Communities': 'समुदाय',
      'Radio': 'रेडियो',
      'Settings': 'सेटिंग्स',
      'Profile': 'प्रोफ़ाइल',
      'Edit': 'संपादित करें',
      'Edit Profile': 'प्रोफ़ाइल संपादित करें',
      'Save': 'सहेजें',
      'App Language': 'ऐप की भाषा',
      'Select World Language': 'विश्व भाषा चुनें',
      'Choose from official languages of all countries':
          'सभी देशों की आधिकारिक भाषाओं में से चुनें',
      'Select Language': 'भाषा चुनें',
      'Search country or language...': 'देश या भाषा खोजें...',
      'All Official Languages': 'सभी आधिकारिक भाषाएँ',
      'All Languages': 'सभी भाषाएँ',
      'By Country': 'देश के अनुसार',
      'Recommended for Your Countries': 'आपके देशों के लिए अनुशंसित',
      'My Profile': 'मेरी प्रोफ़ाइल',
      'Log Out': 'लॉग आउट',
      'Theme Mode': 'थीम मोड',
      'Light': 'लाइट',
      'Dark': 'डार्क',
      'System': 'सिस्टम',
    },
    'zh': {
      'Diaspora Ecosystem': '侨民生态系统',
      'Chats': '聊天',
      'Nearby': '附近',
      'Events': '活动',
      'Communities': '社区',
      'Radio': '电台',
      'Settings': '设置',
      'Profile': '个人资料',
      'Edit': '编辑',
      'Edit Profile': '编辑资料',
      'Save': '保存',
      'App Language': '应用语言',
      'Select World Language': '选择世界语言',
      'All main official languages of every country in the world':
          '全球各国的所有主要官方语言',
      'Choose from official languages of all countries': '从所有国家的官方语言中选择',
      'Select Language': '选择语言',
      'Search country or language...': '搜索国家或语言...',
      'All Official Languages': '所有官方语言',
      'All Languages': '所有语言',
      'By Country': '按国家/地区',
      'Recommended for Your Countries': '为您所在国家/地区推荐',
      'My Profile': '我的资料',
      'Log Out': '退出登录',
      'Theme Mode': '主题模式',
      'Light': '浅色',
      'Dark': '深色',
      'System': '跟随系统',
      'SAFETY NET': '安全保障',
      'Ubuntu Emergency Fund': 'Ubuntu 应急互助基金',
      'MARKETPLACE': '市场',
      'Products': '商品',
      'Services': '服务',
      'Jobs': '工作机会',
      'TRAVEL': '旅行与住宿',
      'Flights': '机票',
      'Hotels': '酒店',
      'Stays': '民宿短租',
      'Car Rental': '租车',
      'REAL ESTATE': '房地产',
      'Land & Plots': '土地与地块',
      'Farms': '农场',
      'Houses': '房屋',
      'MY WALLET': '我的钱包',
      'QUICK SETTINGS': '快捷设置',
    },
    'de': {
      'Diaspora Ecosystem': 'Diaspora-Ökosystem',
      'Chats': 'Chats',
      'Nearby': 'In der Nähe',
      'Events': 'Events',
      'Communities': 'Gemeinschaften',
      'Radio': 'Radio',
      'Settings': 'Einstellungen',
      'Profile': 'Profil',
      'Edit': 'Bearbeiten',
      'Edit Profile': 'Profil bearbeiten',
      'Save': 'Speichern',
      'App Language': 'App-Sprache',
      'Select World Language': 'Weltsprache auswählen',
      'Choose from official languages of all countries':
          'Aus den Amtssprachen aller Länder wählen',
      'Select Language': 'Sprache auswählen',
      'Search country or language...': 'Land oder Sprache suchen...',
      'All Official Languages': 'Alle Amtssprachen',
      'All Languages': 'Alle Sprachen',
      'By Country': 'Nach Land',
      'Recommended for Your Countries': 'Empfohlen für Ihre Länder',
      'My Profile': 'Mein Profil',
      'Log Out': 'Abmelden',
      'Theme Mode': 'Designmodus',
      'Light': 'Hell',
      'Dark': 'Dunkel',
      'System': 'System',
    },
    'ru': {
      'Diaspora Ecosystem': 'Экосистема Диаспоры',
      'Chats': 'Чаты',
      'Nearby': 'Рядом',
      'Events': 'События',
      'Communities': 'Сообщества',
      'Radio': 'Радио',
      'Settings': 'Настройки',
      'Profile': 'Профиль',
      'Edit': 'Изменить',
      'Edit Profile': 'Редактировать профиль',
      'Save': 'Сохранить',
      'App Language': 'Язык приложения',
      'Select World Language': 'Выберите мировой язык',
      'Choose from official languages of all countries':
          'Выберите из официальных языков всех стран',
      'Select Language': 'Выберите язык',
      'Search country or language...': 'Поиск страны или языка...',
      'All Official Languages': 'Все официальные языки',
      'All Languages': 'Все языки',
      'By Country': 'По странам',
      'Recommended for Your Countries': 'Рекомендуется для ваших стран',
      'My Profile': 'Мой профиль',
      'Log Out': 'Выйти',
      'Theme Mode': 'Тема оформления',
      'Light': 'Светлая',
      'Dark': 'Тёмная',
      'System': 'Системная',
    },
  };
}
