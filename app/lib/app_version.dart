/// This app's own release build number -- matches the GitHub release tag
/// (`build-<N>`) and the server's own `BUNNY_BUILD_NUMBER` (server/src/
/// updater.c) exactly, both ultimately `github.run_number` at release time.
/// 0 for a local/dev build (`flutter run`, `flutter test`, ...) -- never
/// "newer" than any real release, so [UpdateCheckService] never reports an
/// update for one. The real value is injected at build time via
/// `--dart-define=BUNNY_BUILD_NUMBER=<N>` (see release.yml).
const int appBuildNumber = int.fromEnvironment('BUNNY_BUILD_NUMBER', defaultValue: 0);
