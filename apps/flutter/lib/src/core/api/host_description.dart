/// Host snapshot contract mirrored from the `describe` method in
/// `packages/host/apiproxy/src/api/host.ts`.
///
/// One-shot host snapshot; empty request payload uses the literal `{}`.
library;

import 'package:meta/meta.dart';

/// The decoded `host.describe` response payload.
@immutable
class HostDescription {
  /// Creates a snapshot from already-decoded parts.
  const HostDescription({
    required this.version,
    required this.cwd,
    this.provider,
    this.model,
    required this.attachedSessions,
    required this.home,
    required this.canOpenPath,
  });

  /// Decodes the wire payload; throws [ArgumentError] on malformed fields
  /// (the host validates with `host.schema.ts`, so malformed bodies mean a
  /// broken peer).
  factory HostDescription.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    final cwd = json['cwd'];
    final attachedSessions = json['attachedSessions'];
    final home = json['home'];
    final canOpenPath = json['canOpenPath'];
    if (version is! String)
      throw ArgumentError.value(version, 'version', 'must be a string');
    if (cwd is! String)
      throw ArgumentError.value(cwd, 'cwd', 'must be a string');
    if (attachedSessions is! int) {
      throw ArgumentError.value(
        attachedSessions,
        'attachedSessions',
        'must be an integer',
      );
    }
    if (home is! String)
      throw ArgumentError.value(home, 'home', 'must be a string');
    if (canOpenPath is! bool)
      throw ArgumentError.value(
        canOpenPath,
        'canOpenPath',
        'must be a boolean',
      );
    return HostDescription(
      version: version,
      cwd: cwd,
      provider: json['provider'] as String?,
      model: json['model'] as String?,
      attachedSessions: attachedSessions,
      home: home,
      canOpenPath: canOpenPath,
    );
  }

  /// Host app's version (apps/cli package.json version).
  final String version;

  /// Host process working directory: root for session persistence and tools.
  final String cwd;

  /// Default provider for new agents when the host configures one explicitly.
  final String? provider;

  /// Default model for new agents when the host configures one explicitly.
  final String? model;

  /// Count of currently attached sessions (those with a live agent).
  final int attachedSessions;

  /// Host account home directory (Web abbreviates on display).
  final String home;

  /// Whether this deployment can hand a path to a user-visible native desktop.
  final bool canOpenPath;
}
