// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get appTitle => 'Skaner CimBar';

  @override
  String get tabImport => 'Otwórz GIF';

  @override
  String get tabCamera => 'Aparat';

  @override
  String get tabSettings => 'Informacje';

  @override
  String get importTitle => 'Importuj GIF CimBar';

  @override
  String get cameraTitle => 'Skanowanie aparatem';

  @override
  String get settingsTitle => 'O aplikacji';

  @override
  String get selectFile => 'Wybierz plik';

  @override
  String get dropFileHere => 'Dotknij, aby wybrać, lub upuść plik tutaj';

  @override
  String get selectGifFile => 'Wybierz plik GIF CimBar do zdekodowania';

  @override
  String get passphrase => 'Hasło';

  @override
  String get passphraseHint => 'Wpisz hasło do odszyfrowania';

  @override
  String get passphraseRequired => 'Hasło jest wymagane';

  @override
  String get decode => 'Dekoduj';

  @override
  String get decoding => 'Dekodowanie...';

  @override
  String get cancel => 'Anuluj';

  @override
  String get progressParsingGif => 'Analizowanie GIF-a...';

  @override
  String get progressDecodingFrames => 'Dekodowanie klatek...';

  @override
  String progressDecodingFrame(int current, int total) {
    return 'Dekodowanie klatki $current/$total';
  }

  @override
  String get progressReedSolomon => 'Dekodowanie Reeda-Solomona...';

  @override
  String get progressDecrypting => 'Odszyfrowywanie...';

  @override
  String get decodeSuccess => 'Zdekodowano pomyślnie!';

  @override
  String decodedFile(String filename) {
    return 'Plik: $filename';
  }

  @override
  String decodedSize(String size) {
    return 'Rozmiar: $size';
  }

  @override
  String get saveFile => 'Zapisz plik';

  @override
  String get shareFile => 'Udostępnij plik';

  @override
  String get fileSaved => 'Plik został zapisany';

  @override
  String get openFile => 'Otwórz';

  @override
  String get saveToDevice => 'Zapisz na urządzeniu';

  @override
  String get savedToDevice => 'Zapisano plik';

  @override
  String get noAppToOpen =>
      'Na tym telefonie nie ma aplikacji, która może otworzyć ten plik';

  @override
  String get openFailed => 'Nie udało się otworzyć pliku';

  @override
  String get passphrasePrompt =>
      'Ten plik jest zaszyfrowany. Wpisz hasło, aby go odszyfrować.';

  @override
  String get errorWrongPassphrase => 'Nieprawidłowe hasło. Spróbuj ponownie.';

  @override
  String get decrypt => 'Odszyfruj';

  @override
  String get errorGeneric => 'Wystąpił błąd';

  @override
  String get errorDecryption =>
      'Odszyfrowanie nie powiodło się — nieprawidłowe hasło lub uszkodzone dane';

  @override
  String get errorInvalidGif => 'Nieprawidłowy lub nieobsługiwany plik GIF';

  @override
  String get errorNoFrames => 'GIF nie zawiera żadnych klatek';

  @override
  String get errorFileTooLarge => 'Plik jest za duży, aby go przetworzyć';

  @override
  String get cameraScanInstruction =>
      'Zrób zdjęcie kodu kreskowego CimBar, aby go zdekodować';

  @override
  String get cameraTakePhoto => 'Zrób zdjęcie';

  @override
  String get cameraFromGallery => 'Galeria';

  @override
  String get cameraRetake => 'Powtórz zdjęcie';

  @override
  String get progressLocatingBarcode => 'Wyszukiwanie kodu kreskowego...';

  @override
  String get progressDetectingFrameSize => 'Wykrywanie rozmiaru klatki...';

  @override
  String get errorBarcodeNotFound =>
      'Na zdjęciu nie znaleziono kodu kreskowego';

  @override
  String get errorNoFrameSizeMatch =>
      'Nie udało się zdekodować kodu kreskowego przy żadnym obsługiwanym rozmiarze klatki';

  @override
  String get language => 'Język';

  @override
  String get systemDefault => 'Domyślny systemowy';

  @override
  String get about => 'O aplikacji';

  @override
  String get aboutDescription =>
      'Skaner CimBar dekoduje kolorowe kody matrycowe z ikon (Color Icon Matrix Barcode). Jest zgodny z koderem internetowym CimBar na nfcarchiver.com/cimbar.';

  @override
  String get aboutSuccessor =>
      'Skaner CimBar jest inspirowany projektami libcimbar i CFC autorstwa sz3 — oryginalnymi projektami Color Icon Matrix Barcode — ale jest osobnym projektem, a nie oficjalną aplikacją cimbar. Używa własnego formatu kodu, CimBar-XL, dlatego nie odczytuje kodów utworzonych przez libcimbar ani CFC, a one nie odczytują jego kodów.';

  @override
  String get webAppLabel => 'Aplikacja internetowa';

  @override
  String get webAppUrl => 'https://nfcarchiver.com/cimbar/';

  @override
  String version(String version) {
    return 'Wersja $version';
  }

  @override
  String get liveScanButton => 'Skanowanie na żywo';

  @override
  String liveScanProgress(int captured, int total) {
    return 'Skanowanie... klatki: $captured/$total';
  }

  @override
  String get liveScanSearching => 'Szukanie kodu kreskowego CimBar...';

  @override
  String get liveScanComplete => 'Przechwycono wszystkie klatki!';

  @override
  String get liveScanError => 'Skanowanie nie powiodło się';

  @override
  String get cameraPermissionDenied =>
      'Skanowanie na żywo wymaga dostępu do aparatu';

  @override
  String get noCameraAvailable => 'To urządzenie nie ma dostępnego aparatu';

  @override
  String liveScanFramesAnalyzed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Przeanalizowano $count klatki',
      many: 'Przeanalizowano $count klatek',
      few: 'Przeanalizowano $count klatki',
      one: 'Przeanalizowano $count klatkę',
    );
    return '$_temp0';
  }

  @override
  String get liveScanAim => 'Umieść kod kreskowy w kwadracie';

  @override
  String get hintMoveCloser => 'Podejdź bliżej';

  @override
  String get hintMoveBack => 'Odsuń się';

  @override
  String get hintHoldStill => 'Nie ruszaj telefonem';

  @override
  String get hintAdjustAngle => 'Zmień kąt lub oświetlenie';

  @override
  String errorMultiFrameNeedsLive(int total) {
    return 'Ten plik składa się z wielu klatek ($total) — użyj funkcji „Skanowanie na żywo”';
  }

  @override
  String get captureSaved => 'Klatka zapisana w dokumentach aplikacji';

  @override
  String get captureFailed => 'Nie udało się przechwycić klatki';

  @override
  String get errorPassphraseRequired =>
      'Ten plik jest zaszyfrowany: wymagane jest hasło';

  @override
  String errorDecoderFailed(String detail) {
    return 'Błąd dekodera: $detail';
  }

  @override
  String get errorNoBarcodeFound =>
      'Na zdjęciu nie znaleziono kodu kreskowego CimBar';

  @override
  String get shareReadFailed =>
      'Nie udało się odczytać udostępnionego elementu.';

  @override
  String get shareWhileDecoding =>
      'Najpierw zakończ bieżące dekodowanie, a potem udostępnij plik ponownie.';

  @override
  String get shareChecking => 'Sprawdzanie udostępnionego zdjęcia…';

  @override
  String shareOnlyFirst(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wysyłany jest tylko pierwszy z $count elementu',
      many: 'Wysyłany jest tylko pierwszy z $count elementów',
      few: 'Wysyłany jest tylko pierwszy z $count elementów',
      one: 'Wysyłany jest tylko 1 element',
    );
    return '$_temp0';
  }

  @override
  String shareTooLarge(String max) {
    return 'Plik jest za duży (limit $max).';
  }

  @override
  String get tabFiles => 'Pliki';

  @override
  String get filesTitle => 'Zdekodowane pliki';

  @override
  String get noFilesYet => 'Brak zdekodowanych plików';

  @override
  String get delete => 'Usuń';

  @override
  String get deleteFileTitle => 'Usuń plik';

  @override
  String deleteFileConfirm(String filename) {
    return 'Usunąć $filename?';
  }

  @override
  String get fileDeleted => 'Plik usunięty';

  @override
  String get developerSection => 'Dla programistów';

  @override
  String get debugModeLabel => 'Tryb debugowania';

  @override
  String get debugModeDescription =>
      'Włącz logi debugowania i przechwytywanie klatek';

  @override
  String get privacyPolicy => 'Polityka prywatności';

  @override
  String get licenseInfo => 'Licencja MIT';

  @override
  String get sourceCode => 'Kod źródłowy';

  @override
  String get receivedText => 'Odebrany tekst';

  @override
  String get copyText => 'Kopiuj';

  @override
  String get textCopied => 'Skopiowano do schowka';

  @override
  String get shareText => 'Udostępnij tekst';

  @override
  String textTruncated(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Pokazano początek tekstu (znaki: $countString) — „Kopiuj”, „Udostępnij” i „Zapisz” używają całego tekstu.';
  }

  @override
  String get tabSend => 'Wyślij';

  @override
  String get sendModeText => 'Tekst';

  @override
  String get sendModeFile => 'Plik';

  @override
  String get sendTextHint => 'Wpisz lub wklej tekst…';

  @override
  String sendEstimate(String size, int frames) {
    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: '$frames klatki',
      many: '$frames klatek',
      few: '$frames klatki',
      one: '$frames klatka',
    );
    return '$size · maks. $_temp0';
  }

  @override
  String get sendFrameDelay => 'Opóźnienie klatki';

  @override
  String get sendPresent => 'Pokaż na ekranie';

  @override
  String get sendShareGif => 'Udostępnij GIF';

  @override
  String get sendEmpty => 'Najpierw wpisz tekst lub wybierz plik.';

  @override
  String sendTooLarge(int frames, int max) {
    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: '$frames klatki',
      many: '$frames klatek',
      few: '$frames klatki',
      one: '$frames klatka',
    );
    return 'Za duży: $_temp0 (limit $max).';
  }

  @override
  String sendFailed(String error) {
    return 'Kodowanie nie powiodło się: $error';
  }

  @override
  String presentSource(int i, int n) {
    return 'Klatka $i z $n';
  }

  @override
  String presentRepair(int r) {
    return 'Klatka naprawcza $r';
  }

  @override
  String sendFileTooBig(String size, String max) {
    return 'Plik jest za duży: $size (limit $max).';
  }

  @override
  String sizeBytes(String value) {
    return '$value B';
  }

  @override
  String sizeKilobytes(String value) {
    return '$value KB';
  }

  @override
  String sizeMegabytes(String value) {
    return '$value MB';
  }

  @override
  String get sendChoosePhoto => 'Wybierz zdjęcie';

  @override
  String get photoOptimiseTitle => 'Optymalizacja zdjęcia';

  @override
  String get photoFramesToSend => 'Klatki do wysłania';

  @override
  String photoTransferTime(int frames, double seconds, int delay) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String secondsString = secondsNumberFormat.format(seconds);

    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: '$frames klatki',
      many: '$frames klatek',
      few: '$frames klatki',
      one: '$frames klatka',
    );
    return '$_temp0 · ≈ $secondsString s przy $delay ms';
  }

  @override
  String photoGifCapNote(int max) {
    return '„Udostępnij GIF” mieści do $max klatek; więcej — tylko „Pokaż na ekranie”';
  }

  @override
  String get photoManual => 'Ręcznie';

  @override
  String get photoBackToAuto => 'Automatycznie';

  @override
  String photoQuality(int quality) {
    return 'Jakość $quality';
  }

  @override
  String get photoSide => 'Dłuższy bok';

  @override
  String get photoOriginal => 'Oryginał';

  @override
  String get photoSkip => 'Pomiń (zachowaj oryginał)';

  @override
  String get photoContinue => 'Kontynuuj';

  @override
  String photoContinueWith(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Kontynuuj z $count klatki',
      many: 'Kontynuuj z $count klatkami',
      few: 'Kontynuuj z $count klatkami',
      one: 'Kontynuuj z $count klatką',
    );
    return '$_temp0';
  }

  @override
  String photoContinueAsIs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Kontynuuj z tym obrazem ($count klatki)',
      many: 'Kontynuuj z tym obrazem ($count klatek)',
      few: 'Kontynuuj z tym obrazem ($count klatki)',
      one: 'Kontynuuj z tym obrazem ($count klatka)',
    );
    return '$_temp0';
  }

  @override
  String photoDoesNotFit(int frames, int needed) {
    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: 'Nie mieści się w $frames klatki',
      many: 'Nie mieści się w $frames klatkach',
      few: 'Nie mieści się w $frames klatkach',
      one: 'Nie mieści się w $frames klatce',
    );
    String _temp1 = intl.Intl.pluralLogic(
      needed,
      locale: localeName,
      other: 'potrzeba co najmniej $needed klatki',
      many: 'potrzeba co najmniej $needed klatek',
      few: 'potrzebne są co najmniej $needed klatki',
      one: 'potrzebna jest co najmniej $needed klatka',
    );
    return '$_temp0 — $_temp1';
  }

  @override
  String get photoDecodeError =>
      'Nie można odczytać tego zdjęcia. Dotknij „Pomiń”, aby wysłać oryginalny plik.';

  @override
  String get photoMemoryError =>
      'Za mało pamięci na tym urządzeniu, aby zoptymalizować to zdjęcie.';

  @override
  String photoResultLabel(int width, int height, int quality, int kb) {
    return '$width×$height · q$quality · $kb KB';
  }

  @override
  String get photoFewerFrames => 'Mniej klatek';

  @override
  String get photoMoreFrames => 'Więcej klatek';

  @override
  String get photoEditFrameCount => 'Dotknij dwukrotnie, aby wpisać liczbę';

  @override
  String get shareWhileEncoding =>
      'Najpierw zaczekaj, aż bieżący kod kreskowy zostanie utworzony, a potem udostępnij ponownie.';

  @override
  String get sharePresentConfirm =>
      'Zakończyć wyświetlanie i wczytać udostępniony element?';

  @override
  String get shareReplaceTextConfirm => 'Zastąpić wpisany tekst?';

  @override
  String get shareSendInstead => 'Wyślij zamiast tego to zdjęcie';

  @override
  String get commonYes => 'Tak';

  @override
  String get commonNo => 'Nie';

  @override
  String get wideSendEmpty => 'Kod kreskowy pojawi się tutaj podczas pisania';

  @override
  String get wideResultEmpty => 'Tutaj pojawi się zdekodowany plik';

  @override
  String get previewFullScreen => 'Pełny ekran';
}
