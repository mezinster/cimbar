// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get appTitle => 'CimBar Сканер';

  @override
  String get tabImport => 'Імпорт GIF';

  @override
  String get tabCamera => 'Камера';

  @override
  String get tabSettings => 'Про додаток';

  @override
  String get importTitle => 'Імпорт CimBar GIF';

  @override
  String get cameraTitle => 'Сканер камери';

  @override
  String get settingsTitle => 'Про додаток';

  @override
  String get selectFile => 'Вибрати файл';

  @override
  String get dropFileHere => 'Натисніть для вибору або перетягніть файл сюди';

  @override
  String get selectGifFile => 'Виберіть CimBar GIF файл для декодування';

  @override
  String get passphrase => 'Пароль';

  @override
  String get passphraseHint => 'Введіть пароль для розшифрування';

  @override
  String get passphraseRequired => 'Потрібен пароль';

  @override
  String get decode => 'Декодувати';

  @override
  String get decoding => 'Декодування...';

  @override
  String get cancel => 'Скасувати';

  @override
  String get progressParsingGif => 'Розбір GIF...';

  @override
  String get progressDecodingFrames => 'Декодування кадрів...';

  @override
  String progressDecodingFrame(int current, int total) {
    return 'Декодування кадру $current/$total';
  }

  @override
  String get progressReedSolomon => 'Декодування Ріда-Соломона...';

  @override
  String get progressDecrypting => 'Розшифрування...';

  @override
  String get decodeSuccess => 'Успішно декодовано!';

  @override
  String decodedFile(String filename) {
    return 'Файл: $filename';
  }

  @override
  String decodedSize(String size) {
    return 'Розмір: $size';
  }

  @override
  String get saveFile => 'Зберегти файл';

  @override
  String get shareFile => 'Поділитися файлом';

  @override
  String get fileSaved => 'Файл успішно збережено';

  @override
  String get errorGeneric => 'Сталася помилка';

  @override
  String get errorDecryption =>
      'Помилка розшифрування — неправильний пароль або пошкоджені дані';

  @override
  String get errorInvalidGif => 'Недійсний або непідтримуваний GIF файл';

  @override
  String get errorNoFrames => 'GIF не містить кадрів';

  @override
  String get errorFileTooLarge => 'Файл занадто великий для обробки';

  @override
  String get cameraScanInstruction =>
      'Сфотографуйте штрих-код CimBar для декодування';

  @override
  String get cameraTakePhoto => 'Зробити фото';

  @override
  String get cameraFromGallery => 'Галерея';

  @override
  String get cameraRetake => 'Перезняти';

  @override
  String get progressLocatingBarcode => 'Пошук штрих-коду...';

  @override
  String get progressDetectingFrameSize => 'Визначення розміру кадру...';

  @override
  String get errorBarcodeNotFound => 'Штрих-код не знайдено на фото';

  @override
  String get errorNoFrameSizeMatch =>
      'Не вдалося декодувати штрих-код при жодному підтримуваному розмірі кадру';

  @override
  String get language => 'Мова';

  @override
  String get systemDefault => 'Системна за замовчуванням';

  @override
  String get about => 'Про додаток';

  @override
  String get aboutDescription =>
      'CimBar Сканер декодує кольорові матричні штрих-коди. Сумісний з веб-кодувальником CimBar на nfcarchiver.com/cimbar.';

  @override
  String get webAppLabel => 'Веб-додаток';

  @override
  String get webAppUrl => 'https://nfcarchiver.com/cimbar/';

  @override
  String version(String version) {
    return 'Версія $version';
  }

  @override
  String get liveScanButton => 'Живе сканування';

  @override
  String liveScanProgress(int captured, int total) {
    return 'Сканування... $captured/$total кадрів';
  }

  @override
  String get liveScanSearching => 'Пошук штрих-коду CimBar...';

  @override
  String get liveScanComplete => 'Усі кадри захоплено!';

  @override
  String get liveScanError => 'Сканування не вдалося';

  @override
  String get cameraPermissionDenied =>
      'Для живого сканування потрібен дозвіл камери';

  @override
  String get noCameraAvailable => 'На цьому пристрої немає доступної камери';

  @override
  String liveScanFramesAnalyzed(int count) {
    return '$count кадрів проаналізовано';
  }

  @override
  String get liveScanAim => 'Fit the barcode inside the square';

  @override
  String get hintMoveCloser => 'Move closer';

  @override
  String get hintMoveBack => 'Move back';

  @override
  String get hintHoldStill => 'Hold still';

  @override
  String get hintAdjustAngle => 'Adjust angle or lighting';

  @override
  String errorMultiFrameNeedsLive(int total) {
    return 'This file spans $total frames — use Live Scan';
  }

  @override
  String get captureSaved => 'Frame captured to app documents';

  @override
  String get captureFailed => 'Capture failed';

  @override
  String get errorPassphraseRequired =>
      'This file is encrypted: a passphrase is required';

  @override
  String errorDecoderFailed(String detail) {
    return 'Decoder failed: $detail';
  }

  @override
  String get errorNoBarcodeFound => 'No CimBar barcode found in the photo';

  @override
  String get tabFiles => 'Файли';

  @override
  String get filesTitle => 'Декодовані файли';

  @override
  String get noFilesYet => 'Ще немає файлів';

  @override
  String get delete => 'Видалити';

  @override
  String get deleteFileTitle => 'Видалити файл';

  @override
  String deleteFileConfirm(String filename) {
    return 'Видалити $filename?';
  }

  @override
  String get fileDeleted => 'Файл видалено';

  @override
  String get developerSection => 'Розробник';

  @override
  String get debugModeLabel => 'Режим налагодження';

  @override
  String get debugModeDescription =>
      'Увімкнути журнал налагодження та захоплення кадрів';

  @override
  String get privacyPolicy => 'Політика конфіденційності';

  @override
  String get licenseInfo => 'Ліцензія MIT';

  @override
  String get sourceCode => 'Вихідний код';
}
