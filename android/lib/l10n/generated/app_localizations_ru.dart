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
  String get tabBinary => 'Импорт бинарного';

  @override
  String get tabCamera => 'Камера';

  @override
  String get tabSettings => 'О приложении';

  @override
  String get importTitle => 'Импорт CimBar GIF';

  @override
  String get importBinaryTitle => 'Импорт бинарного файла';

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
  String get selectBinaryFile => 'Выберите бинарный файл из C++ сканера';

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
  String get errorGeneric => 'Произошла ошибка';

  @override
  String get errorDecryption => 'Ошибка расшифровки — неверный пароль или повреждённые данные';

  @override
  String get errorInvalidGif => 'Недопустимый или неподдерживаемый GIF файл';

  @override
  String get errorNoFrames => 'GIF не содержит кадров';

  @override
  String get errorFileTooLarge => 'Файл слишком большой для обработки';

  @override
  String get cameraScanInstruction => 'Сфотографируйте штрих-код CimBar для декодирования';

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
  String get errorNoFrameSizeMatch => 'Не удалось декодировать штрих-код ни при одном поддерживаемом размере кадра';

  @override
  String get language => 'Язык';

  @override
  String get systemDefault => 'Системный по умолчанию';

  @override
  String get about => 'О приложении';

  @override
  String get aboutDescription => 'CimBar Сканер декодирует цветные матричные штрих-коды. Совместим с веб-кодировщиком CimBar на nfcarchiver.com/cimbar.';

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
    return 'Сканирование... $captured/$total кадров захвачено';
  }

  @override
  String get liveScanSearching => 'Поиск штрих-кода CimBar...';

  @override
  String get liveScanComplete => 'Все кадры захвачены!';

  @override
  String get liveScanError => 'Сканирование не удалось';

  @override
  String get cameraPermissionDenied => 'Для живого сканирования требуется разрешение камеры';

  @override
  String get noCameraAvailable => 'На этом устройстве нет доступной камеры';

  @override
  String liveScanFramesAnalyzed(int count) {
    return '$count кадров проанализировано';
  }

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
  String get privacyPolicy => 'Политика конфиденциальности';

  @override
  String get licenseInfo => 'Лицензия MIT';

  @override
  String get sourceCode => 'Исходный код';
}
