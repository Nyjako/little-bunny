import 'dart:ffi';
import 'dart:io';

/// Opens the platform-appropriate `bunny_core_ffi` shared library. Its own
/// symbols (`bunny_core_ffi_version`) are trivial -- what actually matters is
/// that it links `bunny_core` and its whole dependency chain (see
/// `src/CMakeLists.txt`), so every `bunny_core_*`/`bunny_db_*` symbol is
/// resolvable from here too.
DynamicLibrary loadBunnyCoreLibrary() {
  const libName = 'bunny_core_ffi';
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$libName.framework/$libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}
