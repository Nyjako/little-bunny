#ifndef BUNNY_CORE_FFI_H
#define BUNNY_CORE_FFI_H

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

/* This shared library exists purely to link bunny_core (and its full
 * dependency chain -- see src/CMakeLists.txt) into something dart:ffi can
 * dlopen. bunny_core's own headers (libs/core/include/bunny_core/*.h,
 * libs/db/include/bunny_db/types.h) are the real ffigen entry points --
 * see ../ffigen.yaml -- since they're already plain, simple C with no
 * platform-specific macros. This one helper just proves the library loaded
 * and linked correctly. */
FFI_PLUGIN_EXPORT const char *bunny_core_ffi_version(void);

#endif /* BUNNY_CORE_FFI_H */
