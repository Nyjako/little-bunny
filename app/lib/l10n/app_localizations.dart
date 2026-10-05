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
  /// **'{site} • every {hours}h'**
  String searchesIntervalSubtitle(String site, int hours);

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

  /// No description provided for @searchesNewPoolTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add pool'**
  String get searchesNewPoolTooltip;

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

  /// No description provided for @postGridMassDownloadProgress.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} downloaded'**
  String postGridMassDownloadProgress(int done, int total);

  /// No description provided for @postGridMassDownloadSummary.
  ///
  /// In en, this message translates to:
  /// **'{succeeded} downloaded, {mismatched} checksum mismatch, {failed} failed'**
  String postGridMassDownloadSummary(int succeeded, int mismatched, int failed);

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

  /// No description provided for @postDetailArtistLabel.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get postDetailArtistLabel;

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

  /// No description provided for @postDetailRatingLabel.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get postDetailRatingLabel;

  /// No description provided for @postDetailScoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get postDetailScoreLabel;

  /// No description provided for @postDetailFavoritesLabel.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get postDetailFavoritesLabel;

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

  /// No description provided for @postDetailCreatePoolSearchDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add pool'**
  String get postDetailCreatePoolSearchDialogTitle;

  /// No description provided for @postDetailCreatePoolSearchDialogContent.
  ///
  /// In en, this message translates to:
  /// **'This post belongs to pool {poolId}, but there\'s no saved search for it yet. Create one?'**
  String postDetailCreatePoolSearchDialogContent(int poolId);

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

  /// No description provided for @postDetailDownloadTooltip.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get postDetailDownloadTooltip;

  /// No description provided for @postDetailDownloadVerified.
  ///
  /// In en, this message translates to:
  /// **'Downloaded and checksum verified'**
  String get postDetailDownloadVerified;

  /// No description provided for @postDetailDownloadMismatch.
  ///
  /// In en, this message translates to:
  /// **'Downloaded, but the checksum didn\'t match'**
  String get postDetailDownloadMismatch;

  /// No description provided for @postDetailDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get postDetailDownloadFailed;
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
