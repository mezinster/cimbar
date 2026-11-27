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
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'кадраў',
      many: 'кадраў',
      few: 'кадраў',
      one: 'кадра',
    );
    return 'Сканаванне... $captured/$total $_temp0';
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
  String get shareReadFailed => 'Не ўдалося прачытаць дасланы элемент.';

  @override
  String get shareWhileDecoding =>
      'Спачатку дачакайцеся заканчэння бягучага дэкадавання, потым дашліце файл зноў.';

  @override
  String get shareChecking => 'Правяраем дасланае фота…';

  @override
  String shareOnlyFirst(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Адпраўляецца толькі першы з $count элемента',
      many: 'Адпраўляецца толькі першы з $count элементаў',
      few: 'Адпраўляецца толькі першы з $count элементаў',
      one: 'Адпраўляецца толькі першы з $count элемента',
    );
    return '$_temp0';
  }

  @override
  String shareTooLarge(String max) {
    return 'Файл занадта вялікі (ліміт $max).';
  }

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
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Паказаны першыя $countString сімвалаў — «Капіяваць», «Падзяліцца» і «Захаваць» выкарыстоўваюць увесь тэкст.';
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
  String get sendChoosePhoto => 'Выбраць фота';

  @override
  String get photoOptimiseTitle => 'Аптымізацыя фота';

  @override
  String get photoFramesToSend => 'Кадраў для адпраўкі';

  @override
  String photoTransferTime(int frames, double seconds, int delay) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String secondsString = secondsNumberFormat.format(seconds);

    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: '$frames кадра',
      many: '$frames кадраў',
      few: '$frames кадры',
      one: '$frames кадр',
    );
    return '$_temp0 · ≈ $secondsString с пры $delay мс';
  }

  @override
  String photoGifCapNote(int max) {
    return '«Падзяліцца GIF» умяшчае да $max кадраў; больш — толькі «Паказаць на экране»';
  }

  @override
  String get photoManual => 'Уручную';

  @override
  String get photoBackToAuto => 'Аўтаматычна';

  @override
  String photoQuality(int quality) {
    return 'Якасць $quality';
  }

  @override
  String get photoSide => 'Доўгі бок';

  @override
  String get photoOriginal => 'Арыгінал';

  @override
  String get photoSkip => 'Прапусціць (пакінуць арыгінал)';

  @override
  String get photoContinue => 'Працягнуць';

  @override
  String photoContinueWith(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Працягнуць з $count кадра',
      many: 'Працягнуць з $count кадрамі',
      few: 'Працягнуць з $count кадрамі',
      one: 'Працягнуць з $count кадрам',
    );
    return '$_temp0';
  }

  @override
  String photoContinueAsIs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Працягнуць з гэтай выявай ($count кадра)',
      many: 'Працягнуць з гэтай выявай ($count кадраў)',
      few: 'Працягнуць з гэтай выявай ($count кадры)',
      one: 'Працягнуць з гэтай выявай ($count кадр)',
    );
    return '$_temp0';
  }

  @override
  String photoDoesNotFit(int frames, int needed) {
    String _temp0 = intl.Intl.pluralLogic(
      frames,
      locale: localeName,
      other: 'Не змяшчаецца ў $frames кадра',
      many: 'Не змяшчаецца ў $frames кадраў',
      few: 'Не змяшчаецца ў $frames кадры',
      one: 'Не змяшчаецца ў $frames кадр',
    );
    String _temp1 = intl.Intl.pluralLogic(
      needed,
      locale: localeName,
      other: 'патрэбна мінімум $needed кадра',
      many: 'патрэбна мінімум $needed кадраў',
      few: 'патрэбна мінімум $needed кадры',
      one: 'патрэбны мінімум $needed кадр',
    );
    return '$_temp0 — $_temp1';
  }

  @override
  String get photoDecodeError =>
      'Не ўдаецца прачытаць гэта фота. Націсніце «Прапусціць», каб адправіць зыходны файл.';

  @override
  String get photoMemoryError =>
      'На гэтай прыладзе не хапае памяці, каб аптымізаваць гэта фота.';

  @override
  String photoResultLabel(int width, int height, int quality, int kb) {
    return '$width×$height · q$quality · $kb КБ';
  }

  @override
  String get photoFewerFrames => 'Менш кадраў';

  @override
  String get photoMoreFrames => 'Больш кадраў';

  @override
  String get photoEditFrameCount => 'Двойчы націсніце, каб увесці лік';

  @override
  String get shareWhileEncoding =>
      'Спачатку дачакайцеся заканчэння стварэння бягучага штрых-кода, потым падзяліцеся зноў.';

  @override
  String get sharePresentConfirm =>
      'Спыніць паказ і загрузіць атрыманы элемент?';

  @override
  String get shareReplaceTextConfirm => 'Замяніць уведзены тэкст?';

  @override
  String get shareSendInstead => 'Адправіць гэта фота';

  @override
  String get commonYes => 'Так';

  @override
  String get commonNo => 'Не';

  @override
  String get wideSendEmpty => 'Штрых-код з\'явіцца тут, пакуль вы друкуеце';

  @override
  String get wideResultEmpty => 'Тут з\'явіцца дэкадаваны файл';

  @override
  String get previewFullScreen => 'На ўвесь экран';
}
