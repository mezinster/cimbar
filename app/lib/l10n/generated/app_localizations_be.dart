// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Belarusian (`be`).
class AppLocalizationsBe extends AppLocalizations {
  AppLocalizationsBe([String locale = 'be']) : super(locale);

  @override
  String get appTitle => 'CimBar Сканер';

  @override
  String get tabImport => 'Імпарт GIF';

  @override
  String get tabCamera => 'Камера';

  @override
  String get tabSettings => 'Звесткі';

  @override
  String get importTitle => 'Імпарт CimBar GIF';

  @override
  String get cameraTitle => 'Сканер камеры';

  @override
  String get settingsTitle => 'Пра праграму';

  @override
  String get selectFile => 'Выбраць файл';

  @override
  String get dropFileHere =>
      'Націсніце, каб выбраць, або перацягніце файл сюды';

  @override
  String get selectGifFile => 'Выберыце файл CimBar GIF для дэкадавання';

  @override
  String get passphrase => 'Пароль';

  @override
  String get passphraseHint => 'Увядзіце пароль для расшыфроўкі';

  @override
  String get passphraseRequired => 'Патрэбны пароль';

  @override
  String get decode => 'Дэкадаваць';

  @override
  String get decoding => 'Дэкадаванне...';

  @override
  String get cancel => 'Скасаваць';

  @override
  String get progressParsingGif => 'Разбор GIF...';

  @override
  String get progressDecodingFrames => 'Дэкадаванне кадраў...';

  @override
  String progressDecodingFrame(int current, int total) {
    return 'Дэкадаванне кадра $current/$total';
  }

  @override
  String get progressReedSolomon => 'Дэкадаванне Рыда-Саламона...';

  @override
  String get progressDecrypting => 'Расшыфроўка...';

  @override
  String get decodeSuccess => 'Паспяхова дэкадавана!';

  @override
  String decodedFile(String filename) {
    return 'Файл: $filename';
  }

  @override
  String decodedSize(String size) {
    return 'Памер: $size';
  }

  @override
  String get saveFile => 'Захаваць файл';

  @override
  String get shareFile => 'Падзяліцца файлам';

  @override
  String get fileSaved => 'Файл паспяхова захаваны';

  @override
  String get openFile => 'Адкрыць';

  @override
  String get saveToDevice => 'Захаваць на прыладу';

  @override
  String get savedToDevice => 'Файл захаваны';

  @override
  String get noAppToOpen =>
      'На гэтым тэлефоне няма праграмы, якая можа адкрыць гэты файл';

  @override
  String get openFailed => 'Не ўдалося адкрыць файл';

  @override
  String get passphrasePrompt =>
      'Гэты файл зашыфраваны. Увядзіце пароль, каб расшыфраваць яго.';

  @override
  String get errorWrongPassphrase =>
      'Няправільны пароль. Паспрабуйце яшчэ раз.';

  @override
  String get decrypt => 'Расшыфраваць';

  @override
  String get errorGeneric => 'Адбылася памылка';

  @override
  String get errorDecryption =>
      'Памылка расшыфроўкі — няправільны пароль або пашкоджаныя даныя';

  @override
  String get errorInvalidGif => 'Недапушчальны або непадтрымліваемы файл GIF';

  @override
  String get errorNoFrames => 'GIF не змяшчае кадраў';

  @override
  String get errorFileTooLarge => 'Файл занадта вялікі для апрацоўкі';

  @override
  String get cameraScanInstruction =>
      'Сфатаграфуйце штрых-код CimBar, каб дэкадаваць яго';

  @override
  String get cameraTakePhoto => 'Зрабіць фота';

  @override
  String get cameraFromGallery => 'Галерэя';

  @override
  String get cameraRetake => 'Пераздымаць';

  @override
  String get progressLocatingBarcode => 'Пошук штрых-кода...';

  @override
  String get progressDetectingFrameSize => 'Вызначэнне памеру кадра...';

  @override
  String get errorBarcodeNotFound => 'На фота не знойдзены штрых-код';

  @override
  String get errorNoFrameSizeMatch =>
      'Не ўдалося дэкадаваць штрых-код ні пры адным падтрымліваемым памеры кадра';

  @override
  String get language => 'Мова';

  @override
  String get systemDefault => 'Як у сістэме';

  @override
  String get about => 'Пра праграму';

  @override
  String get aboutDescription =>
      'CimBar Сканер дэкадуе каляровыя матрычныя штрых-коды. Сумяшчальны з вэб-кадавальнікам CimBar на nfcarchiver.com/cimbar.';

  @override
  String get aboutSuccessor =>
      'CimBar Сканер натхнёны праектамі libcimbar і CFC ад sz3, першапачатковымі праектамі каляровых матрычных штрых-кодаў (Color Icon Matrix Barcode), але гэта асобны праект, а не афіцыйная праграма cimbar. Ён выкарыстоўвае ўласны фармат штрых-кода CimBar-XL, таму не чытае штрых-коды libcimbar і CFC, а яны не чытаюць яго штрых-коды.';

  @override
  String get webAppLabel => 'Вэб-праграма';

  @override
  String get webAppUrl => 'https://nfcarchiver.com/cimbar/';

