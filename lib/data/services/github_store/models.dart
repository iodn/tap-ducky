import 'package:flutter/foundation.dart';

enum RepoItemType { file, dir }

enum DetectedFormat { ducky, payloadJson, unknown }

@immutable
class PreviewIssue {
  final String severity; // 'error' | 'warning'
  final int line;
  final String message;
  const PreviewIssue({required this.severity, required this.line, required this.message});
}

@immutable
class RepoRef {
  final String owner;
  final String repo;
  final String branch;
  final String path;
  final String originalUrl;
  final String? alias;
  const RepoRef({
    required this.owner,
    required this.repo,
    required this.branch,
    required this.path,
    required this.originalUrl,
    this.alias,
  });

  RepoRef copyWith({String? owner, String? repo, String? branch, String? path, String? originalUrl, String? alias}) => RepoRef(
    owner: owner ?? this.owner,
    repo: repo ?? this.repo,
    branch: branch ?? this.branch,
    path: path ?? this.path,
    originalUrl: originalUrl ?? this.originalUrl,
    alias: alias ?? this.alias,
  );

  Map<String, dynamic> toJson() => {
    'owner': owner,
    'repo': repo,
    'branch': branch,
    'path': path,
    'originalUrl': originalUrl,
    if (alias != null) 'alias': alias,
  };
}

@immutable
class RepoItem {
  final RepoItemType type;
  final String name;
  final String path;
  final int? size;
  final String? downloadUrl;
  final String? sha;
  const RepoItem({
    required this.type,
    required this.name,
    required this.path,
    this.size,
    this.downloadUrl,
    this.sha,
  });
}

@immutable
class FilePreview {
  final String name;
  final String path;
  final int size;
  // Converted or primary text shown in preview
  final String text;
  // When a conversion took place (e.g., .ino → ducky), keep the original too
  final String? originalText;
  final bool wasConverted;
  final bool isSupported;
  final String? supportReason;
  final DetectedFormat detectedFormat;
  final bool hasErrors;
  final int warningCount;
  final List<PreviewIssue> issues;
  const FilePreview({
    required this.name,
    required this.path,
    required this.size,
    required this.text,
    required this.isSupported,
    required this.detectedFormat,
    this.supportReason,
    this.originalText,
    this.wasConverted = false,
    this.hasErrors = false,
    this.warningCount = 0,
    this.issues = const <PreviewIssue>[],
  });
}
