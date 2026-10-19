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
  String get setupReconfigureTitle => 'Switch connection';

  @override
  String get setupSwitchWarningTitle => 'Switch data source?';

  @override
  String get setupSwitchWarningMessage =>
      'Standalone and networked mode use separate data stores -- your current searches/accounts won\'t automatically carry over. Use Settings → Backup to export/import searches if you want to bring them along.';

  @override
  String get setupSwitchConfirm => 'Switch';

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
  String get searchesSortLastViewed => 'Last viewed';

  @override
  String get searchesCheckForUpdatesTooltip => 'Check for updates';

  @override
  String searchesSyncAllProgress(int done, int total) {
    return '$done/$total checked';
  }

  @override
  String get searchesSyncInProgress => 'Syncing…';

  @override
  String get searchesNewGroupTooltip => 'New group';

  @override
  String get searchesGroupNameLabel => 'Name';

  @override
  String get searchesCreateGroupDialogTitle => 'New group';

  @override
  String get searchesCreateGroupSubmit => 'Create';

  @override
  String get searchesRenameGroupDialogTitle => 'Rename group';

  @override
  String get searchesRenameGroupSubmit => 'Save';

  @override
  String get searchesRenameGroupMenuItem => 'Rename';

  @override
  String get searchesDeleteGroupMenuItem => 'Delete group';

  @override
  String get searchesDeleteGroupDialogTitle => 'Delete group?';

  @override
  String searchesDeleteGroupDialogContent(String name) {
    return 'Searches in \"$name\" will be ungrouped, not deleted.';
  }

  @override
  String searchesGroupSubtitle(int total) {
    return '$total posts';
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
  String get createSearchUsesDefaultIntervalLabel => 'Use default interval';

  @override
  String get createSearchGroupLabel => 'Group';

  @override
  String get createSearchGroupNone => 'No group';

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
  String get tagBrowseRelatedPoolsLabel => 'Related pools';

  @override
  String tagBrowseRelatedPoolChip(int poolId) {
    return 'Pool #$poolId';
  }

  @override
  String get postGridPoolInfoTooltip => 'Pool info';

  @override
  String get postGridPoolInfoTitle => 'Pool information';

  @override
  String postGridPoolInfoPostCount(int count) {
    return '$count posts';
  }

  @override
  String get postGridPoolInfoNoDescription => 'No description.';

  @override
  String get postGridPoolInfoCloseButton => 'Close';

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
  String postDetailFavoriteStarsTooltip(int stars) {
    return 'Favorite ($stars/3 hearts)';
  }

  @override
  String get postDetailFavoriteStarsRemoveTooltip => 'Remove favorite';

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
  String get settingsConnectionSection => 'Connection';

  @override
  String get settingsConnectionEntry => 'Switch connection mode';

  @override
  String get settingsConnectionStandalone => 'Standalone';

  @override
  String settingsConnectionNetworked(String serverUrl) {
    return 'Networked ($serverUrl)';
  }

  @override
  String get settingsServerLogsEntry => 'Server logs';

  @override
  String get serverLogsScreenTitle => 'Server logs';

  @override
  String get serverLogsEmptyState => 'No log lines yet.';

  @override
  String get serverLogsRefreshTooltip => 'Refresh';

  @override
  String get settingsTaskQueueEntry => 'Task queue';

  @override
  String get taskQueueScreenTitle => 'Task queue';

  @override
  String get taskQueueEmptyState => 'Nothing queued right now.';

  @override
  String get taskQueuePriorityHigh => 'High';

  @override
  String get taskQueuePriorityMedium => 'Medium';

  @override
  String get taskQueuePriorityLow => 'Low';

  @override
  String get taskQueueStatusRunning => 'Running';

  @override
  String get taskQueueStatusPending => 'Pending';

  @override
  String get settingsAppearanceSection => 'Appearance';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeColorLabel => 'Color';

  @override
  String get settingsThemeColorPurple => 'Purple';

  @override
  String get settingsThemeColorBlue => 'Blue';

  @override
  String get settingsThemeColorGreen => 'Green';

  @override
  String get settingsThemeColorOrange => 'Orange';

  @override
  String get settingsThemeColorRed => 'Red';

  @override
  String get settingsThemeColorTeal => 'Teal';

  @override
  String get settingsThemeColorPink => 'Pink';

  @override
  String get settingsAmoledLabel => 'AMOLED (true black) dark mode';

  @override
  String get settingsAppLockSection => 'App lock';

  @override
  String get settingsAppLockEntry => 'Manage app lock';

  @override
  String get settingsAboutSection => 'About';

  @override
  String get settingsAboutEntry => 'About LittleBunny';

  @override
  String get aboutScreenTitle => 'About';

  @override
  String get aboutAppDescription =>
      'An e621 + Inkbunny viewer and manager: saved searches that update on a schedule, mark unseen posts, mass like/favorite/download, comment, and keep everything in sync across devices -- with a fully offline standalone mode too.';

  @override
  String aboutBuildNumber(int buildNumber) {
    return 'Build $buildNumber';
  }

  @override
  String get aboutLocalBuild => 'Local build';

  @override
  String get aboutSourceLink => 'View source on GitHub';

  @override
  String get aboutLicensesEntry => 'Open source licenses';

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
  String get settingsImagePreloadCountLabel =>
      'Images to preload (each direction)';

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

  @override
  String updateAvailableTitle(String tagName) {
    return 'Update available ($tagName)';
  }

  @override
  String get updateDownloadingMessage => 'Downloading update...';

  @override
  String get updateFailedMessage =>
      'Update failed. Try again later, or update manually from the project\'s GitHub releases page.';

  @override
  String get updateLaterAction => 'Later';

  @override
  String get updateNowAction => 'Update';
}
