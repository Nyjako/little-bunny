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
  String get accountsMyFavoritesTooltip => 'View my favorites';

  @override
  String get accountsMyFavoritesTitle => 'My favorites';

  @override
  String get searchesScreenTitle => 'Searches';

  @override
  String get searchesAccountsTooltip => 'Accounts';

  @override
  String get searchesSettingsTooltip => 'Settings';

  @override
  String get searchesTagStatsTooltip => 'Tag stats';

  @override
  String get searchesNewSearchTooltip => 'New search';

  @override
  String get searchesEmptyState => 'No saved searches yet. Tap + to add one.';

  @override
  String searchesIntervalSubtitle(String site, int hours, int total) {
    return '$site • every ${hours}h • $total posts';
  }

  @override
  String get searchesPinTooltip => 'Pin';

  @override
  String get searchesUnpinTooltip => 'Unpin';

  @override
  String get searchesSyncRowTooltip => 'Sync now';

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
  String get searchesSortTooltip => 'Sort';

  @override
  String get searchesSortMostUnseen => 'Most unseen';

  @override
  String get searchesSortLabel => 'Label (A-Z)';

  @override
  String get searchesSortRecentlyCreated => 'Recently created';

  @override
  String get searchesCheckForUpdatesTooltip => 'Check for updates';

  @override
  String searchesSyncAllProgress(int done, int total) {
    return '$done/$total checked';
  }

  @override
  String get tagStatsScreenTitle => 'Tag stats';

  @override
  String get tagStatsEmptyState =>
      'No favorited posts yet -- favorite some to see their tags here.';

  @override
  String get tagStatsAllEmptyState =>
      'No synced posts yet -- sync a search to see their tags here.';

  @override
  String get tagStatsFavoritesLabel => 'Favorites';

  @override
  String get tagStatsAllLabel => 'All';

  @override
  String get createSearchScreenTitle => 'New search';

  @override
  String get createSearchLabelField => 'Label';

  @override
  String get createSearchQueryField => 'Query';

  @override
  String get createSearchIntervalLabel => 'Sync interval (hours)';

  @override
  String get createSearchAutoFavoriteLabel => 'Auto-favorite new posts';

  @override
  String get createSearchAutoUpvoteLabel => 'Auto-upvote new posts';

  @override
  String get createSearchSubmit => 'Create';

  @override
  String get createPoolSearchDialogTitle => 'Add pool';

  @override
  String get createPoolSearchIdLabel => 'Pool ID';

  @override
  String get createPoolSearchSubmit => 'Add';

  @override
  String get editSearchScreenTitle => 'Edit search';

  @override
  String editSearchSiteLabel(String site) {
    return 'Site: $site';
  }

  @override
  String get editSearchStarsLabel => 'Favorite level';

  @override
  String get editSearchSubmit => 'Save';

  @override
  String get editSearchDeleteTooltip => 'Delete search';

  @override
  String get postGridUnseenOnlyTooltip => 'Show unseen only';

  @override
  String get postGridRefreshTooltip => 'Refresh';

  @override
  String get postGridEmptyState => 'No posts cached yet. Tap refresh to sync.';

  @override
  String get postGridMarkAllSeen => 'Mark all as seen';

  @override
  String get postGridSelectAll => 'Select all';

  @override
  String postGridSelectionCount(int count) {
    return '$count selected';
  }

  @override
  String get postGridExitSelectionTooltip => 'Cancel selection';

  @override
  String get postGridMassFavoriteTooltip => 'Favorite selected';

  @override
  String get postGridMassUpvoteTooltip => 'Upvote selected';

  @override
  String get postGridMassDownvoteTooltip => 'Downvote selected';

  @override
  String get postGridMassDownloadTooltip => 'Download selected';

  @override
  String postGridMassDownloadProgress(int done, int total) {
    return '$done/$total downloaded';
  }

  @override
  String postGridMassDownloadSummary(
    int succeeded,
    int mismatched,
    int failed,
  ) {
    return '$succeeded downloaded, $mismatched checksum mismatch, $failed failed';
  }

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
  String get postDetailTitleLabel => 'Title';

  @override
  String get postDetailDescriptionLabel => 'Description';

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
  String get postDetailBlacklistedDialogTitle => 'Blacklisted tag';

  @override
  String postDetailBlacklistedDialogContent(String tags) {
    return 'This post has a blacklisted tag: $tags';
  }

  @override
  String get postDetailBlacklistedViewAnyway => 'View anyway';

  @override
  String get postDetailActionFailed =>
      'Couldn\'t send that action -- it wasn\'t saved';

  @override
  String get postDetailFavoriteAddTooltip => 'Add to favorites';

  @override
  String get postDetailFavoriteRemoveTooltip => 'Remove from favorites';

  @override
  String get postDetailUpvoteTooltip => 'Upvote';

  @override
  String get postDetailDownvoteTooltip => 'Downvote';

  @override
  String get postDetailCommentsSectionLabel => 'Discussion';

  @override
  String get postDetailNoCommentsYet => 'No comments yet.';

  @override
  String get postDetailCommentFieldLabel => 'Add a comment';

  @override
  String get postDetailCommentAnonymousLabel => 'Post anonymously';

  @override
  String get postDetailCommentSubmit => 'Post';

  @override
  String get postDetailCommentPostFailed => 'Couldn\'t post that comment';

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

  @override
  String get settingsDownloadsSection => 'Downloads';

  @override
  String get settingsDownloadsFolderLabel => 'Destination folder';

  @override
  String get settingsDownloadsFolderUnset => 'Not set';

  @override
  String get settingsDownloadsChooseFolderButton => 'Choose folder';

  @override
  String get settingsAutoFavoriteOnDownloadLabel => 'Auto-favorite on download';

  @override
  String get settingsAutoUpvoteOnDownloadLabel => 'Auto-upvote on download';

  @override
  String get settingsBackupSection => 'Backup';

  @override
  String get settingsBackupExportLabel => 'Export searches';

  @override
  String get settingsBackupExportButton => 'Export';

  @override
  String get settingsBackupImportLabel => 'Import searches';

  @override
  String get settingsBackupImportButton => 'Import';

  @override
  String settingsBackupImportProgress(int done, int total) {
    return '$done/$total imported';
  }

  @override
  String settingsBackupExportSuccess(int count) {
    return 'Exported $count searches';
  }

  @override
  String settingsBackupImportSummary(
    int imported,
    int duplicates,
    int invalid,
  ) {
    return '$imported imported, $duplicates already saved, $invalid invalid';
  }

  @override
  String get settingsBackupImportUnrecognizedFormat =>
      'Unrecognized file format';

  @override
  String get settingsBlacklistSection => 'Blacklist';

  @override
  String get settingsBlacklistEmpty => 'No blacklisted tags yet.';

  @override
  String get settingsBlacklistAddLabel => 'Add tag';

  @override
  String get postDetailDownloadTooltip => 'Download';

  @override
  String get postDetailDownloadVerified => 'Downloaded and checksum verified';

  @override
  String get postDetailDownloadMismatch =>
      'Downloaded, but the checksum didn\'t match';

  @override
  String get postDetailDownloadFailed => 'Download failed';
}
