import 'package:cross_file/cross_file.dart';

/// Resolved metadata for a media or document upload so Firebase Storage
/// security rules (`isImage()`, `video/.*`, `audio/.*`, non-HTML/SVG document)
/// and browser `Content-Type` headers are always accurate across Android, iOS,
/// and Web (`XFile.fromData` / `blob:` URLs).
class ResolvedMediaInfo {
  final String extension;
  final String contentType;
  final String cleanFileName;
  final String storageSafeBaseName;

  const ResolvedMediaInfo({
    required this.extension,
    required this.contentType,
    required this.cleanFileName,
    required this.storageSafeBaseName,
  });
}

class MediaUploadHelper {
  MediaUploadHelper._();

  static String _extractCandidateName(XFile file) {
    final explicitName = file.name.trim();
    if (explicitName.isNotEmpty &&
        !explicitName.startsWith('blob:') &&
        !explicitName.contains('://')) {
      return explicitName.split(RegExp(r'[/\\]')).last;
    }

    final rawPath = file.path.trim();
    if (rawPath.isNotEmpty && !rawPath.startsWith('blob:')) {
      final cleanPath = rawPath.split('?').first.split('#').first;
      final segment = cleanPath.split(RegExp(r'[/\\]')).last;
      if (segment.isNotEmpty) {
        return segment;
      }
    }
    return '';
  }

