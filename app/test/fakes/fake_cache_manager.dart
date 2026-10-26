import 'dart:async';
import 'dart:typed_data';

import 'package:file/file.dart' as pf;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// A [BaseCacheManager] whose `getFileStream` synchronously emits a
/// pre-written [FileInfo] wrapping a real on-disk [file] -- [GifPlayer]'s
/// real [DefaultCacheManager] kicks off a genuine network fetch that never
/// lets `tester.pumpAndSettle()` settle under `flutter_test` (even though
/// `CachedNetworkImage`'s own plain, non-streaming fetch is fine in this
/// exact environment), so any test reaching `GifPlayer` needs this
/// injected instead. Only `getFileStream` is ever actually called by
/// `GifPlayer` -- every other method throws, matching this codebase's
/// other narrow single-purpose fakes.
class FakeCacheManager implements BaseCacheManager {
  final pf.File file;

  FakeCacheManager(this.file);

  @override
  Stream<FileResponse> getFileStream(String url, {String? key, Map<String, String>? headers, bool withProgress = false}) {
    return Stream.value(FileInfo(file, FileSource.Online, DateTime.now().add(const Duration(days: 1)), url));
  }

  @override
  Future<pf.File> getSingleFile(String url, {String? key, Map<String, String>? headers}) => throw UnimplementedError();

  @override
  Stream<FileInfo> getFile(String url, {String? key, Map<String, String>? headers}) => throw UnimplementedError();

  @override
  Future<FileInfo> downloadFile(String url, {String? key, Map<String, String>? authHeaders, bool force = false}) => throw UnimplementedError();

  @override
  Future<FileInfo?> getFileFromCache(String key, {bool ignoreMemCache = false}) => throw UnimplementedError();

  @override
  Future<FileInfo?> getFileFromMemory(String key) => throw UnimplementedError();

  @override
  Future<pf.File> putFile(String url, Uint8List fileBytes, {String? key, String? eTag, Duration maxAge = const Duration(days: 30), String fileExtension = 'file'}) => throw UnimplementedError();

  @override
  Future<pf.File> putFileStream(String url, Stream<List<int>> source, {String? key, String? eTag, Duration maxAge = const Duration(days: 30), String fileExtension = 'file'}) => throw UnimplementedError();

  @override
  Future<void> removeFile(String key) => throw UnimplementedError();

  @override
  Future<void> emptyCache() => throw UnimplementedError();

  @override
  Future<void> dispose() => throw UnimplementedError();
}
