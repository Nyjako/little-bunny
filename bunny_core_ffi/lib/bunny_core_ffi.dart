/// Dart FFI bindings to `bunny_core` (libs/core/), for the standalone
/// ("networked: off") mode described in docs/architecture.md's "Flutter app
/// (M6)" section. `BunnyCoreNative` is the public entry point -- everything
/// runs on one dedicated background isolate it owns internally, so callers
/// never block the UI thread.
library;

export 'src/bunny_core_isolate.dart' show BunnyCoreNative, BunnyCoreNativeException;
