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
  String get tabSettings => 'Инфо';

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
      'CimBar Сканер вдохновлён libcimbar и CFC от sz3, исходными проектами цветных матричных штрих-кодов (Color Icon Matrix Barcode), но это отдельный проект, а не официальное приложение cimbar. Он использует собственный формат штрих-кода CimBar-XL, поэтому не читает штрих-коды libcimbar и CFC, а они не читают его штрих-коды.';

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
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'кадров',
      many: 'кадров',
      few: 'кадров',
      one: 'кадра',
    );
    return 'Сканирование... $captured/$total $_temp0';
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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count кадра проанализировано',
      many: '$count кадров проанализировано',
      few: '$count кадра проанализировано',
      one: '$count кадр проанализирован',
    );
    return '$_temp0';
  }

  @override
  String get liveScanAim => 'Поместите штрих-код в квадрат';

  @override
  String get hintMoveCloser => 'Поднесите ближе';

  @override
  String get hintMoveBack => 'Отодвиньте дальше';

  @override
  String get hintHoldStill => 'Держите неподвижно';

  @override
  String get hintAdjustAngle => 'Измените угол или освещение';

  @override
  String errorMultiFrameNeedsLive(int total) {
    return 'Кадров в файле: $total — используйте «Живое сканирование»';
  }

  @override
  String get captureSaved => 'Кадр сохранён в документы приложения';

  @override
  String get captureFailed => 'Не удалось сохранить кадр';

  @override
  String get errorPassphraseRequired => 'Файл зашифрован: нужен пароль';

  @override
  String errorDecoderFailed(String detail) {
    return 'Ошибка декодера: $detail';
  }

  @override
  String get errorNoBarcodeFound => 'На фото не найден штрих-код CimBar';

  @override
  String get shareReadFailed => 'Не удалось прочитать отправленный элемент.';

  @override
  String get shareWhileDecoding =>
      'Сначала дождитесь окончания текущего декодирования, затем отправьте файл снова.';

  @override
  String get shareChecking => 'Проверяем отправленное фото…';

  @override
  String shareOnlyFirst(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Отправляется только первый из $count элемента',
      many: 'Отправляется только первый из $count элементов',
      few: 'Отправляется только первый из $count элементов',
      one: 'Отправляется только первый из $count элемента',
    );
    return '$_temp0';
  }

  @override
  String shareTooLarge(String max) {
    return 'Файл слишком большой (лимит $max).';
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

  @override
  String get receivedText => 'Полученный текст';

  @override
  String get copyText => 'Копировать';

  @override
  String get textCopied => 'Скопировано в буфер обмена';

  @override
  String get shareText => 'Поделиться текстом';

  @override
  String textTruncated(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Показаны первые $countString символов — «Копировать», «Поделиться» и «Сохранить» используют весь текст.';
  }

  @override
  String get tabSend => 'Отправить';

  @override
  String get sendModeText => 'Текст';

  @override
  String get sendModeFile => 'Файл';

  @override
  String get sendTextHint => 'Введите или вставьте текст…';

  @override
  String sendEstimate(String size, int frames) {
    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: '$frames кадров',
      many: '$frames кадров',
      few: '$frames кадров',
      one: '$frames кадра',
    );
    return '$size · не более $_temp0';
  }

  @override
  String get sendFrameDelay => 'Задержка кадра';

  @override
  String get sendPresent => 'Показать на экране';

  @override
  String get sendShareGif => 'Поделиться GIF';

  @override
  String get sendEmpty => 'Сначала введите текст или выберите файл.';

  @override
  String sendTooLarge(int frames, int max) {
    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: '$frames кадра',
      many: '$frames кадров',
      few: '$frames кадра',
      one: '$frames кадр',
    );
    return 'Слишком много: $_temp0 (лимит $max).';
  }

  @override
  String sendFailed(String error) {
    return 'Ошибка кодирования: $error';
  }

  @override
  String presentSource(int i, int n) {
    return 'Кадр $i из $n';
  }

  @override
  String presentRepair(int r) {
    return 'Кадр восстановления $r';
  }

  @override
  String sendFileTooBig(String size, String max) {
    return 'Файл слишком большой: $size (лимит $max).';
  }

  @override
  String sizeBytes(String value) {
    return '$value Б';
  }

  @override
  String sizeKilobytes(String value) {
    return '$value КБ';
  }

  @override
  String sizeMegabytes(String value) {
    return '$value МБ';
  }

  @override
  String get sendChoosePhoto => 'Выбрать фото';

  @override
  String get photoOptimiseTitle => 'Оптимизация фото';

  @override
  String get photoFramesToSend => 'Кадров для отправки';

  @override
  String photoTransferTime(int frames, double seconds, int delay) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String secondsString = secondsNumberFormat.format(seconds);

    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: '$frames кадра',
      many: '$frames кадров',
      few: '$frames кадра',
      one: '$frames кадр',
    );
    return '$_temp0 · ≈ $secondsString с при $delay мс';
  }

  @override
  String photoGifCapNote(int max) {
    return '«Поделиться GIF» вмещает до $max кадров; больше — только «Показать на экране»';
  }

  @override
  String get photoManual => 'Вручную';

  @override
  String get photoBackToAuto => 'Вернуть авто';

  @override
  String photoQuality(int quality) {
    return 'Качество $quality';
  }

  @override
  String get photoSide => 'Длинная сторона';

  @override
  String get photoOriginal => 'Оригинал';

  @override
  String get photoSkip => 'Пропустить (оставить оригинал)';

  @override
  String get photoContinue => 'Продолжить';

  @override
  String photoContinueWith(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Продолжить с $count кадра',
      many: 'Продолжить с $count кадрами',
      few: 'Продолжить с $count кадрами',
      one: 'Продолжить с $count кадром',
    );
    return '$_temp0';
  }

  @override
  String photoContinueAsIs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Продолжить с этим изображением ($count кадра)',
      many: 'Продолжить с этим изображением ($count кадров)',
      few: 'Продолжить с этим изображением ($count кадра)',
      one: 'Продолжить с этим изображением ($count кадр)',
    );
    return '$_temp0';
  }

  @override
  String photoDoesNotFit(int frames, int needed) {
    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: 'Не помещается в $frames кадра',
      many: 'Не помещается в $frames кадров',
      few: 'Не помещается в $frames кадра',
      one: 'Не помещается в $frames кадр',
    );
    String _temp1 = intl.Intl.pluralLogic(
      needed,
      locale: localeName,
      other: 'нужно минимум $needed кадра',
      many: 'нужно минимум $needed кадров',
      few: 'нужно минимум $needed кадра',
      one: 'нужен минимум $needed кадр',
    );
    return '$_temp0 — $_temp1';
  }

  @override
  String get photoDecodeError =>
      'Не удаётся прочитать это фото. Нажмите «Пропустить», чтобы отправить исходный файл.';

  @override
  String get photoMemoryError =>
      'На этом устройстве недостаточно памяти, чтобы оптимизировать это фото.';

  @override
  String photoResultLabel(int width, int height, int quality, int kb) {
    return '$width×$height · q$quality · $kb КБ';
  }

  @override
  String get photoFewerFrames => 'Меньше кадров';

  @override
  String get photoMoreFrames => 'Больше кадров';

  @override
  String get photoEditFrameCount => 'Дважды коснитесь, чтобы ввести число';
}
