import 'package:bunny_core_ffi/bunny_core_ffi.dart';

import 'bunny_models.dart';
import 'bunny_repository.dart';

/// Shared [BunnyRepository.downloadFile] implementation (M66) -- both
/// [FfiBunnyRepository] and [HttpBunnyRepository] delegate to this against
/// their own already-open [BunnyCoreNative] handle; the actual fetch is
/// always the same local native call regardless of repository mode (see
/// [BunnyRepository.downloadFile]'s own doc comment). Polls every 250ms,
/// a cadence chosen to match how often a progress bar realistically needs
/// to repaint -- fast enough to feel live, cheap enough not to matter.
Future<DownloadFetchResult> downloadFileViaNative(
  BunnyCoreNative native,
  String fileUrl,
  Map<String, String> extraHeaders,
  String destDir,
  String filename,
  String? expectedMd5,
  void Function(int received, int? total) onProgress,
) async {
  try {
    final handle = await native.downloadStart(fileUrl, extraHeaders, destDir, filename, expectedMd5);
    try {
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final poll = await native.downloadPoll(handle);
        final total = poll['total'] as int;
        onProgress(poll['received'] as int, total < 0 ? null : total);
        if (poll['done'] as bool) {
          return DownloadFetchResult(outcome: poll['outcome'] as String, errorMessage: poll['errorMessage'] as String?);
        }
      }
    } finally {
      await native.downloadRelease(handle);
    }
  } on BunnyCoreNativeException catch (e) {
    throw BunnyRepositoryException(e.message);
  }
}
