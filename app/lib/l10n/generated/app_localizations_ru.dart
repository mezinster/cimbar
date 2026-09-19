// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'CimBar Сканер';

  @override
  String get tabImport => 'Импорт GIF';

  @override
  String get tabCamera => 'Камера';

  @override
  String get tabSettings => 'О приложении';

  @override
  String get importTitle => 'Импорт CimBar GIF';

  @override
  String get cameraTitle => 'Сканер камеры';

  @override
  String get settingsTitle => 'О приложении';

  @override
  String get selectFile => 'Выбрать файл';

  @override
  String get dropFileHere => 'Нажмите для выбора или перетащите файл сюда';

  @override
  String get selectGifFile => 'Выберите CimBar GIF файл для декодирования';

  @override
  String get passphrase => 'Пароль';

  @override
  String get passphraseHint => 'Введите пароль для расшифровки';

  @override
  String get passphraseRequired => 'Требуется пароль';

  @override
  String get decode => 'Декодировать';

  @override
  String get decoding => 'Декодирование...';

  @override
  String get cancel => 'Отмена';

  @override
  String get progressParsingGif => 'Разбор GIF...';

  @override
  String get progressDecodingFrames => 'Декодирование кадров...';

  @override
  String progressDecodingFrame(int current, int total) {
    return 'Декодирование кадра $current/$total';
  }

  @override
  String get progressReedSolomon => 'Декодирование Рида-Соломона...';

  @override
  String get progressDecrypting => 'Расшифровка...';

  @override
  String get decodeSuccess => 'Успешно декодировано!';

  @override
  String decodedFile(String filename) {
    return 'Файл: $filename';
  }

  @override
  String decodedSize(String size) {
    return 'Размер: $size';
  }

  @override
  String get saveFile => 'Сохранить файл';

  @override
  String get shareFile => 'Поделиться файлом';

  @override
  String get fileSaved => 'Файл успешно сохранён';

  @override
  String get openFile => 'Открыть';

  @override
  String get saveToDevice => 'Сохранить на устройство';

  @override
  String get savedToDevice => 'Файл сохранён';

  @override
  String get noAppToOpen =>
      'На этом телефоне нет приложения, которое может открыть этот файл';

  @override
  String get openFailed => 'Не удалось открыть файл';

  @override
  String get passphrasePrompt =>
      'Файл зашифрован. Введите пароль, чтобы расшифровать его.';

  @override
  String get errorWrongPassphrase => 'Неверный пароль. Попробуйте ещё раз.';

  @override
  String get decrypt => 'Расшифровать';

  @override
  String get errorGeneric => 'Произошла ошибка';

  @override
  String get errorDecryption =>
      'Ошибка расшифровки — неверный пароль или повреждённые данные';

  @override
  String get errorInvalidGif => 'Недопустимый или неподдерживаемый GIF файл';

  @override
  String get errorNoFrames => 'GIF не содержит кадров';

  @override
  String get errorFileTooLarge => 'Файл слишком большой для обработки';

  @override
  String get cameraScanInstruction =>
      'Сфотографируйте штрих-код CimBar для декодирования';

  @override
  String get cameraTakePhoto => 'Сделать фото';

  @override
  String get cameraFromGallery => 'Галерея';

  @override
  String get cameraRetake => 'Переснять';

  @override
  String get progressLocatingBarcode => 'Поиск штрих-кода...';

  @override
  String get progressDetectingFrameSize => 'Определение размера кадра...';

  @override
  String get errorBarcodeNotFound => 'Штрих-код не найден на фото';

  @override
  String get errorNoFrameSizeMatch =>
      'Не удалось декодировать штрих-код ни при одном поддерживаемом размере кадра';

  @override
  String get language => 'Язык';

  @override
  String get systemDefault => 'Системный по умолчанию';

  @override
  String get about => 'О приложении';

  @override
  String get aboutDescription =>
      'CimBar Сканер декодирует цветные матричные штрих-коды. Совместим с веб-кодировщиком CimBar на nfcarchiver.com/cimbar.';

  @override
  String get aboutSuccessor =>
      'CimBar Сканер — преемник libcimbar и CFC от sz3, исходных проектов цветных матричных штрих-кодов (Color Icon Matrix Barcode). Он использует собственный, более новый формат штрих-кода, поэтому не читает штрих-коды libcimbar и CFC, а они не читают его штрих-коды.';

  @override
  String get webAppLabel => 'Веб-приложение';

  @override
  String get webAppUrl => 'https://nfcarchiver.com/cimbar/';

  @override
  String version(String version) {
    return 'Версия $version';
  }

  @override
  String get liveScanButton => 'Живое сканирование';

  @override
  String liveScanProgress(int captured, int total) {
    return 'Сканирование... $captured/$total кадров';
  }

  @override
  String get liveScanSearching => 'Поиск штрих-кода CimBar...';

  @override
  String get liveScanComplete => 'Все кадры захвачены!';

  @override
  String get liveScanError => 'Сканирование не удалось';

  @override
  String get cameraPermissionDenied =>
      'Для живого сканирования требуется разрешение камеры';

  @override
  String get noCameraAvailable => 'На этом устройстве нет доступной камеры';

  @override
  String liveScanFramesAnalyzed(int count) {
    return '$count кадров проанализировано';
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
  String get errorPassphraseRequired => 'Файл зашифрован: нужен пароль';

  @override
  String errorDecoderFailed(String detail) {
    return 'Decoder failed: $detail';
  }

  @override
  String get errorNoBarcodeFound => 'No CimBar barcode found in the photo';

  @override
  String get shareReadFailed =>
      'Не удалось прочитать отправленный файл. Откройте его через «Импорт GIF».';

  @override
  String get shareWhileDecoding =>
      'Сначала дождитесь окончания текущего декодирования, затем отправьте файл снова.';

  @override
  String get tabFiles => 'Файлы';

  @override
  String get filesTitle => 'Декодированные файлы';

  @override
  String get noFilesYet => 'Пока нет файлов';

  @override
  String get delete => 'Удалить';

  @override
  String get deleteFileTitle => 'Удалить файл';

  @override
  String deleteFileConfirm(String filename) {
    return 'Удалить $filename?';
  }

  @override
  String get fileDeleted => 'Файл удалён';

  @override
  String get developerSection => 'Разработчик';

  @override
  String get debugModeLabel => 'Режим отладки';

  @override
  String get debugModeDescription => 'Включить журнал отладки и захват кадров';

  @override
  String get privacyPolicy => 'Политика конфиденциальности';

  @override
  String get licenseInfo => 'Лицензия MIT';

  @override
  String get sourceCode => 'Исходный код';
}
