import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';
import '../../models/payload.dart';
import '../digispark_converter.dart';
import '../ducky_script_validator.dart';

class GitHubRateLimitException implements Exception {
  final String message;
  final DateTime? resetAt;
  GitHubRateLimitException(this.message, {this.resetAt});
  @override
  String toString() => message;
}

class GitHubNotFoundException implements Exception {
  final String message;
  GitHubNotFoundException(this.message);
  @override
  String toString() => message;
}

class GitHubTooLargeException implements Exception {
  final String message;
  GitHubTooLargeException(this.message);
  @override
  String toString() => message;
}

class GitHubStoreService {
  Future<String> getDefaultBranch(RepoRef ref) async {
    final uri = Uri.https('api.github.com', '/repos/${ref.owner}/${ref.repo}');
    final res = await http.get(uri, headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': userAgent,
    });
    if (res.statusCode == 404) {
      throw GitHubNotFoundException('Repository not found');
    }
    if (res.statusCode == 403) {
      final reset = res.headers['x-ratelimit-reset'];
      DateTime? resetAt;
      if (reset != null) {
        final epoch = int.tryParse(reset);
        if (epoch != null) resetAt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
      }
      throw GitHubRateLimitException('GitHub API rate limit reached', resetAt: resetAt);
    }
    if (res.statusCode != 200) {
      throw Exception('GitHub error: ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final branch = (body['default_branch'] ?? '').toString();
    return branch.isEmpty ? 'main' : branch;
  }
  static const userAgent = 'TapDucky/1.0';
  static const maxPreviewBytes = 256 * 1024; // 256KB

  Future<List<RepoItem>> listDirectory(RepoRef ref, {String? subPath, bool showMedia = false, bool showAll = false}) async {
    final path = [ref.path, if (subPath != null && subPath.isNotEmpty) subPath]
        .where((e) => e != null && e.toString().isNotEmpty)
        .join('/')
        .replaceAll('//', '/');
    final query = <String, String>{};
    if (ref.branch.isNotEmpty) query['ref'] = ref.branch;
    final uri = Uri.https('api.github.com', '/repos/${ref.owner}/${ref.repo}/contents/${path}', query);
    final res = await http.get(uri, headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': userAgent,
    });
    if (res.statusCode == 404) {
      throw GitHubNotFoundException('Repository, branch, or folder not found');
    }
    if (res.statusCode == 403) {
      final reset = res.headers['x-ratelimit-reset'];
      DateTime? resetAt;
      if (reset != null) {
        final epoch = int.tryParse(reset);
        if (epoch != null) resetAt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
      }
      throw GitHubRateLimitException('GitHub API rate limit reached', resetAt: resetAt);
    }
    if (res.statusCode != 200) {
      throw Exception('GitHub error: ${res.statusCode}');
    }
    final body = jsonDecode(res.body);
    if (body is! List) {
      throw Exception('Expected a directory listing');
    }
    final all = body.map<RepoItem>((e) {
      final type = (e['type'] == 'dir') ? RepoItemType.dir : RepoItemType.file;
      return RepoItem(
        type: type,
        name: (e['name'] ?? '').toString(),
        path: (e['path'] ?? '').toString(),
        size: (e['size'] is int) ? e['size'] as int : null,
        downloadUrl: (e['download_url'] ?? '').toString().isEmpty ? null : (e['download_url'] as String),
        sha: (e['sha'] ?? '').toString().isEmpty ? null : (e['sha'] as String),
      );
    }).where((it) => it.name.isNotEmpty && !it.name.startsWith('.'));

    // Smooth UX: hide obvious media assets (images/videos) from file list.
    const hiddenExts = [
      // Images
      '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg', '.heic', '.heif',
      // Videos
      '.mp4', '.mov', '.avi', '.mkv', '.webm',
      // Archives
      '.zip', '.7z', '.rar', '.tar', '.gz', '.tgz', '.bz2', '.xz', '.tar.gz', '.tar.bz2', '.tar.xz',
      // Binaries / executables / docs we won't preview
      '.exe', '.dll', '.so', '.dylib', '.bin', '.o', '.a', '.class', '.jar',
      '.pdf', '.doc', '.docx', '.ppt', '.pptx', '.xls', '.xlsx',
      // Markdown / readme files (hide by default)
      '.md', '.markdown'
    ];
    bool isHiddenMedia(String name) {
      final lower = name.toLowerCase();
      for (final ext in hiddenExts) {
        if (lower.endsWith(ext)) return true;
      }
      return false;
    }

    final items = all
        .where((it) {
          if (showAll) return true;
          if (it.type == RepoItemType.dir) {
            final name = it.name.toLowerCase();
            if (name == 'images' || name == 'image' || name == 'img' || name == 'video' || name == 'videos') {
              return false; // hide common media folders
            }
            return true;
          }
          return showMedia || !isHiddenMedia(it.name);
        })
        .toList()
      ..sort((a, b) {
        if (a.type != b.type) return a.type == RepoItemType.dir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return items;
  }

  Future<FilePreview> fetchFilePreview(RepoRef ref, String fullPath) async {
    final query = <String, String>{};
    if (ref.branch.isNotEmpty) query['ref'] = ref.branch;
    final uri = Uri.https('api.github.com', '/repos/${ref.owner}/${ref.repo}/contents/$fullPath', query);
    final res = await http.get(uri, headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': userAgent,
    });
    if (res.statusCode == 404) {
      throw GitHubNotFoundException('File not found');
    }
    if (res.statusCode == 403) {
      final reset = res.headers['x-ratelimit-reset'];
      DateTime? resetAt;
      if (reset != null) {
        final epoch = int.tryParse(reset);
        if (epoch != null) resetAt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
      }
      throw GitHubRateLimitException('GitHub API rate limit reached', resetAt: resetAt);
    }
    if (res.statusCode != 200) {
      throw Exception('GitHub error: ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final size = (body['size'] is int) ? body['size'] as int : 0;
    if (size > maxPreviewBytes) {
      throw GitHubTooLargeException('File too large to preview/import (max 256KB)');
    }
    String text;
    if (body['encoding'] == 'base64' && body['content'] is String) {
      final b64 = (body['content'] as String).replaceAll('\n', '');
      final bytes = base64.decode(b64);
      text = utf8.decode(bytes, allowMalformed: true);
    } else if (body['download_url'] is String) {
      final raw = await http.get(Uri.parse(body['download_url'] as String), headers: {'User-Agent': userAgent});
      if (raw.statusCode != 200) throw Exception('Failed to fetch raw');
      text = raw.body;
    } else {
      throw Exception('No content');
    }

    // Detect format
    var detected = DetectedFormat.unknown;
    var supported = false;
    String? reason;

    // Try DigiSpark .ino conversion first
    if (fullPath.toLowerCase().endsWith('.ino') || text.contains('DigiKeyboard')) {
      final conv = DigiSparkConverter.convert(text);
      if (conv != null) {
        final validator = DuckyScriptValidator();
        final res = validator.validate(conv.text);
        final hasErr = res.hasErrors || res.commandCount == 0;
        if (!hasErr) {
          final name = fullPath.split('/').last;
          final reasonSuffix = conv.usedMouseApis ? ' (mouse)' : '';
          return FilePreview(
            name: name,
            path: fullPath,
            size: size,
            text: conv.text,
            originalText: text,
            wasConverted: true,
            isSupported: true,
            supportReason: 'Converted from DigiSpark .ino$reasonSuffix',
            detectedFormat: DetectedFormat.ducky,
            hasErrors: false,
            warningCount: res.issues.where((i) => i.severity == IssueSeverity.warning).length,
            issues: res.issues                .map((i) => PreviewIssue(
                      severity: i.severity.name,
                      line: i.line,
                      message: i.message,
                    ))
                .toList(),
          );
        }
        // if conversion failed to validate, fallthrough to other detectors
      }
    }

    // Try JSON payload first
    bool jsonLooksValid = false;
    bool jsonHasErrors = false;
    int jsonWarnings = 0;
    try {
      final obj = jsonDecode(text);
      if (obj is Map && obj['script'] is String) {
        final script = (obj['script'] as String);
        // Validate embedded script as ducky to ensure compatibility
        final validator = DuckyScriptValidator();
        final result = validator.validate(script);
        jsonHasErrors = result.hasErrors || result.commandCount == 0;
        jsonWarnings = result.issues.where((i) => i.severity == IssueSeverity.warning).length;
        if (!jsonHasErrors) {
          detected = DetectedFormat.payloadJson;
          supported = true;
          reason = 'TapDucky JSON payload';
          jsonLooksValid = true;
        }
        // attach issues regardless to show user details
        final mapped = result.issues
            .map((i) => PreviewIssue(severity: i.severity.name, line: i.line, message: i.message))
            .toList();
        final name = fullPath.split('/').last;
        if (jsonLooksValid) {
          return FilePreview(
            name: name,
            path: fullPath,
            size: size,
            text: text,
            isSupported: true,
            supportReason: 'TapDucky JSON payload',
            detectedFormat: DetectedFormat.payloadJson,
            hasErrors: false,
            warningCount: jsonWarnings,
            issues: mapped,
          );
        }
      }
    } catch (_) {}

    // Try ducky text
    bool duckHasErrors = false;
    int duckWarnings = 0;
    if (!jsonLooksValid) {
      final validator = DuckyScriptValidator();
      final result = validator.validate(text);
      duckHasErrors = result.hasErrors || result.commandCount == 0;
      duckWarnings = result.issues.where((i) => i.severity == IssueSeverity.warning).length;
      if (!duckHasErrors) {
        detected = DetectedFormat.ducky;
        supported = true;
        reason = 'Ducky Script';
        final mapped = result.issues
            .map((i) => PreviewIssue(severity: i.severity.name, line: i.line, message: i.message))
            .toList();
        final name = fullPath.split('/').last;
        return FilePreview(
          name: name,
          path: fullPath,
          size: size,
          text: text,
          isSupported: true,
          supportReason: 'Ducky Script',
          detectedFormat: DetectedFormat.ducky,
          hasErrors: false,
          warningCount: duckWarnings,
          issues: mapped,
        );
      }
    }

    final name = fullPath.split('/').last;
    // Unsupported or has errors
    return FilePreview(
      name: fullPath.split('/').last,
      path: fullPath,
      size: size,
      text: text,
      isSupported: false,
      supportReason: reason,
      detectedFormat: DetectedFormat.unknown,
      hasErrors: true,
      warningCount: 0,
      issues: const <PreviewIssue>[],
    );
  }
}
