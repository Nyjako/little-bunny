import 'package:flutter/foundation.dart';

/// Registers license entries for every native C library linked into
/// `bunny_core_ffi` (the shared library behind [StandaloneConfig]'s FFI
/// mode -- see `bunny_repository_factory.dart` -- which every build links
/// regardless of which [BunnyRepositoryConfig] is picked at runtime).
/// `flutter pub get`'s own license scraping (what `AboutScreen`'s own doc
/// comment on [showLicensePage] already relies on) only covers pub
/// packages, never the CMake/CPM-vendored C dependencies the repo root
/// `CMakeLists.txt` fetches -- those would otherwise be entirely missing
/// from the licenses list even though their object code genuinely ships
/// inside the app. Call once from `main()`, before `runApp`.
///
/// Covers every dependency `CMakeLists.txt` fetches for the FFI build
/// (`BUNNY_BUILD_SERVER OFF` -- civetweb/qrcodegen/stb/Unity are server-
/// or test-only and never linked here) plus curl's own system TLS
/// backend on desktop targets, confirmed against a real built
/// `libbunny_core_ffi.so` via `readelf -d` (its *direct* `NEEDED` entries
/// only -- Linux: libm/libssl/libcrypto/libz/libc; Android: everything
/// below OpenSSL is statically linked instead, so only libz/libm/libdl/
/// libc show up) rather than assumed from the CMake config alone.
///
/// An earlier pass here used plain `ldd` instead of `readelf -d` and
/// concluded curl was linking Brotli/Zstandard despite `CMakeLists.txt`
/// explicitly forcing `CURL_BROTLI`/`CURL_ZSTD` off -- that was a
/// misread: `ldd` prints the full *transitive* closure of every library
/// in the process, not just `libbunny_core_ffi.so`'s own direct deps.
/// `curl_config.h` in the actual build output confirms `HAVE_BROTLI`/
/// `HAVE_ZSTD` are both undefined (curl itself never touches either), and
/// `readelf -d` on the system's own `libcrypto.so.3` shows Brotli/Zstd as
/// *its* direct deps -- the Arch package build's own OpenSSL links them
/// for RFC 8879 TLS certificate compression, nothing to do with curl or
/// this app. They're deliberately left off this list: unlike everything
/// else here, they aren't vendored, chosen, or depended on by this
/// project at all, and which (if any) compression libraries a given
/// Linux distro's OpenSSL build happens to pull in is outside this app's
/// control and varies by distro.
void registerNativeDependencyLicenses() {
  for (final entry in _nativeDependencyLicenses) {
    LicenseRegistry.addLicense(() => Stream<LicenseEntry>.value(LicenseEntryWithLineBreaks(<String>[entry.name], entry.text)));
  }
}

typedef _NativeDependencyLicense = ({String name, String text});

const List<_NativeDependencyLicense> _nativeDependencyLicenses = [
  (name: 'curl', text: _curlLicense),
  (name: 'cJSON', text: _cJsonLicense),
  (name: 'SQLite', text: _sqliteLicense),
  (name: 'GOBLIN', text: _goblinLicense),
  (name: 'mbedTLS (Android builds)', text: _apache2License),
  (name: 'OpenSSL (desktop builds)', text: _apache2License),
  (name: 'zlib', text: _zlibLicense),
];

const String _curlLicense = '''
COPYRIGHT AND PERMISSION NOTICE

Copyright (c) 1996 - 2026, Daniel Stenberg, <daniel@haxx.se>, and many
contributors, see the THANKS file.

All rights reserved.

Permission to use, copy, modify, and distribute this software for any purpose
with or without fee is hereby granted, provided that the above copyright
notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF THIRD PARTY RIGHTS. IN
NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
OR OTHER DEALINGS IN THE SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall not
be used in advertising or otherwise to promote the sale, use or other dealings
in this Software without prior written authorization of the copyright holder.
''';

const String _cJsonLicense = '''
Copyright (c) 2009-2017 Dave Gamble and cJSON contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
''';

// SQLite's own blessing, verbatim from sqlite3.c -- the project places its
// source in the public domain and disclaims copyright entirely, so there is
// no permission-grant text as such, just this.
const String _sqliteLicense = '''
The author disclaims copyright to this source code. In place of a legal
notice, here is a blessing:

   May you do good and not evil.
   May you find forgiveness for yourself and forgive others.
   May you share freely, never taking more than you give.
''';

const String _goblinLicense = '''
MIT License

Copyright (c) 2026 Kacper Tucholski

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''';

// mbedTLS is dual Apache-2.0/GPL-2.0-or-later; OpenSSL 3.x is Apache-2.0
// outright -- both shown under the same Apache-2.0 text (the option this
// project takes for mbedTLS, given the app itself is not GPL).
const String _apache2License = '''
Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use this file except in compliance with the License. You may obtain a copy
of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.
''';

const String _zlibLicense = '''
(C) 1995-2026 Jean-loup Gailly and Mark Adler

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from
the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.
''';

