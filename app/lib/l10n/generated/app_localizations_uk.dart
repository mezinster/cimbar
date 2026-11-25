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
  String get tabSettings => 'Інфо';

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
  String get openFile => 'Відкрити';

  @override
  String get saveToDevice => 'Зберегти на пристрій';

  @override
  String get savedToDevice => 'Файл збережено';

  @override
  String get noAppToOpen =>
      'На цьому телефоні немає застосунку, який може відкрити цей файл';

  @override
  String get openFailed => 'Не вдалося відкрити файл';

  @override
  String get passphrasePrompt =>
      'Файл зашифровано. Введіть пароль, щоб розшифрувати його.';

  @override
  String get errorWrongPassphrase => 'Неправильний пароль. Спробуйте ще раз.';

  @override
  String get decrypt => 'Розшифрувати';

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
  String get aboutSuccessor =>
      'CimBar Сканер натхненний libcimbar і CFC від sz3, першопочатковими проєктами кольорових матричних штрих-кодів (Color Icon Matrix Barcode), але це окремий проєкт, а не офіційний застосунок cimbar. Він використовує власний формат штрих-коду CimBar-XL, тому не читає штрих-коди libcimbar і CFC, а вони не читають його штрих-коди.';

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
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'кадрів',
      many: 'кадрів',
      few: 'кадрів',
      one: 'кадру',
    );
    return 'Сканування... $captured/$total $_temp0';
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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count кадру проаналізовано',
      many: '$count кадрів проаналізовано',
      few: '$count кадри проаналізовано',
      one: '$count кадр проаналізовано',
    );
    return '$_temp0';
  }

  @override
  String get liveScanAim => 'Помістіть штрих-код у квадрат';

  @override
  String get hintMoveCloser => 'Піднесіть ближче';

  @override
  String get hintMoveBack => 'Відсуньте далі';

  @override
  String get hintHoldStill => 'Тримайте нерухомо';

  @override
  String get hintAdjustAngle => 'Змініть кут або освітлення';

  @override
  String errorMultiFrameNeedsLive(int total) {
    return 'Кадрів у файлі: $total — скористайтеся «Живим скануванням»';
  }

  @override
  String get captureSaved => 'Кадр збережено в документи застосунку';

  @override
  String get captureFailed => 'Не вдалося зберегти кадр';

  @override
  String get errorPassphraseRequired => 'Файл зашифровано: потрібен пароль';

  @override
  String errorDecoderFailed(String detail) {
    return 'Помилка декодера: $detail';
  }

  @override
  String get errorNoBarcodeFound => 'На фото не знайдено штрих-код CimBar';

  @override
  String get shareReadFailed => 'Не вдалося прочитати надісланий елемент.';

  @override
  String get shareWhileDecoding =>
      'Спершу дочекайтеся завершення поточного декодування, потім надішліть файл знову.';

  @override
  String get shareChecking => 'Перевіряємо надіслане фото…';

  @override
  String shareOnlyFirst(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Надсилається лише перший із $count елемента',
      many: 'Надсилається лише перший із $count елементів',
      few: 'Надсилається лише перший із $count елементів',
      one: 'Надсилається лише перший із $count елемента',
    );
    return '$_temp0';
  }

  @override
  String shareTooLarge(String max) {
    return 'Файл завеликий (ліміт $max).';
  }

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

  @override
  String get receivedText => 'Отриманий текст';

  @override
  String get copyText => 'Копіювати';

  @override
  String get textCopied => 'Скопійовано в буфер обміну';

  @override
  String get shareText => 'Поділитися текстом';

  @override
  String textTruncated(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Показано перші $countString символів — «Копіювати», «Поділитися» та «Зберегти» використовують увесь текст.';
  }

  @override
  String get tabSend => 'Надіслати';

  @override
  String get sendModeText => 'Текст';

  @override
  String get sendModeFile => 'Файл';

  @override
  String get sendTextHint => 'Введіть або вставте текст…';

  @override
  String sendEstimate(String size, int frames) {
    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: '$frames кадрів',
      many: '$frames кадрів',
      few: '$frames кадрів',
      one: '$frames кадру',
    );
    return '$size · не більше $_temp0';
  }

  @override
  String get sendFrameDelay => 'Затримка кадру';

  @override
  String get sendPresent => 'Показати на екрані';

  @override
  String get sendShareGif => 'Поділитися GIF';

  @override
  String get sendEmpty => 'Спочатку введіть текст або виберіть файл.';

  @override
  String sendTooLarge(int frames, int max) {
    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: '$frames кадру',
      many: '$frames кадрів',
      few: '$frames кадри',
      one: '$frames кадр',
    );
    return 'Забагато: $_temp0 (ліміт $max).';
  }

  @override
  String sendFailed(String error) {
    return 'Помилка кодування: $error';
  }

  @override
  String presentSource(int i, int n) {
    return 'Кадр $i з $n';
  }

  @override
  String presentRepair(int r) {
    return 'Кадр відновлення $r';
  }

  @override
  String sendFileTooBig(String size, String max) {
    return 'Файл завеликий: $size (ліміт $max).';
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
  String get sendChoosePhoto => 'Вибрати фото';

  @override
  String get photoOptimiseTitle => 'Оптимізація фото';

  @override
  String get photoFramesToSend => 'Кадрів для надсилання';

  @override
  String photoTransferTime(int frames, double seconds, int delay) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String secondsString = secondsNumberFormat.format(seconds);

    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: '$frames кадру',
      many: '$frames кадрів',
      few: '$frames кадри',
      one: '$frames кадр',
    );
    return '$_temp0 · ≈ $secondsString с при $delay мс';
  }

  @override
  String photoGifCapNote(int max) {
    return '«Поділитися GIF» вміщує до $max кадрів; більше — лише «Показати на екрані»';
  }

  @override
  String get photoManual => 'Вручну';

  @override
  String get photoBackToAuto => 'Повернути авто';

  @override
  String photoQuality(int quality) {
    return 'Якість $quality';
  }

  @override
  String get photoSide => 'Довга сторона';

  @override
  String get photoOriginal => 'Оригінал';

  @override
  String get photoSkip => 'Пропустити (залишити оригінал)';

  @override
  String get photoContinue => 'Продовжити';

  @override
  String photoContinueWith(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Продовжити з $count кадру',
      many: 'Продовжити з $count кадрами',
      few: 'Продовжити з $count кадрами',
      one: 'Продовжити з $count кадром',
    );
    return '$_temp0';
  }

  @override
  String photoContinueAsIs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Продовжити з цим зображенням ($count кадру)',
      many: 'Продовжити з цим зображенням ($count кадрів)',
      few: 'Продовжити з цим зображенням ($count кадри)',
      one: 'Продовжити з цим зображенням ($count кадр)',
    );
    return '$_temp0';
  }

  @override
  String photoDoesNotFit(int frames, int needed) {
    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: 'Не вміщується у $frames кадру',
      many: 'Не вміщується у $frames кадрів',
      few: 'Не вміщується у $frames кадри',
      one: 'Не вміщується у $frames кадр',
    );
    String _temp1 = intl.Intl.pluralLogic(
      needed,
      locale: localeName,
      other: 'потрібно щонайменше $needed кадру',
      many: 'потрібно щонайменше $needed кадрів',
      few: 'потрібно щонайменше $needed кадри',
      one: 'потрібен щонайменше $needed кадр',
    );
    return '$_temp0 — $_temp1';
  }

  @override
  String get photoDecodeError =>
      'Не вдається прочитати це фото. Натисніть «Пропустити», щоб надіслати вихідний файл.';

  @override
  String get photoMemoryError =>
      'На цьому пристрої недостатньо пам\'яті, щоб оптимізувати це фото.';

  @override
  String photoResultLabel(int width, int height, int quality, int kb) {
    return '$width×$height · q$quality · $kb КБ';
  }

  @override
  String get photoFewerFrames => 'Менше кадрів';

  @override
  String get photoMoreFrames => 'Більше кадрів';

  @override
  String get photoEditFrameCount => 'Двічі торкніться, щоб ввести число';

  @override
  String get shareWhileEncoding =>
      'Спершу дочекайтеся завершення створення поточного штрих-коду, потім поділіться знову.';

  @override
  String get sharePresentConfirm =>
      'Зупинити показ і завантажити отриманий елемент?';

  @override
  String get shareReplaceTextConfirm => 'Замінити введений текст?';

  @override
  String get shareSendInstead => 'Надіслати це фото';

  @override
  String get commonYes => 'Так';

  @override
  String get commonNo => 'Ні';
}
