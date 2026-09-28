# inkbunny_favorite_experiment

A thin CLI over `libinkbunny`'s unofficial favorite functions
(`inkbunny/unofficial_favorites.h`: `inkbunny_website_login`, `inkbunny_favorite_add`,
`inkbunny_favorite_remove`), for manually testing them against a real account. See
`docs/architecture.md`, "Unofficial favorite flow", for what these do and why they exist
separately from the documented-API-only parts of `libinkbunny`.

**This is fragile.** These functions depend on exact HTML markup that Inkbunny could
change at any time without notice, unlike the documented API — confirmed live 2026-09-28
when the site's mixed single-/double-quoted attributes broke the first extraction attempt.

## Build

```sh
make tools
# or directly:
cmake -S . -B build-tools -DCMAKE_BUILD_TYPE=Debug -DBUNNY_BUILD_TOOLS=ON
cmake --build build-tools
```

## Run

```sh
./build-tools/tools/inkbunny_favorite_experiment/inkbunny_favorite_experiment <username> <submission_id> add 1
./build-tools/tools/inkbunny_favorite_experiment/inkbunny_favorite_experiment <username> <submission_id> remove
```

You'll be prompted for your password on stdin (not echoed). It's used once to log in
and then overwritten in memory — never logged, printed, or stored anywhere.

Example, verified working against <https://inkbunny.net/s/3948160>:

```sh
./build-tools/tools/inkbunny_favorite_experiment/inkbunny_favorite_experiment yourname 3948160 add 1
./build-tools/tools/inkbunny_favorite_experiment/inkbunny_favorite_experiment yourname 3948160 remove
```
