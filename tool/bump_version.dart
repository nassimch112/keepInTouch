// Simple version bumper for pubspec.yaml
// Usage: dart run tool/bump_version.dart [patch|minor|major]

import 'dart:io';

void main(List<String> args) {
  final level = args.isNotEmpty ? args.first : 'patch';
  final file = File('pubspec.yaml');
  if (!file.existsSync()) {
    stderr.writeln('pubspec.yaml not found');
    exit(1);
  }
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().startsWith('version:')) {
      final current = line.split(':').last.trim();
      final parts = current.split('+');
      final semver = parts[0];
      final build = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      final sv = semver.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      while (sv.length < 3) sv.add(0);
      var major = sv[0], minor = sv[1], patch = sv[2];
      switch (level) {
        case 'major':
          major += 1;
          minor = 0;
          patch = 0;
          break;
        case 'minor':
          minor += 1;
          patch = 0;
          break;
        case 'patch':
        default:
          patch += 1;
      }
      final newBuild = build + 1;
      final next = 'version: ' + '$major.$minor.$patch' + '+$newBuild';
      lines[i] = next;
      file.writeAsStringSync(lines.join('\n'));
      stdout.writeln('Bumped version to $major.$minor.$patch+$newBuild');
      return;
    }
  }
  stderr.writeln('No version line found in pubspec.yaml');
  exit(1);
}
