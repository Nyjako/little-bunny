# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(bunny_core_ffi_library VERSION 0.0.1 LANGUAGES C)

# Reuse the existing little-bunny CMake project instead of a second, parallel
# build definition -- this pulls in bunny_core and its whole dependency chain
# (bunny_db, bunny_e621, bunny_inkbunny, bunny_common, plus the CPM-fetched
# sqlite3/curl/cjson/goblin) exactly as built everywhere else in the repo.
# Only the core library chain is needed here, not the C server or tests.
#
# Flutter builds this plugin through a symlink
# (.../flutter/ephemeral/.plugin_symlinks/bunny_core_ffi), so a plain
# "${CMAKE_CURRENT_SOURCE_DIR}/../../.." walks up through the symlink's
# apparent location instead of this file's real one. Resolve the real path
# first.
get_filename_component(BUNNY_CORE_FFI_SRC_REAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
set(BUNNY_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(BUNNY_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(BUNNY_BUILD_SERVER OFF CACHE BOOL "" FORCE)
# bunny_core_ffi/src -> bunny_core_ffi -> <repo root> is only two levels up.
# EXCLUDE_FROM_ALL: the reused project's own CPM dependencies (cJSON, curl,
# ...) carry their own install() rules meant for a system-wide install --
# without this, Flutter's own "cmake --install" step (which bundles this
# plugin's shared lib into the app) also runs those, and e.g. cJSON tries to
# write to /usr/local/include and fails without admin rights. This keeps the
# reused subdirectory's targets buildable (bunny_core_ffi still links
# bunny_core directly) without pulling its install rules into the default
# install target.
add_subdirectory("${BUNNY_CORE_FFI_SRC_REAL_DIR}/../.." little_bunny_core_build EXCLUDE_FROM_ALL)

add_library(bunny_core_ffi SHARED
  "bunny_core_ffi.c"
)

# bunny_core_ffi.c itself never calls a bunny_core_*/bunny_db_* function --
# Dart looks all of them up by name via dlopen/DynamicLibrary.lookup at
# runtime. A normal `target_link_libraries` only pulls the .o files a static
# archive's caller actually references, so without forcing "whole archive"
# linking here, none of bunny_core's/bunny_db's actual object code (and thus
# none of the symbols Dart needs) would end up in the resulting shared
# library at all.
if(APPLE)
  target_link_libraries(bunny_core_ffi PRIVATE
    -Wl,-force_load,$<TARGET_FILE:bunny_core>
    -Wl,-force_load,$<TARGET_FILE:bunny_db>
  )
elseif(MSVC)
  # Passing "$<TARGET_FILE:bunny_core>" as a bare flag string (rather than
  # the target name itself, as the other two branches do) means CMake's
  # Visual Studio generator never records bunny_core/bunny_db as real
  # project dependencies of bunny_core_ffi -- MSBuild is then free to link
  # bunny_core_ffi.vcxproj before bunny_core.vcxproj has produced its .lib,
  # failing with LNK1104 ("cannot open file ...bunny_core.lib"). Spelling
  # out the dependency explicitly forces the correct build order.
  add_dependencies(bunny_core_ffi bunny_core bunny_db)
  target_link_libraries(bunny_core_ffi PRIVATE
    "/WHOLEARCHIVE:$<TARGET_FILE:bunny_core>"
    "/WHOLEARCHIVE:$<TARGET_FILE:bunny_db>"
  )
else()
  # GNU ld/lld (Linux, Android NDK, MinGW).
  target_link_libraries(bunny_core_ffi PRIVATE
    -Wl,--whole-archive
    bunny_core
    bunny_db
    -Wl,--no-whole-archive
  )
endif()

set_target_properties(bunny_core_ffi PROPERTIES
  PUBLIC_HEADER bunny_core_ffi.h
  OUTPUT_NAME "bunny_core_ffi"
)

target_compile_definitions(bunny_core_ffi PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(bunny_core_ffi PRIVATE "-Wl,-z,max-page-size=16384")
endif()
