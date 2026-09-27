# inkbunny_favorite_experiment (unofficial, experimental)

Tests whether Inkbunny's own website flow (not the documented API) can be used to
add/remove a favorite. `libinkbunny` deliberately doesn't do this because the official
API has no endpoint for it — see `docs/architecture.md`. This tool is for evaluating
whether that decision should be revisited, not for production use.

It logs into inkbunny.net the same way a browser would (`login.php` →
`login_process.php`, cookie-based session), scrapes a page-embedded CSRF token
(`global_token`), and POSTs to the same `submissionfav_process.php` endpoint the
website's own JS (`js82/fav.rev01.js`) calls when you click the favorite stars.

**This is fragile.** It depends on exact HTML markup that Inkbunny could change at any
time without notice, unlike the documented API. Treat it as a spike, not a dependency.

## Build

```sh
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

Example, tested against <https://inkbunny.net/s/3948160>:

```sh
./build-tools/tools/inkbunny_favorite_experiment/inkbunny_favorite_experiment yourname 3948160 add 1
./build-tools/tools/inkbunny_favorite_experiment/inkbunny_favorite_experiment yourname 3948160 remove
```
