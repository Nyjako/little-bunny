// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'LittleBunny';

  @override
  String get commonRequired => 'Required';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonContinue => 'Continue';

  @override
  String get setupScreenTitle => 'Set up LittleBunny';

  @override
  String get setupModeStandalone => 'Standalone';

  @override
  String get setupModeNetworked => 'Networked';

  @override
  String get setupStandaloneDescription =>
      'Stores everything locally on this device. No server needed.';

  @override
  String get setupServerUrlLabel => 'Server URL';

  @override
  String get setupServerUrlHint => 'https://192.168.1.10:8443';

  @override
  String get setupServerUrlInvalid => 'Enter a valid URL';

  @override
  String get setupBearerTokenLabel => 'Bearer token';

  @override
  String get setupCertFingerprintLabel => 'Certificate SHA-256 fingerprint';

  @override
  String loginScreenTitle(String site) {
    return 'Log in to $site';
  }

  @override
  String get loginUsernameLabel => 'Username';

  @override
  String get loginApiKeyLabel => 'API key';

  @override
  String get loginPasswordLabel => 'Password';

  @override
  String get loginSubmit => 'Log in';

  @override
  String get accountsScreenTitle => 'Accounts';

  @override
  String get accountsRemoveDialogTitle => 'Remove account?';

  @override
  String accountsRemoveDialogContent(String site) {
    return 'This removes the saved $site account from this app. You can log in again later.';
  }

  @override
  String accountsLoggedInAs(String username) {
    return 'Logged in as $username';
  }

  @override
  String get accountsNotConnected => 'Not connected';

  @override
  String get searchesScreenTitle => 'Searches';

  @override
  String get searchesAccountsTooltip => 'Accounts';

  @override
  String get searchesSettingsTooltip => 'Settings';

  @override
  String get searchesNewSearchTooltip => 'New search';

  @override
  String get searchesEmptyState => 'No saved searches yet. Tap + to add one.';

  @override
  String searchesIntervalSubtitle(String site, int hours) {
    return '$site • every ${hours}h';
  }

  @override
  String get searchesRemoveDialogTitle => 'Remove search?';

  @override
  String searchesRemoveDialogContent(String label) {
    return 'This removes the saved search \"$label\" from this app.';
  }

  @override
  String get searchesTabSearches => 'Searches';

  @override
  String get searchesTabPools => 'Pools';

  @override
  String get searchesPoolsEmptyState => 'No saved pools yet. Tap + to add one.';

  @override
  String get searchesNewPoolTooltip => 'Add pool';

  @override
  String get createSearchScreenTitle => 'New search';

  @override
  String get createSearchLabelField => 'Label';

  @override
  String get createSearchQueryField => 'Query';

  @override
  String get createSearchIntervalLabel => 'Sync interval (hours)';

  @override
  String get createSearchSubmit => 'Create';

  @override
  String get createPoolSearchDialogTitle => 'Add pool';

  @override
  String get createPoolSearchIdLabel => 'Pool ID';

  @override
  String get createPoolSearchSubmit => 'Add';

  @override
  String get postGridUnseenOnlyTooltip => 'Show unseen only';

  @override
  String get postGridRefreshTooltip => 'Refresh';

  @override
  String get postGridEmptyState => 'No posts cached yet. Tap refresh to sync.';

  @override
  String get postGridMarkAllSeen => 'Mark all as seen';

  @override
  String get tagBrowseEmptyState => 'No posts found for this search.';

  @override
  String get tagBrowseAddToSearchesTooltip => 'Save as a search';

  @override
  String get postDetailScreenTitle => 'Post';

  @override
  String postDetailUnsupportedFormat(String extension) {
    return 'This file format ($extension) isn\'t supported yet';
  }

  @override
  String get postDetailArtistLabel => 'Artist';

  @override
  String get postDetailTitleLabel => 'Title';

  @override
  String get postDetailDescriptionLabel => 'Description';

  @override
  String get postDetailRatingLabel => 'Rating';

  @override
  String get postDetailScoreLabel => 'Score';

  @override
  String get postDetailFavoritesLabel => 'Favorites';

  @override
  String get postDetailCommentsLabel => 'Comments';

  @override
  String get postDetailDimensionsLabel => 'Dimensions';

  @override
  String get postDetailCreatedLabel => 'Posted';

  @override
  String get postDetailUnknownValue => 'Unknown';

  @override
  String get postDetailIdLabel => 'Post ID';

  @override
  String get postDetailIdCopied => 'Post ID copied to clipboard';

  @override
  String get postDetailTagsLabel => 'Tags';

  @override
  String get postDetailSourcesLabel => 'Sources';

  @override
  String get postDetailParentLabel => 'Parent';

  @override
  String get postDetailChildrenLabel => 'Children';

  @override
  String get postDetailPoolsLabel => 'Pools';

  @override
  String get postDetailOpenPostFailed => 'Couldn\'t open that post';

  @override
  String get postDetailCreatePoolSearchDialogTitle => 'Add pool';

  @override
  String postDetailCreatePoolSearchDialogContent(int poolId) {
    return 'This post belongs to pool $poolId, but there\'s no saved search for it yet. Create one?';
  }

  @override
  String get lockScreenMessage => 'LittleBunny is locked';

  @override
  String get lockScreenBiometricReason => 'Unlock LittleBunny';

  @override
  String get lockScreenPinLabel => 'PIN/password';

  @override
  String get lockScreenUnlock => 'Unlock';

  @override
  String get lockScreenTryFingerprintAgain => 'Try fingerprint again';

  @override
  String get lockScreenIncorrectPin => 'Incorrect PIN/password';

  @override
  String get lockSetupScreenTitle => 'App lock';

  @override
  String get lockSetupDescription =>
      'Set a PIN or password to lock this app on startup.';

  @override
  String get lockSetupNewPinLabel => 'New PIN/password';

  @override
  String get lockSetupConfirmLabel => 'Confirm';

  @override
  String get lockSetupEntriesDoNotMatch => 'Entries do not match';

  @override
  String get lockSetupEnableButton => 'Enable app lock';

  @override
  String get lockSetupCurrentlyOn => 'App lock is currently on.';

  @override
  String get lockSetupCurrentPinLabel =>
      'Enter current PIN/password to disable';

  @override
  String get lockSetupDisableButton => 'Disable app lock';

  @override
  String get settingsScreenTitle => 'Settings';

  @override
  String get settingsAppearanceSection => 'Appearance';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsAppLockSection => 'App lock';

  @override
  String get settingsAppLockEntry => 'Manage app lock';

  @override
  String get settingsSyncSection => 'Sync';

  @override
  String get settingsDefaultIntervalLabel => 'Default sync interval (hours)';

  @override
  String get settingsDisplaySection => 'Display';

  @override
  String get settingsPreviewQualityThumbnail => 'Thumbnail';

  @override
  String get settingsPreviewQualityMedium => 'Medium';

  @override
  String get settingsGridColumnsLabel => 'Grid columns';
}