  static String _extractExtension(String fileNameOrPath) {
    final clean = fileNameOrPath.trim().split('?').first.split('#').first;
    final lastSegment = clean.split(RegExp(r'[/\\]')).last;
    final dotIndex = lastSegment.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == lastSegment.length - 1) {
      return '';
    }
    final ext = lastSegment.substring(dotIndex).toLowerCase();
    if (ext.length > 10 || !RegExp(r'^\.[a-z0-9]+$').hasMatch(ext)) {
      return '';
    }
    return ext;
  }

  static String _sanitizeStorageSegment(String input, String fallback) {
    final sanitized = input
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      return fallback;
    }
    return sanitized.length > 100 ? sanitized.substring(0, 100) : sanitized;
  }

  /// Resolves extension, MIME `contentType`, and display filename for an [XFile].
  ///
  /// [category] should be `'image'`, `'video'`, `'audio'`, `'audio_file'`, or `'document'`.
  /// [explicitFileName] optionally supplies a known filename when `XFile.fromData`
  /// on Dart IO leaves `file.name` and `file.path` empty.
  static ResolvedMediaInfo resolve(
    XFile file,
    String category, {
    String? explicitFileName,
  }) {
    final rawMime = (file.mimeType ?? '').trim().toLowerCase();
    final explicitTrimmed = (explicitFileName ?? '').trim();
    final candidateName = explicitTrimmed.isNotEmpty
        ? explicitTrimmed.split(RegExp(r'[/\\]')).last
        : _extractCandidateName(file);
    var ext = _extractExtension(candidateName);
    if (ext.isEmpty) {
      ext = _extractExtension(file.path);
    }

    switch (category) {
      case 'image':
        return _resolveImage(rawMime, ext, candidateName);
      case 'video':
        return _resolveVideo(rawMime, ext, candidateName);
      case 'audio':
      case 'audio_file':
        return _resolveAudio(rawMime, ext, candidateName);
      default:
        return _resolveDocument(rawMime, ext, candidateName);
    }
  }

  static ResolvedMediaInfo _resolveImage(
    String rawMime,
    String ext,
    String candidateName,
  ) {
    String resolvedExt = ext;
    String resolvedMime = '';

    if (rawMime == 'image/png' || ext == '.png') {
      resolvedExt = '.png';
      resolvedMime = 'image/png';
    } else if (rawMime == 'image/webp' || ext == '.webp') {
      resolvedExt = '.webp';
      resolvedMime = 'image/webp';
    } else if (rawMime == 'image/gif' || ext == '.gif') {
      resolvedExt = '.gif';
      resolvedMime = 'image/gif';
    } else if (rawMime == 'image/heic' ||
        rawMime == 'image/heif' ||
        ext == '.heic' ||
        ext == '.heif') {
      resolvedExt = ext == '.heif' ? '.heif' : '.heic';
      resolvedMime = rawMime.startsWith('image/') ? rawMime : 'image/heic';
    } else if (rawMime.startsWith('image/') && rawMime != 'image/svg+xml') {
      resolvedMime = rawMime;
      if (resolvedExt.isEmpty) {
        resolvedExt = '.jpg';
      }
    } else {
      resolvedExt = (ext == '.jpeg') ? '.jpeg' : '.jpg';
      resolvedMime = 'image/jpeg';
    }

    final cleanName = candidateName.isNotEmpty
        ? candidateName
        : 'photo$resolvedExt';
    return ResolvedMediaInfo(
      extension: resolvedExt,
      contentType: resolvedMime,
      cleanFileName: cleanName,
      storageSafeBaseName: _sanitizeStorageSegment(cleanName, 'image'),
    );
  }

  static ResolvedMediaInfo _resolveVideo(
    String rawMime,
    String ext,
    String candidateName,
  ) {
    String resolvedExt = ext;
    String resolvedMime = '';

    if (rawMime == 'video/quicktime' || ext == '.mov') {
      resolvedExt = '.mov';
      resolvedMime = 'video/quicktime';
    } else if (rawMime == 'video/webm' || ext == '.webm') {
      resolvedExt = '.webm';
      resolvedMime = 'video/webm';
    } else if (rawMime == 'video/x-matroska' || ext == '.mkv') {
      resolvedExt = '.mkv';
      resolvedMime = 'video/x-matroska';
    } else if (rawMime == 'video/3gpp' || ext == '.3gp') {
      resolvedExt = '.3gp';
      resolvedMime = 'video/3gpp';
    } else if (rawMime.startsWith('video/')) {
      resolvedMime = rawMime;
      if (resolvedExt.isEmpty) resolvedExt = '.mp4';
    } else {
      resolvedExt = '.mp4';
      resolvedMime = 'video/mp4';
    }

    final cleanName = candidateName.isNotEmpty
        ? candidateName
        : 'video$resolvedExt';
    return ResolvedMediaInfo(
      extension: resolvedExt,
      contentType: resolvedMime,
      cleanFileName: cleanName,
      storageSafeBaseName: _sanitizeStorageSegment(cleanName, 'video'),
    );
  }

  static ResolvedMediaInfo _resolveAudio(
    String rawMime,
    String ext,
    String candidateName,
  ) {
    String resolvedExt = ext;
    String resolvedMime = '';

    if (rawMime == 'audio/mpeg' || rawMime == 'audio/mp3' || ext == '.mp3') {
      resolvedExt = '.mp3';
      resolvedMime = 'audio/mpeg';
    } else if (rawMime == 'audio/wav' ||
        rawMime == 'audio/x-wav' ||
        rawMime == 'audio/wave' ||
        ext == '.wav') {
      resolvedExt = '.wav';
      resolvedMime = 'audio/wav';
    } else if (rawMime == 'audio/aac' || ext == '.aac') {
      resolvedExt = '.aac';
      resolvedMime = 'audio/aac';
    } else if (rawMime == 'audio/ogg' ||
        rawMime == 'audio/opus' ||
        ext == '.ogg' ||
        ext == '.opus') {
      resolvedExt = ext == '.opus' ? '.opus' : '.ogg';
      resolvedMime = 'audio/ogg';
    } else if (rawMime == 'audio/webm' || ext == '.webm') {
      resolvedExt = '.webm';
      resolvedMime = 'audio/webm';
    } else if (rawMime == 'audio/mp4' ||
        rawMime == 'audio/x-m4a' ||
        rawMime == 'audio/m4a' ||
        ext == '.m4a' ||
        ext == '.mp4') {
      resolvedExt = ext == '.mp4' ? '.mp4' : '.m4a';
      resolvedMime = 'audio/mp4';
    } else if (rawMime.startsWith('audio/')) {
      resolvedMime = rawMime;
      if (resolvedExt.isEmpty) resolvedExt = '.m4a';
    } else {
      if (resolvedExt.isEmpty) resolvedExt = '.m4a';
      resolvedMime = 'audio/mp4';
    }

    final cleanName = candidateName.isNotEmpty
        ? candidateName
        : 'audio$resolvedExt';
    return ResolvedMediaInfo(
      extension: resolvedExt,
      contentType: resolvedMime,
      cleanFileName: cleanName,
      storageSafeBaseName: _sanitizeStorageSegment(cleanName, 'audio'),
    );
  }

  static ResolvedMediaInfo _resolveDocument(
    String rawMime,
    String ext,
    String candidateName,
  ) {
    String resolvedExt = ext;
    String resolvedMime = '';

    switch (ext) {
      case '.pdf':
        resolvedMime = 'application/pdf';
        break;
      case '.doc':
        resolvedMime = 'application/msword';
        break;
      case '.docx':
        resolvedMime =
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        break;
      case '.xls':
        resolvedMime = 'application/vnd.ms-excel';
        break;
      case '.xlsx':
        resolvedMime =
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        break;
      case '.ppt':
        resolvedMime = 'application/vnd.ms-powerpoint';
        break;
      case '.pptx':
        resolvedMime =
            'application/vnd.openxmlformats-officedocument.presentationml.presentation';
        break;
      case '.txt':
        resolvedMime = 'text/plain';
        break;
      case '.csv':
        resolvedMime = 'text/csv';
        break;
      case '.json':
        resolvedMime = 'application/json';
        break;
      case '.zip':
        resolvedMime = 'application/zip';
        break;
      default:
        if (rawMime == 'application/pdf') {
          resolvedMime = rawMime;
          if (resolvedExt.isEmpty) resolvedExt = '.pdf';
        } else if (rawMime == 'application/msword') {
          resolvedMime = rawMime;
          if (resolvedExt.isEmpty) resolvedExt = '.doc';
        } else if (rawMime ==
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
          resolvedMime = rawMime;
          if (resolvedExt.isEmpty) resolvedExt = '.docx';
        } else if (rawMime == 'application/vnd.ms-excel') {
          resolvedMime = rawMime;
          if (resolvedExt.isEmpty) resolvedExt = '.xls';
        } else if (rawMime ==
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') {
          resolvedMime = rawMime;
          if (resolvedExt.isEmpty) resolvedExt = '.xlsx';
        } else if (rawMime == 'text/plain') {
          resolvedMime = rawMime;
          if (resolvedExt.isEmpty) resolvedExt = '.txt';
        } else if (rawMime == 'text/csv') {
          resolvedMime = rawMime;
          if (resolvedExt.isEmpty) resolvedExt = '.csv';
        } else if (rawMime.isNotEmpty &&
            rawMime != 'text/html' &&
            rawMime != 'image/svg+xml') {
          resolvedMime = rawMime;
        } else {
          resolvedMime = 'application/octet-stream';
        }
        break;
    }

    final cleanName = candidateName.isNotEmpty
        ? candidateName
        : (resolvedExt.isNotEmpty ? 'document$resolvedExt' : 'document');
    return ResolvedMediaInfo(
      extension: resolvedExt,
      contentType: resolvedMime,
      cleanFileName: cleanName,
      storageSafeBaseName: _sanitizeStorageSegment(cleanName, 'document'),
    );
  }
}