  @override
  String version(String version) {
    return 'Версія $version';
  }

  @override
  String get liveScanButton => 'Жывое сканаванне';

  @override
  String liveScanProgress(int captured, int total) {
    return 'Сканаванне... $captured/$total кадраў';
  }

  @override
  String get liveScanSearching => 'Пошук штрых-кода CimBar...';

  @override
  String get liveScanComplete => 'Усе кадры захоплены!';

  @override
  String get liveScanError => 'Сканаванне не ўдалося';

  @override
  String get cameraPermissionDenied =>
      'Для жывога сканавання патрэбны дазвол на камеру';

  @override
  String get noCameraAvailable => 'На гэтай прыладзе няма даступнай камеры';

  @override
  String liveScanFramesAnalyzed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count кадра прааналізавана',
      many: '$count кадраў прааналізавана',
      few: '$count кадры прааналізаваны',
      one: '$count кадр прааналізаваны',
    );
    return '$_temp0';
  }

  @override
  String get liveScanAim => 'Змясціце штрых-код у квадрат';

  @override
  String get hintMoveCloser => 'Падыдзіце бліжэй';

  @override
  String get hintMoveBack => 'Адсуньцеся далей';

  @override
  String get hintHoldStill => 'Трымайце нерухома';

  @override
  String get hintAdjustAngle => 'Змяніце вугал або асвятленне';

  @override
  String errorMultiFrameNeedsLive(int total) {
    return 'Кадраў у файле: $total — выкарыстоўвайце «Жывое сканаванне»';
  }

  @override
  String get captureSaved => 'Кадр захаваны ў дакументы праграмы';

  @override
  String get captureFailed => 'Не ўдалося захаваць кадр';

  @override
  String get errorPassphraseRequired =>
      'Гэты файл зашыфраваны: патрэбны пароль';

  @override
  String errorDecoderFailed(String detail) {
    return 'Памылка дэкодэра: $detail';
  }

  @override
  String get errorNoBarcodeFound => 'На фота не знойдзены штрых-код CimBar';

  @override
  String get shareReadFailed =>
      'Не ўдалося прачытаць дасланы файл. Адкрыйце яго праз «Імпарт GIF».';

  @override
  String get shareWhileDecoding =>
      'Спачатку дачакайцеся заканчэння бягучага дэкадавання, потым дашліце файл зноў.';

  @override
  String get tabFiles => 'Файлы';

  @override
  String get filesTitle => 'Дэкадаваныя файлы';

  @override
  String get noFilesYet => 'Пакуль няма файлаў';

  @override
  String get delete => 'Выдаліць';

  @override
  String get deleteFileTitle => 'Выдаліць файл';

  @override
  String deleteFileConfirm(String filename) {
    return 'Выдаліць $filename?';
  }

  @override
  String get fileDeleted => 'Файл выдалены';

  @override
  String get developerSection => 'Распрацоўшчык';

  @override
  String get debugModeLabel => 'Рэжым адладкі';

  @override
  String get debugModeDescription => 'Уключыць журнал адладкі і захоп кадраў';

  @override
  String get privacyPolicy => 'Палітыка прыватнасці';

  @override
  String get licenseInfo => 'Ліцэнзія MIT';

  @override
  String get sourceCode => 'Зыходны код';

  @override
  String get receivedText => 'Атрыманы тэкст';

  @override
  String get copyText => 'Капіяваць';

  @override
  String get textCopied => 'Скапіявана ў буфер абмену';

  @override
  String get shareText => 'Падзяліцца тэкстам';

  @override
  String textTruncated(int count) {
    return 'Паказаны першыя $count сімвалаў — «Капіяваць», «Падзяліцца» і «Захаваць» выкарыстоўваюць увесь тэкст.';
  }

  @override
  String get tabSend => 'Адправіць';

  @override
  String get sendModeText => 'Тэкст';

  @override
  String get sendModeFile => 'Файл';

  @override
  String get sendTextHint => 'Увядзіце або ўстаўце тэкст…';

  @override
  String sendEstimate(String size, int frames) {
    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: '$frames кадра',
      many: '$frames кадраў',
      few: '$frames кадры',
      one: '$frames кадр',
    );
    return '$size · не больш за $_temp0';
  }

  @override
  String get sendFrameDelay => 'Затрымка кадра';

  @override
  String get sendPresent => 'Паказаць на экране';

  @override
  String get sendShareGif => 'Падзяліцца GIF';

  @override
  String get sendEmpty => 'Спачатку ўвядзіце тэкст або выберыце файл.';

  @override
  String sendTooLarge(int frames, int max) {
    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: '$frames кадра',
      many: '$frames кадраў',
      few: '$frames кадры',
      one: '$frames кадр',
    );
    return 'Занадта шмат: $_temp0 (ліміт $max).';
  }

  @override
  String sendFailed(String error) {
    return 'Памылка кадавання: $error';
  }

  @override
  String presentSource(int i, int n) {
    return 'Кадр $i з $n';
  }

  @override
  String presentRepair(int r) {
    return 'Кадр аднаўлення $r';
  }

  @override
  String sendFileTooBig(String size, String max) {
    return 'Файл занадта вялікі: $size (ліміт $max).';
  }
}
