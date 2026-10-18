import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Downloads a release asset ([UpdateCheckResult.downloadUrl]) and applies
/// it, per platform -- see [downloadAndApply]'s own doc comment for exactly
/// what "applies" means on each one. Pure logic, no widget, same shape as
/// [DownloadManager]; the caller (a dialog, see SearchesScreen) owns all UI.
class UpdateApplyService {
  /// Injectable for tests (a fake [http.Client]); `null` lazily creates a
  /// real one per call -- same pattern as [DownloadManager.client].
  final http.Client? client;

  const UpdateApplyService({this.client});

  Future<File> _downloadToFile(String url, String destPath, {void Function(double? progress)? onProgress}) async {
    final httpClient = client ?? http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await httpClient.send(request);
      if (response.statusCode != 200) {
        throw Exception('download failed: HTTP ${response.statusCode}');
      }

      final file = File(destPath);
      final sink = file.openWrite();
      final total = response.contentLength;
      var received = 0;
      try {
        await response.stream.listen((chunk) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) {
            onProgress?.call(received / total);
          }
        }).asFuture<void>();
      } finally {
        await sink.close();
      }
      return file;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Extracts a .zip or .tar.gz archive into destDir (created if missing).
  /// Pure Dart (the `archive` package) rather than shelling out to `tar`/
  /// `Expand-Archive` -- unlike server/src/updater.c's Linux-only, controlled
  /// deployment (where `tar` is a safe assumption), a general end-user
  /// machine running this app can't be assumed to have any particular
  /// archive tool on PATH, especially on Windows.
  Future<void> _extractArchive(String archivePath, String destDir) async {
    await Directory(destDir).create(recursive: true);
    final bytes = await File(archivePath).readAsBytes();
    final archive = archivePath.endsWith('.tar.gz') ? TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes)) : ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      final outPath = path.join(destDir, entry.name);
      if (entry.isFile) {
        final outFile = File(outPath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>);
        if (!Platform.isWindows) {
          // Preserve the executable bit the archive itself carries (tar
          // stores Unix file modes; Flutter's own build output already has
          // this set correctly on the main binary) -- lost by a naive
          // writeAsBytes, which creates a plain 644 file.
          final mode = entry.mode;
          if (mode & 0x40 != 0) {
            await Process.run('chmod', ['+x', outPath]);
          }
        }
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }

  /// Linux's own bundle is flat: Platform.resolvedExecutable's parent
  /// directory IS the whole install (the exe alongside lib/, data/).
  /// Overwriting files of a running executable is safe on Linux (the
  /// kernel keeps the old inode mapped for this process until it exits;
  /// the next launch opens the new one) -- extract straight over it, then
  /// relaunch (a fresh, detached process so it outlives this one) and exit.
  Future<bool> _applyLinux(String extractedDir) async {
    final installDir = File(Platform.resolvedExecutable).parent.path;
    final extractedBundleDir = Directory(path.join(extractedDir, 'bundle'));
    if (!await extractedBundleDir.exists()) {
      return false;
    }
    await for (final entity in extractedBundleDir.list(recursive: true)) {
      final relative = path.relative(entity.path, from: extractedBundleDir.path);
      final dest = path.join(installDir, relative);
      if (entity is File) {
        await Directory(path.dirname(dest)).create(recursive: true);
        await entity.copy(dest);
      } else if (entity is Directory) {
        await Directory(dest).create(recursive: true);
      }
    }
    await Process.start(Platform.resolvedExecutable, [], mode: ProcessStartMode.detached);
    exit(0);
  }

  /// A macOS app bundle's structure (Contents/MacOS/the executable) is a fixed OS
  /// convention, not a guess -- three directories up from
  /// Platform.resolvedExecutable is reliably the .app root, the same way
  /// Sparkle-style macOS updaters locate it. Same in-place-overwrite +
  /// relaunch reasoning as Linux.
  Future<bool> _applyMacOS(String extractedDir) async {
    final appBundlePath = path.dirname(path.dirname(path.dirname(Platform.resolvedExecutable)));
    final entries = await Directory(extractedDir).list().toList();
    final extractedApp = entries.whereType<Directory>().where((d) => d.path.endsWith('.app')).firstOrNull;
    if (extractedApp == null) {
      return false;
    }
    await for (final entity in extractedApp.list(recursive: true)) {
      final relative = path.relative(entity.path, from: extractedApp.path);
      final dest = path.join(appBundlePath, relative);
      if (entity is File) {
        await Directory(path.dirname(dest)).create(recursive: true);
        await entity.copy(dest);
      } else if (entity is Directory) {
        await Directory(dest).create(recursive: true);
      }
    }
    await Process.start('open', [appBundlePath], mode: ProcessStartMode.detached);
    exit(0);
  }

  /// Windows locks a running .exe's own file (and its loaded DLLs) against
  /// being overwritten -- unlike Linux/macOS, there's no way for this
  /// process to replace its own install directory while still running it.
  /// The standard pattern (what most Windows auto-updaters do): write a
  /// small detached helper script that waits for this process to actually
  /// exit (so its locks release), swaps the files, and relaunches -- then
  /// this process just exits immediately after spawning it.
  Future<bool> _applyWindows(String extractedDir) async {
    final installDir = File(Platform.resolvedExecutable).parent.path;
    final exeName = path.basename(Platform.resolvedExecutable);
    final currentPid = pid; // dart:io top-level getter -- this process's own PID
    final scriptPath = path.join(await _tempDirPath(), 'bunny_update_apply.bat');
    final script =
        '@echo off\r\n'
        ':wait\r\n'
        'tasklist /FI "PID eq $currentPid" 2>NUL | find /I "$currentPid" >NUL\r\n'
        'if not errorlevel 1 (\r\n'
        '  timeout /t 1 /nobreak >nul\r\n'
        '  goto wait\r\n'
        ')\r\n'
        'xcopy /E /Y /I "$extractedDir" "$installDir"\r\n'
        'start "" "$installDir\\$exeName"\r\n'
        'del "%~f0"\r\n';
    await File(scriptPath).writeAsString(script);
    await Process.start('cmd.exe', ['/c', scriptPath], mode: ProcessStartMode.detached);
    exit(0);
  }

  /// Android has no "swap in place" concept at all (and no permission to
  /// write over its own installed APK even if it did) -- opening the
  /// downloaded .apk hands off to the system's own package installer,
  /// which does the actual replace after the user confirms (requires
  /// "install unknown apps" to be granted for this app the first time,
  /// same as sideloading normally does).
  Future<bool> _applyAndroid(File apkFile) async {
    final result = await OpenFilex.open(apkFile.path, type: 'application/vnd.android.package-archive');
    return result.type == ResultType.done;
  }

  Future<String> _tempDirPath() async => (await getTemporaryDirectory()).path;

  Future<bool> downloadAndApply(String downloadUrl, {void Function(double? progress)? onProgress}) async {
    final tempDir = await _tempDirPath();
    final fileName = downloadUrl.split('/').last;
    final downloadPath = path.join(tempDir, fileName);

    final file = await _downloadToFile(downloadUrl, downloadPath, onProgress: onProgress);

    if (Platform.isAndroid) {
      return _applyAndroid(file);
    }

    final extractDir = path.join(tempDir, 'bunny_update_extracted');
    await _extractArchive(file.path, extractDir);

    if (Platform.isLinux) {
      return _applyLinux(extractDir);
    }
    if (Platform.isMacOS) {
      return _applyMacOS(extractDir);
    }
    if (Platform.isWindows) {
      return _applyWindows(extractDir);
    }
    return false;
  }
}
