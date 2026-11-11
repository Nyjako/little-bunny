// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get appTitle => 'LittleBunny';

  @override
  String get commonRequired => 'Wymagane';

  @override
  String get commonCancel => 'Anuluj';

  @override
  String get commonRemove => 'Usuń';

  @override
  String get commonContinue => 'Kontynuuj';

  @override
  String get commonMustBeANumber => 'Wprowadź liczbę całkowitą';

  @override
  String get setupScreenTitle => 'Konfiguracja LittleBunny';

  @override
  String get setupModeStandalone => 'Samodzielny';

  @override
  String get setupModeNetworked => 'Sieciowy';

  @override
  String get setupStandaloneDescription =>
      'Przechowuje wszystko lokalnie na tym urządzeniu. Serwer nie jest wymagany.';

  @override
  String get setupServerUrlLabel => 'Adres URL serwera';

  @override
  String get setupServerUrlHint => 'https://192.168.1.10:8443';

  @override
  String get setupServerUrlInvalid => 'Wprowadź poprawny adres URL';

  @override
  String get setupBearerTokenLabel => 'Token Bearer';

  @override
  String get setupCertFingerprintLabel => 'Odcisk SHA-256 certyfikatu';

  @override
  String get setupPasteConnectionInfo => 'Wklej informacje o połączeniu';

  @override
  String get setupScanQrCode => 'Skanuj kod QR';

  @override
  String get setupConnectionQrInvalid =>
      'Nie udało się odczytać informacji o połączeniu';

  @override
  String get setupReconfigureTitle => 'Zmień tryb połączenia';

  @override
  String get setupSwitchWarningTitle => 'Zmienić źródło danych?';

  @override
  String get setupSwitchWarningMessage =>
      'Tryby samodzielny i sieciowy używają osobnych magazynów danych — Twoje obecne wyszukiwania i konta nie przeniosą się automatycznie. Użyj Ustawienia → Kopia zapasowa, aby wyeksportować/zaimportować wyszukiwania, jeśli chcesz je przenieść.';

  @override
  String get setupSwitchConfirm => 'Zmień';

  @override
  String loginScreenTitle(String site) {
    return 'Zaloguj się do $site';
  }

  @override
  String get loginUsernameLabel => 'Nazwa użytkownika';

  @override
  String get loginApiKeyLabel => 'Klucz API';

  @override
  String get loginPasswordLabel => 'Hasło';

  @override
  String get loginSubmit => 'Zaloguj się';

  @override
  String get accountsScreenTitle => 'Konta';

  @override
  String get accountsRemoveDialogTitle => 'Usunąć konto?';

  @override
  String accountsRemoveDialogContent(String site) {
    return 'To usunie zapisane konto $site z tej aplikacji. Możesz zalogować się ponownie później.';
  }

  @override
  String accountsLoggedInAs(String username) {
    return 'Zalogowano jako $username';
  }

  @override
  String get accountsNotConnected => 'Nie połączono';

  @override
  String get accountsMyFavoritesTooltip => 'Pokaż moje ulubione';

  @override
  String get accountsMyFavoritesTitle => 'Moje ulubione';

  @override
  String accountsFavoritesCount(int count) {
    return '$count ulubionych';
  }

  @override
  String get accountsSyncFavoritesTooltip => 'Synchronizuj ulubione teraz';

  @override
  String get searchesScreenTitle => 'Wyszukiwania';

  @override
  String get searchesAccountsTooltip => 'Konta';

  @override
  String get searchesSettingsTooltip => 'Ustawienia';

  @override
  String get searchesTagStatsTooltip => 'Statystyki tagów';

  @override
  String get searchesNewSearchTooltip => 'Nowe wyszukiwanie';

  @override
  String get searchesEmptyState =>
      'Brak zapisanych wyszukiwań. Naciśnij +, aby dodać.';

  @override
  String searchesIntervalSubtitle(String site, int hours, int total) {
    return '$site • co ${hours}h • $total postów';
  }

  @override
  String searchesLastUpdatedSubtitle(String duration) {
    return 'Zaktualizowano $duration temu';
  }

  @override
  String get searchesPinTooltip => 'Przypnij';

  @override
  String get searchesUnpinTooltip => 'Odepnij';

  @override
  String get searchesSyncRowTooltip => 'Synchronizuj teraz';

  @override
  String get searchesRowMenuEditLabel => 'Edytuj';

  @override
  String get searchesRowMenuAddToSlideshowLabel => 'Dodaj do pokazu slajdów';

  @override
  String get searchesAddToSlideshowDialogTitle => 'Dodaj do pokazu slajdów';

  @override
  String get searchesNoSlideshowsYet =>
      'Brak pokazów slajdów — najpierw utwórz jakiś.';

  @override
  String searchesAddedToSlideshow(String label) {
    return 'Dodano do „$label”';
  }

  @override
  String get searchesAddSelectedToSlideshowTooltip =>
      'Dodaj wybrane do pokazu slajdów';

  @override
  String searchesAddedSelectedToSlideshow(int count, String label) {
    return 'Dodano $count do „$label”';
  }

  @override
  String get searchesRemoveDialogTitle => 'Usunąć wyszukiwanie?';

  @override
  String searchesRemoveDialogContent(String label) {
    return 'To usunie zapisane wyszukiwanie „$label” z tej aplikacji.';
  }

  @override
  String get searchesTabSearches => 'Wyszukiwania';

  @override
  String get searchesTabPools => 'Zbiory';

  @override
  String get searchesTabSlideshows => 'Pokazy slajdów';

  @override
  String get searchesPoolsEmptyState =>
      'Brak zapisanych zbiorów. Naciśnij +, aby dodać.';

  @override
  String get searchesFavoritesLabel => 'Ulubione';

  @override
  String get searchesNewPoolTooltip => 'Dodaj zbiór';

  @override
  String get searchesSortTooltip => 'Sortuj';

  @override
  String get searchesMoreActionsTooltip => 'Więcej';

  @override
  String get searchesSortMostUnseen => 'Najwięcej niewidzianych';

  @override
  String get searchesSortLabel => 'Nazwa (A–Z)';

  @override
  String get searchesSortRecentlyCreated => 'Ostatnio utworzone';

  @override
  String get searchesSortLastViewed => 'Ostatnio wyświetlane';

  @override
  String get searchesSortLastUpdated => 'Ostatnio zaktualizowane';

  @override
  String get searchesCheckForUpdatesTooltip => 'Sprawdź aktualizacje';

  @override
  String get searchesSelectForDownloadTooltip =>
      'Wybierz wyszukiwania do pobrania';

  @override
  String searchesSelectedCount(int count) {
    return 'Wybrano $count';
  }

  @override
  String get searchesDownloadSelectedTooltip => 'Pobierz wybrane';

  @override
  String searchesMassDownloadQueued(int count) {
    return '$count zakolejkowano do pobrania';
  }

  @override
  String get searchesMassDownloadError =>
      'Nie udało się załadować wszystkich postów dla jednego lub więcej wybranych wyszukiwań. Spróbuj ponownie.';

  @override
  String searchesLoadingPostsDialogTitle(int index, int count) {
    return 'Wczytywanie postów $index/$count';
  }

  @override
  String searchesLoadingPostsSearchProgress(
    String label,
    int loaded,
    int total,
  ) {
    return '$label $loaded/$total';
  }

  @override
  String get searchesDownloadQueueTooltip => 'Pobieranie';

  @override
  String searchesSyncAllProgress(int done, int total) {
    return '$done/$total sprawdzonych';
  }

  @override
  String get searchesSyncInProgress => 'Synchronizacja…';

  @override
  String get searchesNewGroupTooltip => 'Nowa grupa';

  @override
  String get searchesGroupNameLabel => 'Nazwa';

  @override
  String get searchesCreateGroupDialogTitle => 'Nowa grupa';

  @override
  String get searchesCreateGroupSubmit => 'Utwórz';

  @override
  String get searchesRenameGroupDialogTitle => 'Zmień nazwę grupy';

  @override
  String get searchesRenameGroupSubmit => 'Zapisz';

  @override
  String get searchesRenameGroupMenuItem => 'Zmień nazwę';

  @override
  String get searchesDeleteGroupMenuItem => 'Usuń grupę';

  @override
  String get searchesDeleteGroupDialogTitle => 'Usunąć grupę?';

  @override
  String searchesDeleteGroupDialogContent(String name) {
    return 'Wyszukiwania w „$name” zostaną rozgrupowane, a nie usunięte.';
  }

  @override
  String searchesGroupSubtitle(int total) {
    return '$total postów';
  }

  @override
  String searchesDuplicatesBannerMessage(int count) {
    return 'Znaleziono $count zduplikowanych wyszukiwań.';
  }

  @override
  String get searchesDuplicatesBannerReviewAction => 'Przejrzyj';

  @override
  String get searchesDuplicatesBannerDismissTooltip => 'Odrzuć';

  @override
  String get searchesResolveDuplicatesDialogTitle =>
      'Zduplikowane wyszukiwania';

  @override
  String searchesResolveDuplicatesGroupHeading(String site, String query) {
    return '$site: $query';
  }

  @override
  String get searchesResolveDuplicatesKeepButton => 'Zachowaj to';

  @override
  String searchesResolveDuplicatesIntervalLabel(int hours) {
    return 'Co ${hours}h';
  }

  @override
  String get searchesResolveDuplicatesPinnedLabel => 'Przypięte';

  @override
  String searchesResolveDuplicatesGroupLabel(String name) {
    return 'Grupa: $name';
  }

  @override
  String get searchesResolveDuplicatesDoneButton => 'Zamknij';

  @override
  String get tagStatsScreenTitle => 'Statystyki tagów';

  @override
  String get tagStatsRefreshTooltip => 'Odśwież teraz';

  @override
  String tagStatsLastUpdatedLabel(String time) {
    return 'Zaktualizowano $time';
  }

  @override
  String get tagStatsBuildingLabel =>
      'Budowanie raportu po raz pierwszy — zajrzyj wkrótce.';

  @override
  String get tagStatsTopFavoritedTagsLabel =>
      'Najczęściej dodawane do ulubionych tagi';

  @override
  String get tagStatsTopUsedTagsLabel => 'Najczęściej używane tagi';

  @override
  String get tagStatsTopPoolsLabel => 'Najlepsze zbiory (wg ulubionych postów)';

  @override
  String get tagStatsTopViewedSearchesLabel =>
      'Najczęściej odwiedzane wyszukiwania';

  @override
  String get tagStatsSectionEmptyState => 'Na razie nic tu nie ma.';

  @override
  String get createSearchScreenTitle => 'Nowe wyszukiwanie';

  @override
  String get createSearchLabelField => 'Etykieta';

  @override
  String get createSearchQueryField => 'Zapytanie';

  @override
  String get tagQueryInvalidSyntax => 'Nieprawidłowa składnia';

  @override
  String tagAliasHint(String tag, String canonical) {
    return '„$tag” jest aliasem „$canonical”';
  }

  @override
  String get createSearchIntervalLabel => 'Interwał synchronizacji (godziny)';

  @override
  String get createSearchUsesDefaultIntervalLabel =>
      'Użyj domyślnego interwału';

  @override
  String get createSearchGroupLabel => 'Grupa';

  @override
  String get createSearchGroupNone => 'Bez grupy';

  @override
  String get createSearchAutoFavoriteLabel =>
      'Automatycznie dodawaj nowe posty do ulubionych';

  @override
  String get createSearchAutoUpvoteLabel =>
      'Automatycznie głosuj w górę na nowe posty';

  @override
  String get createSearchSubmit => 'Utwórz';

  @override
  String get createPoolSearchDialogTitle => 'Dodaj zbiór';

  @override
  String get createPoolSearchIdLabel => 'ID zbioru';

  @override
  String get createPoolSearchSubmit => 'Dodaj';

  @override
  String get createPoolSearchAlreadyExists => 'Ten zbiór jest już zapisany.';

  @override
  String get editSearchScreenTitle => 'Edytuj wyszukiwanie';

  @override
  String editSearchSiteLabel(String site) {
    return 'Strona: $site';
  }

  @override
  String get editSearchStarsLabel => 'Poziom ulubionych';

  @override
  String get editSearchSubmit => 'Zapisz';

  @override
  String get editSearchDeleteTooltip => 'Usuń wyszukiwanie';

  @override
  String get postGridUnseenOnlyTooltip => 'Pokaż tylko niewidziane';

  @override
  String get postGridFilterTooltip => 'Filtruj wg ratingu / typu mediów';

  @override
  String get postGridFilterRatingLabel => 'Rating';

  @override
  String get postGridFilterRatingSafe => 'Safe';

  @override
  String get postGridFilterRatingQuestionable => 'Questionable';

  @override
  String get postGridFilterRatingExplicit => 'Explicit';

  @override
  String get postGridFilterMediaLabel => 'Typ mediów';

  @override
  String get postGridFilterMediaImage => 'Obraz';

  @override
  String get postGridFilterMediaVideo => 'Wideo';

  @override
  String get postGridFilterMediaGif => 'GIF';

  @override
  String get postGridRefreshTooltip => 'Odśwież';

  @override
  String get postGridEmptyState =>
      'Brak zbuforowanych postów. Naciśnij odśwież, aby zsynchronizować.';

  @override
  String get postGridMarkAllSeen => 'Oznacz wszystkie jako widziane';

  @override
  String get postGridSelectAll => 'Zaznacz wszystkie';

  @override
  String postGridSelectionCount(int count) {
    return 'Wybrano $count';
  }

  @override
  String get postGridExitSelectionTooltip => 'Anuluj zaznaczenie';

  @override
  String get postGridMassFavoriteTooltip => 'Dodaj wybrane do ulubionych';

  @override
  String get postGridMassUpvoteTooltip => 'Głosuj w górę na wybrane';

  @override
  String get postGridMassDownvoteTooltip => 'Głosuj w dół na wybrane';

  @override
  String get postGridMassDownloadTooltip => 'Pobierz wybrane';

  @override
  String postGridMassDownloadQueued(int count) {
    return '$count zakolejkowano do pobrania';
  }

  @override
  String postGridSelectEntireSearch(int count) {
    return 'Zaznacz całe wyszukiwanie ($count)';
  }

  @override
  String get postGridSelectEntireSearchDialogTitle =>
      'Zaznaczanie całego wyszukiwania…';

  @override
  String postGridSelectEntireSearchProgress(int count, int total) {
    return '$count z $total';
  }

  @override
  String get postGridSelectEntireSearchError =>
      'Nie udało się załadować całego wyszukiwania. Spróbuj ponownie.';

  @override
  String get tagBrowseEmptyState =>
      'Nie znaleziono postów dla tego wyszukiwania.';

  @override
  String get tagBrowseAddToSearchesTooltip => 'Zapisz jako wyszukiwanie';

  @override
  String get tagBrowseAlreadySavedTooltip =>
      'Już zapisane — naciśnij, aby usunąć';

  @override
  String tagBrowseRelatedPoolChip(int poolId) {
    return 'Zbiór #$poolId';
  }

  @override
  String get postGridPoolInfoTooltip => 'Informacje o zbiorze';

  @override
  String get postGridPoolInfoTitle => 'Informacje o zbiorze';

  @override
  String postGridPoolInfoPostCount(int count) {
    return '$count postów';
  }

  @override
  String get postGridPoolInfoNoDescription => 'Brak opisu.';

  @override
  String get postGridPoolInfoCloseButton => 'Zamknij';

  @override
  String get postDetailScreenTitle => 'Post';

  @override
  String postDetailUnsupportedFormat(String extension) {
    return 'Ten format pliku ($extension) nie jest jeszcze obsługiwany';
  }

  @override
  String get postDetailOpenExternally => 'Otwórz zewnętrznie';

  @override
  String postDetailAudioTrackLabel(int position) {
    return 'Ścieżka $position';
  }

  @override
  String get postDetailTitleLabel => 'Tytuł';

  @override
  String get postDetailDescriptionLabel => 'Opis';

  @override
  String get postDetailCommentsLabel => 'Komentarze';

  @override
  String get postDetailDimensionsLabel => 'Wymiary';

  @override
  String get postDetailCreatedLabel => 'Opublikowano';

  @override
  String get postDetailUnknownValue => 'Nieznane';

  @override
  String get postDetailIdLabel => 'ID posta';

  @override
  String get postDetailIdCopied => 'ID posta skopiowane do schowka';

  @override
  String get postDetailTagsLabel => 'Tagi';

  @override
  String get postDetailSourcesLabel => 'Źródła';

  @override
  String get postDetailParentLabel => 'Rodzic';

  @override
  String get postDetailChildrenLabel => 'Dzieci';

  @override
  String get postDetailPoolsLabel => 'Zbiory';

  @override
  String get postDetailOpenPostFailed => 'Nie udało się otworzyć tego posta';

  @override
  String get postDetailBlacklistedDialogTitle => 'Tag na czarnej liście';

  @override
  String postDetailBlacklistedDialogContent(String tags) {
    return 'Ten post ma tag na czarnej liście: $tags';
  }

  @override
  String get postDetailBlacklistedViewAnyway => 'Pokaż mimo to';

  @override
  String get postDetailActionFailed =>
      'Nie udało się wykonać tej akcji — nie została zapisana';

  @override
  String get postDetailFavoriteAddTooltip => 'Dodaj do ulubionych';

  @override
  String get postDetailFavoriteRemoveTooltip => 'Usuń z ulubionych';

  @override
  String get postDetailUpvoteTooltip => 'Głos w górę';

  @override
  String get postDetailDownvoteTooltip => 'Głos w dół';

  @override
  String postDetailFavoriteStarsTooltip(int stars) {
    return 'Ulubione ($stars/3 serca)';
  }

  @override
  String get postDetailFavoriteStarsRemoveTooltip => 'Usuń z ulubionych';

  @override
  String get postDetailCommentsSectionLabel => 'Dyskusja';

  @override
  String get postDetailNoCommentsYet => 'Brak komentarzy.';

  @override
  String get postDetailCommentFieldLabel => 'Dodaj komentarz';

  @override
  String get postDetailCommentAnonymousLabel => 'Opublikuj anonimowo';

  @override
  String get postDetailCommentSubmit => 'Opublikuj';

  @override
  String get postDetailCommentPostFailed =>
      'Nie udało się opublikować komentarza';

  @override
  String get lockScreenMessage => 'LittleBunny jest zablokowane';

  @override
  String get lockScreenBiometricReason => 'Odblokuj LittleBunny';

  @override
  String get lockScreenPinLabel => 'Hasło';

  @override
  String get lockScreenUnlock => 'Odblokuj';

  @override
  String get lockScreenTryFingerprintAgain => 'Spróbuj odcisku palca ponownie';

  @override
  String get lockScreenIncorrectPin => 'Nieprawidłowy PIN lub hasło';

  @override
  String get lockScreenEnterPinHeading => 'Wprowadź PIN';

  @override
  String get lockSetupScreenTitle => 'Blokada aplikacji';

  @override
  String get lockSetupDescription =>
      'Ustaw PIN lub hasło, aby blokować aplikację przy starcie.';

  @override
  String get lockSetupModePin => 'PIN';

  @override
  String get lockSetupModePassword => 'Hasło';

  @override
  String get lockSetupPinLengthLabel => 'Długość PIN-u';

  @override
  String get lockSetupNewPinLabel => 'Nowe hasło';

  @override
  String get lockSetupNewPinHeading => 'Wprowadź nowy PIN';

  @override
  String get lockSetupConfirmPinHeading => 'Potwierdź nowy PIN';

  @override
  String get lockSetupBackToNewPin => 'Wstecz';

  @override
  String get lockSetupConfirmLabel => 'Potwierdź';

  @override
  String get lockSetupEntriesDoNotMatch => 'Wpisy się nie zgadzają';

  @override
  String get lockSetupEnableButton => 'Włącz blokadę aplikacji';

  @override
  String get lockSetupCurrentlyOn => 'Blokada aplikacji jest obecnie włączona.';

  @override
  String get lockSetupCurrentPinLabel => 'Wprowadź bieżące hasło, aby wyłączyć';

  @override
  String get lockSetupCurrentPinHeading => 'Wprowadź bieżący PIN, aby wyłączyć';

  @override
  String get lockSetupDisableButton => 'Wyłącz blokadę aplikacji';

  @override
  String get settingsScreenTitle => 'Ustawienia';

  @override
  String get settingsConnectionSection => 'Połączenie';

  @override
  String get settingsConnectionEntry => 'Zmień tryb połączenia';

  @override
  String get settingsConnectionStandalone => 'Samodzielny';

  @override
  String settingsConnectionNetworked(String serverUrl) {
    return 'Sieciowy ($serverUrl)';
  }

  @override
  String get settingsServerLogsEntry => 'Logi serwera';

  @override
  String get serverLogsScreenTitle => 'Logi serwera';

  @override
  String get serverLogsEmptyState => 'Brak linii logów.';

  @override
  String get serverLogsRefreshTooltip => 'Odśwież';

  @override
  String get settingsTaskQueueEntry => 'Kolejka zadań';

  @override
  String get settingsShareConnectionQr => 'Udostępnij kod QR połączenia';

  @override
  String get connectionQrScreenTitle => 'Kod QR połączenia';

  @override
  String connectionQrLoadError(String error) {
    return 'Nie udało się wczytać kodu QR połączenia: $error';
  }

  @override
  String get taskQueueScreenTitle => 'Kolejka zadań';

  @override
  String get taskQueueEmptyState => 'Nic nie jest teraz w kolejce.';

  @override
  String get taskQueuePriorityHigh => 'Wysoki';

  @override
  String get taskQueuePriorityMedium => 'Średni';

  @override
  String get taskQueuePriorityLow => 'Niski';

  @override
  String get taskQueueStatusRunning => 'W trakcie';

  @override
  String get taskQueueStatusPending => 'Oczekuje';

  @override
  String get taskQueueRecentSection => 'Ostatnie';

  @override
  String taskQueueFinishedAgo(String duration) {
    return 'Zakończono $duration temu';
  }

  @override
  String get taskQueueSucceeded => 'Powodzenie';

  @override
  String get taskQueueFailed => 'Niepowodzenie';

  @override
  String get settingsAppearanceSection => 'Wygląd';

  @override
  String get settingsThemeLight => 'Jasny';

  @override
  String get settingsThemeDark => 'Ciemny';

  @override
  String get settingsThemeSystem => 'Systemowy';

  @override
  String get settingsThemeColorLabel => 'Kolor';

  @override
  String get settingsThemeColorPurple => 'Fioletowy';

  @override
  String get settingsThemeColorBlue => 'Niebieski';

  @override
  String get settingsThemeColorGreen => 'Zielony';

  @override
  String get settingsThemeColorOrange => 'Pomarańczowy';

  @override
  String get settingsThemeColorRed => 'Czerwony';

  @override
  String get settingsThemeColorTeal => 'Turkusowy';

  @override
  String get settingsThemeColorPink => 'Różowy';

  @override
  String get settingsAmoledLabel => 'AMOLED (prawdziwa czerń) w trybie ciemnym';

  @override
  String get settingsLanguageSection => 'Język';

  @override
  String get settingsLanguageLabel => 'Język';

  @override
  String get settingsLanguageSystemDefault => 'Domyślny systemowy';

  @override
  String get settingsUpdatesSection => 'Aktualizacje';

  @override
  String get settingsAutoCheckForUpdatesLabel =>
      'Automatycznie sprawdzaj aktualizacje';

  @override
  String get settingsAppLockSection => 'Blokada aplikacji';

  @override
  String get settingsAppLockEntry => 'Zarządzaj blokadą aplikacji';

  @override
  String get settingsAboutSection => 'O aplikacji';

  @override
  String get settingsAboutEntry => 'O LittleBunny';

  @override
  String get aboutScreenTitle => 'O aplikacji';

  @override
  String get aboutAppDescription =>
      'Przeglądarka i menedżer e621 + Inkbunny: zapisane wyszukiwania aktualizowane według harmonogramu, oznaczanie niewidzianych postów, masowe polubienia/ulubione/pobieranie, komentowanie oraz synchronizacja między urządzeniami — z pełnym trybem offline.';

  @override
  String aboutBuildNumber(int buildNumber) {
    return 'Kompilacja $buildNumber';
  }

  @override
  String get aboutLocalBuild => 'Kompilacja lokalna';

  @override
  String get aboutSourceLink => 'Zobacz źródła na GitHubie';

  @override
  String get aboutLicensesEntry => 'Licencje open source';

  @override
  String get aboutCheckForUpdateButton => 'Sprawdź aktualizację aplikacji';

  @override
  String get aboutNoUpdateAvailable => 'Brak dostępnej aktualizacji';

  @override
  String get aboutViewChangelogEntry => 'Zobacz listę zmian';

  @override
  String get changelogScreenTitle => 'Lista zmian';

  @override
  String get changelogEmptyState => 'Brak historii wydań.';

  @override
  String changelogLoadError(String error) {
    return 'Nie udało się wczytać listy zmian: $error';
  }

  @override
  String get settingsSyncSection => 'Synchronizacja';

  @override
  String get settingsDefaultIntervalLabel =>
      'Domyślny interwał synchronizacji (godziny)';

  @override
  String get settingsDisplaySection => 'Wyświetlanie';

  @override
  String get settingsPreviewQualityThumbnail => 'Miniatura';

  @override
  String get settingsPreviewQualityMedium => 'Średnia';

  @override
  String get settingsGridColumnsLabel => 'Kolumny siatki';

  @override
  String get settingsImagePreloadCountLabel =>
      'Obrazy do wstępnego wczytania (w każdym kierunku)';

  @override
  String get settingsDownloadsSection => 'Pobieranie';

  @override
  String get settingsDownloadsFolderLabel => 'Folder docelowy';

  @override
  String get settingsDownloadsFolderUnset => 'Nie ustawiono';

  @override
  String get settingsDownloadsChooseFolderButton => 'Wybierz folder';

  @override
  String get settingsAutoFavoriteOnDownloadLabel =>
      'Automatycznie dodawaj do ulubionych przy pobieraniu';

  @override
  String get settingsAutoUpvoteOnDownloadLabel =>
      'Automatycznie głosuj w górę przy pobieraniu';

  @override
  String get settingsBackupSection => 'Kopia zapasowa';

  @override
  String get settingsBackupExportLabel => 'Eksportuj wyszukiwania';

  @override
  String get settingsBackupExportButton => 'Eksportuj';

  @override
  String get settingsBackupImportLabel => 'Importuj wyszukiwania';

  @override
  String get settingsBackupImportButton => 'Importuj';

  @override
  String settingsBackupImportProgress(int done, int total) {
    return 'Zaimportowano $done/$total';
  }

  @override
  String settingsBackupExportSuccess(int count) {
    return 'Wyeksportowano $count wyszukiwań';
  }

  @override
  String settingsBackupImportSummary(
    int imported,
    int duplicates,
    int invalid,
  ) {
    return 'Zaimportowano $imported, już zapisanych $duplicates, nieprawidłowych $invalid';
  }

  @override
  String get settingsBackupImportUnrecognizedFormat =>
      'Nierozpoznany format pliku';

  @override
  String get settingsBlacklistSection => 'Czarna lista';

  @override
  String get settingsBlacklistEmpty => 'Brak tagów na czarnej liście.';

  @override
  String get settingsBlacklistAddLabel => 'Dodaj tag';

  @override
  String get settingsBlacklistSyncE621Button => 'Synchronizuj z e621';

  @override
  String settingsBlacklistSyncE621Result(
    int added,
    int alreadyPresent,
    int skippedInvalid,
  ) {
    return 'Dodano $added, już obecnych $alreadyPresent, pominięto $skippedInvalid nieprawidłowych reguł';
  }

  @override
  String get settingsBlacklistSyncE621Failed =>
      'Nie udało się zsynchronizować z e621 — sprawdź, czy konto e621 jest skonfigurowane';

  @override
  String get postDetailDownloadTooltip => 'Pobierz';

  @override
  String get postDetailDownloadQueued => 'Zakolejkowano do pobrania';

  @override
  String get tagMenuSearchLabel => 'Szukaj';

  @override
  String get tagMenuAddToSearchesLabel => 'Dodaj do zapisanych wyszukiwań';

  @override
  String get tagMenuAddToBlacklistLabel => 'Dodaj do czarnej listy';

  @override
  String get tagMenuShowWikiLabel => 'Pokaż wiki';

  @override
  String get tagMenuCopyLabel => 'Kopiuj do schowka';

  @override
  String tagMenuAddedToBlacklist(String tag) {
    return 'Dodano „$tag” do czarnej listy';
  }

  @override
  String tagMenuCopied(String tag) {
    return 'Skopiowano „$tag” do schowka';
  }

  @override
  String get tagMenuAddToCurrentSearchLabel =>
      'Dodaj do bieżącego wyszukiwania';

  @override
  String get tagMenuExcludeFromCurrentSearchLabel =>
      'Wyklucz z bieżącego wyszukiwania';

  @override
  String get tagMenuRemoveFromCurrentSearchLabel =>
      'Usuń z bieżącego wyszukiwania';

  @override
  String get customSearchScreenTitle => 'Własne wyszukiwanie';

  @override
  String get customSearchSubmit => 'Szukaj';

  @override
  String get searchesCustomSearchTooltip => 'Własne wyszukiwanie';

  @override
  String get downloadQueueScreenTitle => 'Pobieranie';

  @override
  String get downloadQueueDownloadingLabel => 'Pobieranie';

  @override
  String get downloadQueueFailedLabel => 'Niepowodzenie';

  @override
  String get downloadQueueEmptyState => 'Na razie nic tu nie ma.';

  @override
  String get downloadQueueRetryTooltip => 'Ponów';

  @override
  String get downloadQueueRetryAllTooltip => 'Ponów wszystkie';

  @override
  String get downloadQueueClearFinishedTooltip => 'Wyczyść zakończone';

  @override
  String get downloadQueueResumeTooltip => 'Wznów pobieranie';

  @override
  String get downloadQueuePauseTooltip => 'Wstrzymaj pobieranie';

  @override
  String get downloadQueueChecksumMismatchReason =>
      'Pobrano, ale suma kontrolna się nie zgadza';

  @override
  String downloadQueueQueuedCount(int count) {
    return '$count w kolejce';
  }

  @override
  String downloadQueueDoneCount(int count) {
    return '$count ukończonych';
  }

  @override
  String updateAvailableTitle(String tagName) {
    return 'Dostępna aktualizacja ($tagName)';
  }

  @override
  String get updateDownloadingMessage => 'Pobieranie aktualizacji…';

  @override
  String get updateFailedMessage =>
      'Aktualizacja nie powiodła się. Spróbuj później lub zaktualizuj ręcznie ze strony wydań projektu na GitHubie.';

  @override
  String get updateLaterAction => 'Później';

  @override
  String get updateNowAction => 'Aktualizuj';

  @override
  String get wikiPageNotFoundMessage => 'Brak strony wiki dla tego tagu.';

  @override
  String get wikiPageLoadFailedMessage => 'Nie udało się wczytać strony wiki.';

  @override
  String wikiPageOtherNamesLabel(String names) {
    return 'Znane też jako: $names';
  }

  @override
  String get slideshowsScreenEmptyState =>
      'Brak pokazów slajdów. Naciśnij +, aby utworzyć.';

  @override
  String get slideshowsNewTooltip => 'Nowy pokaz slajdów';

  @override
  String get slideshowsNoLimitSubtitle => 'Bez limitu postów';

  @override
  String slideshowsMaxPostsSubtitle(int count) {
    return 'Do $count postów';
  }

  @override
  String get slideshowsDeleteDialogTitle => 'Usuń pokaz slajdów';

  @override
  String slideshowsDeleteDialogContent(String label) {
    return 'Usunąć „$label”? Już pobrane pliki zostaną zachowane, chyba że również zdecydujesz się je usunąć.';
  }

  @override
  String get slideshowsDeleteAlsoFilesLabel => 'Usuń też pobrane pliki';

  @override
  String get slideshowEditCreateTitle => 'Nowy pokaz slajdów';

  @override
  String get slideshowEditEditTitle => 'Edytuj pokaz slajdów';

  @override
  String get slideshowEditLabelField => 'Etykieta';

  @override
  String get slideshowEditDefaultCountField =>
      'Domyślna liczba postów na wyszukiwanie (puste = bez limitu)';

  @override
  String get slideshowEditMaxTotalField =>
      'Maksymalna łączna liczba postów (puste = bez limitu)';

  @override
  String get slideshowEditIntervalField => 'Sekundy na slajd';

  @override
  String get slideshowEditSaveButton => 'Zapisz';

  @override
  String get slideshowEditSearchesHeading => 'Wyszukiwania';

  @override
  String get slideshowEditAddSearchTooltip => 'Dodaj wyszukiwanie';

  @override
  String get slideshowEditAddSearchDialogTitle => 'Dodaj wyszukiwania';

  @override
  String get slideshowEditAddSearchDoneButton => 'Gotowe';

  @override
  String get slideshowEditNewSearchOption => 'Nowe wyszukiwanie';

  @override
  String get slideshowEditNewPoolOption => 'Nowy zbiór';

  @override
  String get slideshowEditNoMoreSearchesToAdd =>
      'Wszystkie wyszukiwania są już dodane';

  @override
  String get slideshowEditNoMorePoolsToAdd => 'Wszystkie zbiory są już dodane';

  @override
  String get slideshowEditSearchesEmptyState =>
      'Nie dodano jeszcze wyszukiwań. Najpierw zapisz pokaz slajdów, potem dodaj.';

  @override
  String get slideshowEditBlacklistHeading => 'Czarna lista';

  @override
  String get slideshowEditBlacklistEmpty =>
      'Brak tagów wykluczonych z tego pokazu slajdów.';

  @override
  String get slideshowEditBlacklistAddLabel => 'Wyklucz tag';

  @override
  String slideshowEditOverrideCountDialogTitle(String label) {
    return 'Posty dla „$label”';
  }

  @override
  String get slideshowEditOverrideCountField =>
      'Nadpisz liczbę (puste = użyj domyślnej z pokazu)';

  @override
  String slideshowEditOverrideCountSet(int count) {
    return '$count postów';
  }

  @override
  String get slideshowEditOverrideUsesDefault => 'Używa domyślnej z pokazu';

  @override
  String get slideshowEditRerollSearchTooltip =>
      'Wylosuj ponownie to wyszukiwanie';

  @override
  String get slideshowEditRerollAllButton => 'Wylosuj wszystkie ponownie';

  @override
  String get slideshowEditRemoveSearchTooltip => 'Usuń wyszukiwanie';

  @override
  String get slideshowEditRemoveSearchDialogTitle => 'Usuń wyszukiwanie';

  @override
  String slideshowEditRemoveSearchDialogContent(String label) {
    return 'Usunąć „$label” z tego pokazu slajdów? Już pobrane pliki zostaną zachowane, chyba że również zdecydujesz się je usunąć.';
  }

  @override
  String get slideshowEditPrepareHeading => 'Przygotuj';

  @override
  String get slideshowEditPrepareButton => 'Przygotuj';

  @override
  String slideshowEditPrepareSummary(
    int ready,
    int inProgress,
    int replaced,
    int unreplaceable,
  ) {
    return '$ready gotowych, $inProgress pobieranych, $replaced zastąpionych, $unreplaceable nie udało się zastąpić';
  }

  @override
  String slideshowEditUnreplaceableReason(String label, String reason) {
    return '$label: $reason';
  }

  @override
  String get slideshowEditRetryButton => 'Ponów';

  @override
  String get slideshowEditWatchButton => 'Oglądaj';

  @override
  String get slideshowEditPrepareErrorMessage =>
      'Nie udało się przygotować pokazu slajdów';

  @override
  String get slideshowEditNoDestinationFolderMessage =>
      'Nie skonfigurowano folderu docelowego pobierania. Ustaw go najpierw w Ustawieniach.';
}
