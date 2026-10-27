import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The app's title, used as MaterialApp.title.
  ///
  /// In en, this message translates to:
  /// **'LittleBunny'**
  String get appTitle;

  /// No description provided for @commonRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get commonRequired;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @setupScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up LittleBunny'**
  String get setupScreenTitle;

  /// No description provided for @setupModeStandalone.
  ///
  /// In en, this message translates to:
  /// **'Standalone'**
  String get setupModeStandalone;

  /// No description provided for @setupModeNetworked.
  ///
  /// In en, this message translates to:
  /// **'Networked'**
  String get setupModeNetworked;

  /// No description provided for @setupStandaloneDescription.
  ///
  /// In en, this message translates to:
  /// **'Stores everything locally on this device. No server needed.'**
  String get setupStandaloneDescription;

  /// No description provided for @setupServerUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get setupServerUrlLabel;

  /// No description provided for @setupServerUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://192.168.1.10:8443'**
  String get setupServerUrlHint;

  /// No description provided for @setupServerUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid URL'**
  String get setupServerUrlInvalid;

  /// No description provided for @setupBearerTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'Bearer token'**
  String get setupBearerTokenLabel;

  /// No description provided for @setupCertFingerprintLabel.
  ///
  /// In en, this message translates to:
  /// **'Certificate SHA-256 fingerprint'**
  String get setupCertFingerprintLabel;

  /// No description provided for @setupPasteConnectionInfo.
  ///
  /// In en, this message translates to:
  /// **'Paste connection info'**
  String get setupPasteConnectionInfo;

  /// No description provided for @setupScanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get setupScanQrCode;

  /// No description provided for @setupConnectionQrInvalid.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read connection info from that'**
  String get setupConnectionQrInvalid;

  /// No description provided for @setupReconfigureTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch connection'**
  String get setupReconfigureTitle;

  /// No description provided for @setupSwitchWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch data source?'**
  String get setupSwitchWarningTitle;

  /// No description provided for @setupSwitchWarningMessage.
  ///
  /// In en, this message translates to:
  /// **'Standalone and networked mode use separate data stores -- your current searches/accounts won\'t automatically carry over. Use Settings → Backup to export/import searches if you want to bring them along.'**
  String get setupSwitchWarningMessage;

  /// No description provided for @setupSwitchConfirm.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get setupSwitchConfirm;

  /// No description provided for @loginScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Log in to {site}'**
  String loginScreenTitle(String site);

  /// No description provided for @loginUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get loginUsernameLabel;

  /// No description provided for @loginApiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get loginApiKeyLabel;

  /// No description provided for @loginPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPasswordLabel;

  /// No description provided for @loginSubmit.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get loginSubmit;

  /// No description provided for @accountsScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accountsScreenTitle;

  /// No description provided for @accountsRemoveDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove account?'**
  String get accountsRemoveDialogTitle;

  /// No description provided for @accountsRemoveDialogContent.
  ///
  /// In en, this message translates to:
  /// **'This removes the saved {site} account from this app. You can log in again later.'**
  String accountsRemoveDialogContent(String site);

  /// No description provided for @accountsLoggedInAs.
  ///
  /// In en, this message translates to:
  /// **'Logged in as {username}'**
  String accountsLoggedInAs(String username);

  /// No description provided for @accountsNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get accountsNotConnected;

  /// No description provided for @accountsMyFavoritesTooltip.
  ///
  /// In en, this message translates to:
  /// **'View my favorites'**
  String get accountsMyFavoritesTooltip;

  /// No description provided for @accountsMyFavoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'My favorites'**
  String get accountsMyFavoritesTitle;

  /// No description provided for @accountsFavoritesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} favorites'**
  String accountsFavoritesCount(int count);

  /// No description provided for @accountsSyncFavoritesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sync favorites now'**
  String get accountsSyncFavoritesTooltip;

  /// No description provided for @searchesScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Searches'**
  String get searchesScreenTitle;

  /// No description provided for @searchesAccountsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get searchesAccountsTooltip;

  /// No description provided for @searchesSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get searchesSettingsTooltip;

  /// No description provided for @searchesTagStatsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Tag stats'**
  String get searchesTagStatsTooltip;

  /// No description provided for @searchesNewSearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'New search'**
  String get searchesNewSearchTooltip;

  /// No description provided for @searchesEmptyState.
  ///
  /// In en, this message translates to:
  /// **'No saved searches yet. Tap + to add one.'**
  String get searchesEmptyState;

  /// No description provided for @searchesIntervalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{site} • every {hours}h • {total} posts'**
  String searchesIntervalSubtitle(String site, int hours, int total);

  /// No description provided for @searchesPinTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get searchesPinTooltip;

  /// No description provided for @searchesUnpinTooltip.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get searchesUnpinTooltip;

  /// No description provided for @searchesSyncRowTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get searchesSyncRowTooltip;

  /// No description provided for @searchesRemoveDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove search?'**
  String get searchesRemoveDialogTitle;

  /// No description provided for @searchesRemoveDialogContent.
  ///
  /// In en, this message translates to:
  /// **'This removes the saved search \"{label}\" from this app.'**
  String searchesRemoveDialogContent(String label);

  /// No description provided for @searchesTabSearches.
  ///
  /// In en, this message translates to:
  /// **'Searches'**
  String get searchesTabSearches;

  /// No description provided for @searchesTabPools.
  ///
  /// In en, this message translates to:
  /// **'Pools'**
  String get searchesTabPools;

  /// No description provided for @searchesPoolsEmptyState.
  ///
  /// In en, this message translates to:
  /// **'No saved pools yet. Tap + to add one.'**
  String get searchesPoolsEmptyState;

  /// No description provided for @searchesFavoritesLabel.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get searchesFavoritesLabel;

  /// No description provided for @searchesNewPoolTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add pool'**
  String get searchesNewPoolTooltip;

  /// No description provided for @searchesSortTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get searchesSortTooltip;

  /// No description provided for @searchesSortMostUnseen.
  ///
  /// In en, this message translates to:
  /// **'Most unseen'**
  String get searchesSortMostUnseen;

  /// No description provided for @searchesSortLabel.
  ///
  /// In en, this message translates to:
  /// **'Label (A-Z)'**
  String get searchesSortLabel;

  /// No description provided for @searchesSortRecentlyCreated.
  ///
  /// In en, this message translates to:
  /// **'Recently created'**
  String get searchesSortRecentlyCreated;

  /// No description provided for @searchesSortLastViewed.
  ///
  /// In en, this message translates to:
  /// **'Last viewed'**
  String get searchesSortLastViewed;

  /// No description provided for @searchesCheckForUpdatesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get searchesCheckForUpdatesTooltip;

  /// No description provided for @searchesDownloadQueueTooltip.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get searchesDownloadQueueTooltip;

  /// No description provided for @searchesSyncAllProgress.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} checked'**
  String searchesSyncAllProgress(int done, int total);

  /// No description provided for @searchesSyncInProgress.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get searchesSyncInProgress;

  /// No description provided for @searchesNewGroupTooltip.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get searchesNewGroupTooltip;

  /// No description provided for @searchesGroupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get searchesGroupNameLabel;

  /// No description provided for @searchesCreateGroupDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get searchesCreateGroupDialogTitle;

  /// No description provided for @searchesCreateGroupSubmit.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get searchesCreateGroupSubmit;

  /// No description provided for @searchesRenameGroupDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get searchesRenameGroupDialogTitle;

  /// No description provided for @searchesRenameGroupSubmit.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get searchesRenameGroupSubmit;

  /// No description provided for @searchesRenameGroupMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get searchesRenameGroupMenuItem;

  /// No description provided for @searchesDeleteGroupMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get searchesDeleteGroupMenuItem;

  /// No description provided for @searchesDeleteGroupDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete group?'**
  String get searchesDeleteGroupDialogTitle;

  /// No description provided for @searchesDeleteGroupDialogContent.
  ///
  /// In en, this message translates to:
  /// **'Searches in \"{name}\" will be ungrouped, not deleted.'**
  String searchesDeleteGroupDialogContent(String name);

  /// No description provided for @searchesGroupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{total} posts'**
  String searchesGroupSubtitle(int total);

  /// No description provided for @searchesDuplicatesBannerMessage.
  ///
  /// In en, this message translates to:
  /// **'{count} duplicate searches found.'**
  String searchesDuplicatesBannerMessage(int count);

  /// No description provided for @searchesDuplicatesBannerReviewAction.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get searchesDuplicatesBannerReviewAction;

  /// No description provided for @searchesDuplicatesBannerDismissTooltip.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get searchesDuplicatesBannerDismissTooltip;

  /// No description provided for @searchesResolveDuplicatesDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Duplicate searches'**
  String get searchesResolveDuplicatesDialogTitle;

  /// No description provided for @searchesResolveDuplicatesGroupHeading.
  ///
  /// In en, this message translates to:
  /// **'{site}: {query}'**
  String searchesResolveDuplicatesGroupHeading(String site, String query);

  /// No description provided for @searchesResolveDuplicatesKeepButton.
  ///
  /// In en, this message translates to:
  /// **'Keep this one'**
  String get searchesResolveDuplicatesKeepButton;

  /// No description provided for @searchesResolveDuplicatesIntervalLabel.
  ///
  /// In en, this message translates to:
  /// **'Every {hours}h'**
  String searchesResolveDuplicatesIntervalLabel(int hours);

  /// No description provided for @searchesResolveDuplicatesPinnedLabel.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get searchesResolveDuplicatesPinnedLabel;

  /// No description provided for @searchesResolveDuplicatesGroupLabel.
  ///
  /// In en, this message translates to:
  /// **'Group: {name}'**
  String searchesResolveDuplicatesGroupLabel(String name);

  /// No description provided for @searchesResolveDuplicatesDoneButton.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get searchesResolveDuplicatesDoneButton;

  /// No description provided for @tagStatsScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Tag stats'**
  String get tagStatsScreenTitle;

  /// No description provided for @tagStatsRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh now'**
  String get tagStatsRefreshTooltip;

  /// No description provided for @tagStatsLastUpdatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String tagStatsLastUpdatedLabel(String time);

  /// No description provided for @tagStatsBuildingLabel.
  ///
  /// In en, this message translates to:
  /// **'Building the report for the first time -- check back shortly.'**
  String get tagStatsBuildingLabel;

  /// No description provided for @tagStatsTopFavoritedTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Top favorited tags'**
  String get tagStatsTopFavoritedTagsLabel;

  /// No description provided for @tagStatsTopUsedTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Top used tags'**
  String get tagStatsTopUsedTagsLabel;

  /// No description provided for @tagStatsTopPoolsLabel.
  ///
  /// In en, this message translates to:
  /// **'Top pools (by favorited posts)'**
  String get tagStatsTopPoolsLabel;

  /// No description provided for @tagStatsTopViewedSearchesLabel.
  ///
  /// In en, this message translates to:
  /// **'Most-visited searches'**
  String get tagStatsTopViewedSearchesLabel;

  /// No description provided for @tagStatsSectionEmptyState.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get tagStatsSectionEmptyState;

  /// No description provided for @createSearchScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'New search'**
  String get createSearchScreenTitle;

  /// No description provided for @createSearchLabelField.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get createSearchLabelField;

  /// No description provided for @createSearchQueryField.
  ///
  /// In en, this message translates to:
  /// **'Query'**
  String get createSearchQueryField;

  /// No description provided for @createSearchIntervalLabel.
  ///
  /// In en, this message translates to:
  /// **'Sync interval (hours)'**
  String get createSearchIntervalLabel;

  /// No description provided for @createSearchUsesDefaultIntervalLabel.
  ///
  /// In en, this message translates to:
  /// **'Use default interval'**
  String get createSearchUsesDefaultIntervalLabel;

  /// No description provided for @createSearchGroupLabel.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get createSearchGroupLabel;

  /// No description provided for @createSearchGroupNone.
  ///
  /// In en, this message translates to:
  /// **'No group'**
  String get createSearchGroupNone;

  /// No description provided for @createSearchAutoFavoriteLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto-favorite new posts'**
  String get createSearchAutoFavoriteLabel;

  /// No description provided for @createSearchAutoUpvoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto-upvote new posts'**
  String get createSearchAutoUpvoteLabel;

  /// No description provided for @createSearchSubmit.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createSearchSubmit;

  /// No description provided for @createPoolSearchDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add pool'**
  String get createPoolSearchDialogTitle;

  /// No description provided for @createPoolSearchIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Pool ID'**
  String get createPoolSearchIdLabel;

  /// No description provided for @createPoolSearchSubmit.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get createPoolSearchSubmit;

  /// No description provided for @createPoolSearchAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'This pool is already saved.'**
  String get createPoolSearchAlreadyExists;

  /// No description provided for @editSearchScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit search'**
  String get editSearchScreenTitle;

  /// No description provided for @editSearchSiteLabel.
  ///
  /// In en, this message translates to:
  /// **'Site: {site}'**
  String editSearchSiteLabel(String site);

  /// No description provided for @editSearchStarsLabel.
  ///
  /// In en, this message translates to:
  /// **'Favorite level'**
  String get editSearchStarsLabel;

  /// No description provided for @editSearchSubmit.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get editSearchSubmit;

  /// No description provided for @editSearchDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete search'**
  String get editSearchDeleteTooltip;

  /// No description provided for @postGridUnseenOnlyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show unseen only'**
  String get postGridUnseenOnlyTooltip;

  /// No description provided for @postGridRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get postGridRefreshTooltip;

  /// No description provided for @postGridEmptyState.
  ///
  /// In en, this message translates to:
  /// **'No posts cached yet. Tap refresh to sync.'**
  String get postGridEmptyState;

  /// No description provided for @postGridMarkAllSeen.
  ///
  /// In en, this message translates to:
  /// **'Mark all as seen'**
  String get postGridMarkAllSeen;

  /// No description provided for @postGridSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get postGridSelectAll;

  /// No description provided for @postGridSelectionCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String postGridSelectionCount(int count);

  /// No description provided for @postGridExitSelectionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cancel selection'**
  String get postGridExitSelectionTooltip;

  /// No description provided for @postGridMassFavoriteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Favorite selected'**
  String get postGridMassFavoriteTooltip;

  /// No description provided for @postGridMassUpvoteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Upvote selected'**
  String get postGridMassUpvoteTooltip;

  /// No description provided for @postGridMassDownvoteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Downvote selected'**
  String get postGridMassDownvoteTooltip;

  /// No description provided for @postGridMassDownloadTooltip.
  ///
  /// In en, this message translates to:
  /// **'Download selected'**
  String get postGridMassDownloadTooltip;

  /// No description provided for @postGridMassDownloadQueued.
  ///
  /// In en, this message translates to:
  /// **'{count} queued for download'**
  String postGridMassDownloadQueued(int count);

  /// No description provided for @tagBrowseEmptyState.
  ///
  /// In en, this message translates to:
  /// **'No posts found for this search.'**
  String get tagBrowseEmptyState;

  /// No description provided for @tagBrowseAddToSearchesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save as a search'**
  String get tagBrowseAddToSearchesTooltip;

  /// No description provided for @tagBrowseAlreadySavedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Already saved -- tap to remove'**
  String get tagBrowseAlreadySavedTooltip;

  /// No description provided for @tagBrowseRelatedPoolChip.
  ///
  /// In en, this message translates to:
  /// **'Pool #{poolId}'**
  String tagBrowseRelatedPoolChip(int poolId);

  /// No description provided for @postGridPoolInfoTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pool info'**
  String get postGridPoolInfoTooltip;

  /// No description provided for @postGridPoolInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Pool information'**
  String get postGridPoolInfoTitle;

  /// No description provided for @postGridPoolInfoPostCount.
  ///
  /// In en, this message translates to:
  /// **'{count} posts'**
  String postGridPoolInfoPostCount(int count);

  /// No description provided for @postGridPoolInfoNoDescription.
  ///
  /// In en, this message translates to:
  /// **'No description.'**
  String get postGridPoolInfoNoDescription;

  /// No description provided for @postGridPoolInfoCloseButton.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get postGridPoolInfoCloseButton;

  /// No description provided for @postDetailScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get postDetailScreenTitle;

  /// No description provided for @postDetailUnsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'This file format ({extension}) isn\'t supported yet'**
  String postDetailUnsupportedFormat(String extension);

  /// No description provided for @postDetailTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get postDetailTitleLabel;

  /// No description provided for @postDetailDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get postDetailDescriptionLabel;

  /// No description provided for @postDetailCommentsLabel.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get postDetailCommentsLabel;

  /// No description provided for @postDetailDimensionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Dimensions'**
  String get postDetailDimensionsLabel;

  /// No description provided for @postDetailCreatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Posted'**
  String get postDetailCreatedLabel;

  /// No description provided for @postDetailUnknownValue.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get postDetailUnknownValue;

  /// No description provided for @postDetailIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Post ID'**
  String get postDetailIdLabel;

  /// No description provided for @postDetailIdCopied.
  ///
  /// In en, this message translates to:
  /// **'Post ID copied to clipboard'**
  String get postDetailIdCopied;

  /// No description provided for @postDetailTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get postDetailTagsLabel;

  /// No description provided for @postDetailSourcesLabel.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get postDetailSourcesLabel;

  /// No description provided for @postDetailParentLabel.
  ///
  /// In en, this message translates to:
  /// **'Parent'**
  String get postDetailParentLabel;

  /// No description provided for @postDetailChildrenLabel.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get postDetailChildrenLabel;

  /// No description provided for @postDetailPoolsLabel.
  ///
  /// In en, this message translates to:
  /// **'Pools'**
  String get postDetailPoolsLabel;

  /// No description provided for @postDetailOpenPostFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open that post'**
  String get postDetailOpenPostFailed;

  /// No description provided for @postDetailBlacklistedDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Blacklisted tag'**
  String get postDetailBlacklistedDialogTitle;

  /// No description provided for @postDetailBlacklistedDialogContent.
  ///
  /// In en, this message translates to:
  /// **'This post has a blacklisted tag: {tags}'**
  String postDetailBlacklistedDialogContent(String tags);

  /// No description provided for @postDetailBlacklistedViewAnyway.
  ///
  /// In en, this message translates to:
  /// **'View anyway'**
  String get postDetailBlacklistedViewAnyway;

  /// No description provided for @postDetailActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send that action -- it wasn\'t saved'**
  String get postDetailActionFailed;

  /// No description provided for @postDetailFavoriteAddTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get postDetailFavoriteAddTooltip;

  /// No description provided for @postDetailFavoriteRemoveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get postDetailFavoriteRemoveTooltip;

  /// No description provided for @postDetailUpvoteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Upvote'**
  String get postDetailUpvoteTooltip;

  /// No description provided for @postDetailDownvoteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Downvote'**
  String get postDetailDownvoteTooltip;

  /// No description provided for @postDetailFavoriteStarsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Favorite ({stars}/3 hearts)'**
  String postDetailFavoriteStarsTooltip(int stars);

  /// No description provided for @postDetailFavoriteStarsRemoveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove favorite'**
  String get postDetailFavoriteStarsRemoveTooltip;

  /// No description provided for @postDetailCommentsSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Discussion'**
  String get postDetailCommentsSectionLabel;

  /// No description provided for @postDetailNoCommentsYet.
  ///
  /// In en, this message translates to:
  /// **'No comments yet.'**
  String get postDetailNoCommentsYet;

  /// No description provided for @postDetailCommentFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Add a comment'**
  String get postDetailCommentFieldLabel;

  /// No description provided for @postDetailCommentAnonymousLabel.
  ///
  /// In en, this message translates to:
  /// **'Post anonymously'**
  String get postDetailCommentAnonymousLabel;

  /// No description provided for @postDetailCommentSubmit.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get postDetailCommentSubmit;

  /// No description provided for @postDetailCommentPostFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t post that comment'**
  String get postDetailCommentPostFailed;

  /// No description provided for @lockScreenMessage.
  ///
  /// In en, this message translates to:
  /// **'LittleBunny is locked'**
  String get lockScreenMessage;

  /// No description provided for @lockScreenBiometricReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock LittleBunny'**
  String get lockScreenBiometricReason;

  /// No description provided for @lockScreenPinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN/password'**
  String get lockScreenPinLabel;

  /// No description provided for @lockScreenUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get lockScreenUnlock;

  /// No description provided for @lockScreenTryFingerprintAgain.
  ///
  /// In en, this message translates to:
  /// **'Try fingerprint again'**
  String get lockScreenTryFingerprintAgain;

  /// No description provided for @lockScreenIncorrectPin.
  ///
  /// In en, this message translates to:
  /// **'Incorrect PIN/password'**
  String get lockScreenIncorrectPin;

  /// No description provided for @lockSetupScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get lockSetupScreenTitle;

  /// No description provided for @lockSetupDescription.
  ///
  /// In en, this message translates to:
  /// **'Set a PIN or password to lock this app on startup.'**
  String get lockSetupDescription;

  /// No description provided for @lockSetupNewPinLabel.
  ///
  /// In en, this message translates to:
  /// **'New PIN/password'**
  String get lockSetupNewPinLabel;

  /// No description provided for @lockSetupConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get lockSetupConfirmLabel;

  /// No description provided for @lockSetupEntriesDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Entries do not match'**
  String get lockSetupEntriesDoNotMatch;

  /// No description provided for @lockSetupEnableButton.
  ///
  /// In en, this message translates to:
  /// **'Enable app lock'**
  String get lockSetupEnableButton;

  /// No description provided for @lockSetupCurrentlyOn.
  ///
  /// In en, this message translates to:
  /// **'App lock is currently on.'**
  String get lockSetupCurrentlyOn;

  /// No description provided for @lockSetupCurrentPinLabel.
  ///
  /// In en, this message translates to:
  /// **'Enter current PIN/password to disable'**
  String get lockSetupCurrentPinLabel;

  /// No description provided for @lockSetupDisableButton.
  ///
  /// In en, this message translates to:
  /// **'Disable app lock'**
  String get lockSetupDisableButton;

  /// No description provided for @settingsScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsScreenTitle;

  /// No description provided for @settingsConnectionSection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsConnectionSection;

  /// No description provided for @settingsConnectionEntry.
  ///
  /// In en, this message translates to:
  /// **'Switch connection mode'**
  String get settingsConnectionEntry;

  /// No description provided for @settingsConnectionStandalone.
  ///
  /// In en, this message translates to:
  /// **'Standalone'**
  String get settingsConnectionStandalone;

  /// No description provided for @settingsConnectionNetworked.
  ///
  /// In en, this message translates to:
  /// **'Networked ({serverUrl})'**
  String settingsConnectionNetworked(String serverUrl);

  /// No description provided for @settingsServerLogsEntry.
  ///
  /// In en, this message translates to:
  /// **'Server logs'**
  String get settingsServerLogsEntry;

  /// No description provided for @serverLogsScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Server logs'**
  String get serverLogsScreenTitle;

  /// No description provided for @serverLogsEmptyState.
  ///
  /// In en, this message translates to:
  /// **'No log lines yet.'**
  String get serverLogsEmptyState;

  /// No description provided for @serverLogsRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get serverLogsRefreshTooltip;

  /// No description provided for @settingsTaskQueueEntry.
  ///
  /// In en, this message translates to:
  /// **'Task queue'**
  String get settingsTaskQueueEntry;

  /// No description provided for @settingsShareConnectionQr.
  ///
  /// In en, this message translates to:
  /// **'Share connection QR'**
  String get settingsShareConnectionQr;

  /// No description provided for @connectionQrScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection QR'**
  String get connectionQrScreenTitle;

  /// No description provided for @connectionQrLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the connection QR: {error}'**
  String connectionQrLoadError(String error);

  /// No description provided for @taskQueueScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Task queue'**
  String get taskQueueScreenTitle;

  /// No description provided for @taskQueueEmptyState.
  ///
  /// In en, this message translates to:
  /// **'Nothing queued right now.'**
  String get taskQueueEmptyState;

  /// No description provided for @taskQueuePriorityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get taskQueuePriorityHigh;

  /// No description provided for @taskQueuePriorityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get taskQueuePriorityMedium;

  /// No description provided for @taskQueuePriorityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get taskQueuePriorityLow;

  /// No description provided for @taskQueueStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get taskQueueStatusRunning;

  /// No description provided for @taskQueueStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get taskQueueStatusPending;

  /// No description provided for @settingsAppearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceSection;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get settingsThemeColorLabel;

  /// No description provided for @settingsThemeColorPurple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get settingsThemeColorPurple;

  /// No description provided for @settingsThemeColorBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get settingsThemeColorBlue;

  /// No description provided for @settingsThemeColorGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get settingsThemeColorGreen;

  /// No description provided for @settingsThemeColorOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get settingsThemeColorOrange;

  /// No description provided for @settingsThemeColorRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get settingsThemeColorRed;

  /// No description provided for @settingsThemeColorTeal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get settingsThemeColorTeal;

  /// No description provided for @settingsThemeColorPink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get settingsThemeColorPink;

  /// No description provided for @settingsAmoledLabel.
  ///
  /// In en, this message translates to:
  /// **'AMOLED (true black) dark mode'**
  String get settingsAmoledLabel;

  /// No description provided for @settingsLanguageSection.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageSection;

  /// No description provided for @settingsLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageLabel;

  /// No description provided for @settingsLanguageSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystemDefault;

  /// No description provided for @settingsAppLockSection.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get settingsAppLockSection;

  /// No description provided for @settingsAppLockEntry.
  ///
  /// In en, this message translates to:
  /// **'Manage app lock'**
  String get settingsAppLockEntry;

  /// No description provided for @settingsAboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutSection;

  /// No description provided for @settingsAboutEntry.
  ///
  /// In en, this message translates to:
  /// **'About LittleBunny'**
  String get settingsAboutEntry;

  /// No description provided for @aboutScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutScreenTitle;

  /// No description provided for @aboutAppDescription.
  ///
  /// In en, this message translates to:
  /// **'An e621 + Inkbunny viewer and manager: saved searches that update on a schedule, mark unseen posts, mass like/favorite/download, comment, and keep everything in sync across devices -- with a fully offline standalone mode too.'**
  String get aboutAppDescription;

  /// No description provided for @aboutBuildNumber.
  ///
  /// In en, this message translates to:
  /// **'Build {buildNumber}'**
  String aboutBuildNumber(int buildNumber);

  /// No description provided for @aboutLocalBuild.
  ///
  /// In en, this message translates to:
  /// **'Local build'**
  String get aboutLocalBuild;

  /// No description provided for @aboutSourceLink.
  ///
  /// In en, this message translates to:
  /// **'View source on GitHub'**
  String get aboutSourceLink;

  /// No description provided for @aboutLicensesEntry.
  ///
  /// In en, this message translates to:
  /// **'Open source licenses'**
  String get aboutLicensesEntry;

  /// No description provided for @settingsSyncSection.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get settingsSyncSection;

  /// No description provided for @settingsDefaultIntervalLabel.
  ///
  /// In en, this message translates to:
  /// **'Default sync interval (hours)'**
  String get settingsDefaultIntervalLabel;

  /// No description provided for @settingsDisplaySection.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get settingsDisplaySection;

  /// No description provided for @settingsPreviewQualityThumbnail.
  ///
  /// In en, this message translates to:
  /// **'Thumbnail'**
  String get settingsPreviewQualityThumbnail;

  /// No description provided for @settingsPreviewQualityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get settingsPreviewQualityMedium;

  /// No description provided for @settingsGridColumnsLabel.
  ///
  /// In en, this message translates to:
  /// **'Grid columns'**
  String get settingsGridColumnsLabel;

  /// No description provided for @settingsImagePreloadCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Images to preload (each direction)'**
  String get settingsImagePreloadCountLabel;

  /// No description provided for @settingsDownloadsSection.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get settingsDownloadsSection;

  /// No description provided for @settingsDownloadsFolderLabel.
  ///
  /// In en, this message translates to:
  /// **'Destination folder'**
  String get settingsDownloadsFolderLabel;

  /// No description provided for @settingsDownloadsFolderUnset.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get settingsDownloadsFolderUnset;

  /// No description provided for @settingsDownloadsChooseFolderButton.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get settingsDownloadsChooseFolderButton;

  /// No description provided for @settingsAutoFavoriteOnDownloadLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto-favorite on download'**
  String get settingsAutoFavoriteOnDownloadLabel;

  /// No description provided for @settingsAutoUpvoteOnDownloadLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto-upvote on download'**
  String get settingsAutoUpvoteOnDownloadLabel;

  /// No description provided for @settingsBackupSection.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get settingsBackupSection;

  /// No description provided for @settingsBackupExportLabel.
  ///
  /// In en, this message translates to:
  /// **'Export searches'**
  String get settingsBackupExportLabel;

  /// No description provided for @settingsBackupExportButton.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get settingsBackupExportButton;

  /// No description provided for @settingsBackupImportLabel.
  ///
  /// In en, this message translates to:
  /// **'Import searches'**
  String get settingsBackupImportLabel;

  /// No description provided for @settingsBackupImportButton.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get settingsBackupImportButton;

  /// No description provided for @settingsBackupImportProgress.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} imported'**
  String settingsBackupImportProgress(int done, int total);

  /// No description provided for @settingsBackupExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Exported {count} searches'**
  String settingsBackupExportSuccess(int count);

  /// No description provided for @settingsBackupImportSummary.
  ///
  /// In en, this message translates to:
  /// **'{imported} imported, {duplicates} already saved, {invalid} invalid'**
  String settingsBackupImportSummary(int imported, int duplicates, int invalid);

  /// No description provided for @settingsBackupImportUnrecognizedFormat.
  ///
  /// In en, this message translates to:
  /// **'Unrecognized file format'**
  String get settingsBackupImportUnrecognizedFormat;

  /// No description provided for @settingsBlacklistSection.
  ///
  /// In en, this message translates to:
  /// **'Blacklist'**
  String get settingsBlacklistSection;

  /// No description provided for @settingsBlacklistEmpty.
  ///
  /// In en, this message translates to:
  /// **'No blacklisted tags yet.'**
  String get settingsBlacklistEmpty;

  /// No description provided for @settingsBlacklistAddLabel.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get settingsBlacklistAddLabel;

  /// No description provided for @settingsBlacklistSyncE621Button.
  ///
  /// In en, this message translates to:
  /// **'Sync from e621'**
  String get settingsBlacklistSyncE621Button;

  /// No description provided for @settingsBlacklistSyncE621Result.
  ///
  /// In en, this message translates to:
  /// **'Added {added}, {alreadyPresent} already present, skipped {skippedMultiTag} multi-tag rule(s)'**
  String settingsBlacklistSyncE621Result(
    int added,
    int alreadyPresent,
    int skippedMultiTag,
  );

  /// No description provided for @settingsBlacklistSyncE621Failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sync from e621 -- check that an e621 account is configured'**
  String get settingsBlacklistSyncE621Failed;

  /// No description provided for @postDetailDownloadTooltip.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get postDetailDownloadTooltip;

  /// No description provided for @postDetailDownloadQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued for download'**
  String get postDetailDownloadQueued;

  /// No description provided for @downloadQueueScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloadQueueScreenTitle;

  /// No description provided for @downloadQueueDownloadingLabel.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get downloadQueueDownloadingLabel;

  /// No description provided for @downloadQueueQueuedLabel.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get downloadQueueQueuedLabel;

  /// No description provided for @downloadQueueFailedLabel.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get downloadQueueFailedLabel;

  /// No description provided for @downloadQueueEmptyState.
  ///
  /// In en, this message translates to:
  /// **'Nothing here right now.'**
  String get downloadQueueEmptyState;

  /// No description provided for @downloadQueueRetryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get downloadQueueRetryTooltip;

  /// No description provided for @downloadQueueRetryAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Retry all'**
  String get downloadQueueRetryAllTooltip;

  /// No description provided for @downloadQueueClearFinishedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear finished'**
  String get downloadQueueClearFinishedTooltip;

  /// No description provided for @downloadQueueChecksumMismatchReason.
  ///
  /// In en, this message translates to:
  /// **'Downloaded, but the checksum didn\'t match'**
  String get downloadQueueChecksumMismatchReason;

  /// No description provided for @updateAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Update available ({tagName})'**
  String updateAvailableTitle(String tagName);

  /// No description provided for @updateDownloadingMessage.
  ///
  /// In en, this message translates to:
  /// **'Downloading update...'**
  String get updateDownloadingMessage;

  /// No description provided for @updateFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Update failed. Try again later, or update manually from the project\'s GitHub releases page.'**
  String get updateFailedMessage;

  /// No description provided for @updateLaterAction.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLaterAction;

  /// No description provided for @updateNowAction.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateNowAction;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
