// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Georgian (`ka`).
class AppLocalizationsKa extends AppLocalizations {
  AppLocalizationsKa([String locale = 'ka']) : super(locale);

  @override
  String get appTitle => 'CimBar სკანერი';

  @override
  String get tabImport => 'იმპორტი';

  @override
  String get tabCamera => 'კამერა';

  @override
  String get tabSettings => 'შესახებ';

  @override
  String get importTitle => 'CimBar GIF იმპორტი';

  @override
  String get cameraTitle => 'კამერის სკანერი';

  @override
  String get settingsTitle => 'შესახებ';

  @override
  String get selectFile => 'ფაილის არჩევა';

  @override
  String get dropFileHere => 'შეხებით აირჩიეთ ან გადმოიტანეთ ფაილი აქ';

  @override
  String get selectGifFile => 'აირჩიეთ CimBar GIF ფაილი დეკოდირებისთვის';

  @override
  String get passphrase => 'პაროლი';

  @override
  String get passphraseHint => 'შეიყვანეთ გაშიფვრის პაროლი';

  @override
  String get passphraseRequired => 'პაროლი აუცილებელია';

  @override
  String get decode => 'დეკოდირება';

  @override
  String get decoding => 'დეკოდირება...';

  @override
  String get cancel => 'გაუქმება';

  @override
  String get progressParsingGif => 'GIF-ის ანალიზი...';

  @override
  String get progressDecodingFrames => 'კადრების დეკოდირება...';

  @override
  String progressDecodingFrame(int current, int total) {
    return 'კადრის დეკოდირება $current/$total';
  }

  @override
  String get progressReedSolomon => 'რიდ-სოლომონის დეკოდირება...';

  @override
  String get progressDecrypting => 'გაშიფვრა...';

  @override
  String get decodeSuccess => 'წარმატებით დეკოდირდა!';

  @override
  String decodedFile(String filename) {
    return 'ფაილი: $filename';
  }

  @override
  String decodedSize(String size) {
    return 'ზომა: $size';
  }

  @override
  String get saveFile => 'ფაილის შენახვა';

  @override
  String get shareFile => 'ფაილის გაზიარება';

  @override
  String get fileSaved => 'ფაილი წარმატებით შეინახა';

  @override
  String get openFile => 'გახსნა';

  @override
  String get saveToDevice => 'მოწყობილობაზე შენახვა';

  @override
  String get savedToDevice => 'ფაილი შენახულია';

  @override
  String get noAppToOpen =>
      'ამ ტელეფონზე არ არის აპი, რომელსაც ამ ფაილის გახსნა შეუძლია';

  @override
  String get openFailed => 'ფაილის გახსნა ვერ მოხერხდა';

  @override
  String get passphrasePrompt =>
      'ფაილი დაშიფრულია. გასაშიფრად შეიყვანეთ პაროლი.';

  @override
  String get errorWrongPassphrase => 'არასწორი პაროლი. სცადეთ ხელახლა.';

  @override
  String get decrypt => 'გაშიფვრა';

  @override
  String get errorGeneric => 'მოხდა შეცდომა';

  @override
  String get errorDecryption =>
      'გაშიფვრა ვერ მოხერხდა — არასწორი პაროლი ან დაზიანებული მონაცემები';

  @override
  String get errorInvalidGif => 'არასწორი ან მხარდაუჭერელი GIF ფაილი';

  @override
  String get errorNoFrames => 'GIF არ შეიცავს კადრებს';

  @override
  String get errorFileTooLarge => 'ფაილი ძალიან დიდია დასამუშავებლად';

  @override
  String get cameraScanInstruction =>
      'გადაუღეთ ფოტო CimBar შტრიხკოდს დეკოდირებისთვის';

  @override
  String get cameraTakePhoto => 'ფოტოს გადაღება';

  @override
  String get cameraFromGallery => 'გალერეა';

  @override
  String get cameraRetake => 'ხელახლა გადაღება';

  @override
  String get progressLocatingBarcode => 'შტრიხკოდის ძიება...';

  @override
  String get progressDetectingFrameSize => 'კადრის ზომის განსაზღვრა...';

  @override
  String get errorBarcodeNotFound => 'ფოტოში შტრიხკოდი ვერ მოიძებნა';

  @override
  String get errorNoFrameSizeMatch =>
      'შტრიხკოდის დეკოდირება ვერ მოხერხდა არცერთ მხარდაჭერილ კადრის ზომაზე';

  @override
  String get language => 'ენა';

  @override
  String get systemDefault => 'სისტემის ნაგულისხმევი';

  @override
  String get about => 'შესახებ';

  @override
  String get aboutDescription =>
      'CimBar სკანერი დეკოდირებს ფერადი ხატულების მატრიცულ შტრიხკოდებს. თავსებადია CimBar ვებ-კოდირებასთან: nfcarchiver.com/cimbar.';

  @override
  String get aboutSuccessor =>
      'CimBar სკანერი შთაგონებულია sz3-ის libcimbar-ითა და CFC-ით — ფერადი ხატულების მატრიცული შტრიხკოდის (Color Icon Matrix Barcode) თავდაპირველი პროექტებით, მაგრამ ის ცალკე პროექტია და არა cimbar-ის ოფიციალური აპლიკაცია. ის იყენებს საკუთარ შტრიხკოდის ფორმატს, CimBar-XL-ს, ამიტომ ვერ კითხულობს libcimbar-ით ან CFC-ით შექმნილ შტრიხკოდებს, ისინი კი ვერ კითხულობენ მის შტრიხკოდებს.';

  @override
  String get webAppLabel => 'ვებ-აპლიკაცია';

  @override
  String get webAppUrl => 'https://nfcarchiver.com/cimbar/';

  @override
  String version(String version) {
    return 'ვერსია $version';
  }

  @override
  String get liveScanButton => 'პირდაპირი სკანირება';

  @override
  String liveScanProgress(int captured, int total) {
    return 'სკანირება... $captured/$total კადრი';
  }

  @override
  String get liveScanSearching => 'CimBar შტრიხკოდის ძიება...';

  @override
  String get liveScanComplete => 'ყველა კადრი დაფიქსირდა!';

  @override
  String get liveScanError => 'სკანირება ვერ მოხერხდა';

  @override
  String get cameraPermissionDenied =>
      'პირდაპირი სკანირებისთვის საჭიროა კამერის ნებართვა';

  @override
  String get noCameraAvailable => 'ამ მოწყობილობაზე კამერა მიუწვდომელია';

  @override
  String liveScanFramesAnalyzed(int count) {
    return '$count კადრი გაანალიზებულია';
  }

  @override
  String get liveScanAim => 'მოათავსეთ შტრიხკოდი კვადრატში';

  @override
  String get hintMoveCloser => 'მიიტანეთ უფრო ახლოს';

  @override
  String get hintMoveBack => 'გასწიეთ უფრო შორს';

  @override
  String get hintHoldStill => 'დაიჭირეთ უძრავად';

  @override
  String get hintAdjustAngle => 'შეცვალეთ კუთხე ან განათება';

  @override
  String errorMultiFrameNeedsLive(int total) {
    return 'ფაილი $total კადრისგან შედგება — გამოიყენეთ „პირდაპირი სკანირება“';
  }

  @override
  String get captureSaved => 'კადრი შეინახა აპის დოკუმენტებში';

  @override
  String get captureFailed => 'კადრის შენახვა ვერ მოხერხდა';

  @override
  String get errorPassphraseRequired => 'ფაილი დაშიფრულია: საჭიროა პაროლი';

  @override
  String errorDecoderFailed(String detail) {
    return 'დეკოდერის შეცდომა: $detail';
  }

  @override
  String get errorNoBarcodeFound => 'ფოტოში CimBar შტრიხკოდი ვერ მოიძებნა';

  @override
  String get shareReadFailed => 'გაზიარებული ელემენტის წაკითხვა ვერ მოხერხდა.';

  @override
  String get shareWhileDecoding =>
      'ჯერ დაელოდეთ მიმდინარე დეკოდირების დასრულებას, შემდეგ ფაილი ხელახლა გააზიარეთ.';

  @override
  String get shareChecking => 'გაზიარებული ფოტოს შემოწმება…';

  @override
  String shareOnlyFirst(int count) {
    return '$count ელემენტიდან იგზავნება მხოლოდ პირველი';
  }

  @override
  String shareTooLarge(String max) {
    return 'ფაილი ძალიან დიდია (ლიმიტი $max).';
  }

  @override
  String get tabFiles => 'ფაილები';

  @override
  String get filesTitle => 'ფაილები';

  @override
  String get noFilesYet => 'ფაილები ჯერ არ არის';

  @override
  String get delete => 'წაშლა';

  @override
  String get deleteFileTitle => 'ფაილის წაშლა';

  @override
  String deleteFileConfirm(String filename) {
    return 'წაიშალოს $filename?';
  }

  @override
  String get fileDeleted => 'ფაილი წაიშალა';

  @override
  String get developerSection => 'დეველოპერი';

  @override
  String get debugModeLabel => 'გამართვის რეჟიმი';

  @override
  String get debugModeDescription =>
      'გამართვის ჟურნალის და კადრების გადაღების ჩართვა';

  @override
  String get privacyPolicy => 'კონფიდენციალურობის პოლიტიკა';

  @override
  String get licenseInfo => 'MIT ლიცენზია';

  @override
  String get sourceCode => 'საწყისი კოდი';

  @override
  String get receivedText => 'მიღებული ტექსტი';

  @override
  String get copyText => 'კოპირება';

  @override
  String get textCopied => 'დაკოპირდა ბუფერში';

  @override
  String get shareText => 'ტექსტის გაზიარება';

  @override
  String textTruncated(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'ნაჩვენებია პირველი $countString სიმბოლო — კოპირება, გაზიარება და შენახვა მთლიან ტექსტს იყენებს.';
  }

  @override
  String get tabSend => 'გაგზავნა';

  @override
  String get sendModeText => 'ტექსტი';

  @override
  String get sendModeFile => 'ფაილი';

  @override
  String get sendTextHint => 'აკრიფეთ ან ჩასვით ტექსტი…';

  @override
  String sendEstimate(String size, int frames) {
    return '$size · მაქს. $frames კადრი';
  }

  @override
  String get sendFrameDelay => 'კადრის დაყოვნება';

  @override
  String get sendPresent => 'ეკრანზე ჩვენება';

  @override
  String get sendShareGif => 'GIF-ის გაზიარება';

  @override
  String get sendEmpty => 'ჯერ შეიყვანეთ ტექსტი ან აირჩიეთ ფაილი.';

  @override
  String sendTooLarge(int frames, int max) {
    return 'ზედმეტად დიდია: $frames კადრი (ლიმიტი $max).';
  }

  @override
  String sendFailed(String error) {
    return 'კოდირება ვერ მოხერხდა: $error';
  }

  @override
  String presentSource(int i, int n) {
    return 'კადრი $i / $n';
  }

  @override
  String presentRepair(int r) {
    return 'აღდგენის კადრი $r';
  }

  @override
  String sendFileTooBig(String size, String max) {
    return 'ფაილი ზედმეტად დიდია: $size (ლიმიტი $max).';
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
  String get sendChoosePhoto => 'ფოტოს არჩევა';

  @override
  String get photoOptimiseTitle => 'ფოტოს ოპტიმიზაცია';

  @override
  String get photoFramesToSend => 'გასაგზავნი კადრები';

  @override
  String photoTransferTime(int frames, double seconds, int delay) {
    final intl.NumberFormat secondsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String secondsString = secondsNumberFormat.format(seconds);

    return '$frames კადრი · ≈ $secondsString წმ, $delay ms დაყოვნებით';
  }

  @override
  String photoGifCapNote(int max) {
    return '„GIF-ის გაზიარება“ იტევს მაქსიმუმ $max კადრს; მეტი — მხოლოდ „ეკრანზე ჩვენებით“';
  }

  @override
  String get photoManual => 'ხელით';

  @override
  String get photoBackToAuto => 'ავტომატურზე დაბრუნება';

  @override
  String photoQuality(int quality) {
    return 'ხარისხი $quality';
  }

  @override
  String get photoSide => 'გრძელი მხარე';

  @override
  String get photoOriginal => 'ორიგინალი';

  @override
  String get photoSkip => 'გამოტოვება (ორიგინალის შენარჩუნება)';

  @override
  String get photoContinue => 'გაგრძელება';

  @override
  String photoContinueWith(int count) {
    return 'გაგრძელება $count კადრით';
  }

  @override
  String photoContinueAsIs(int count) {
    return 'ამ სურათით გაგრძელება ($count კადრი)';
  }

  @override
  String photoDoesNotFit(int frames, int needed) {
    return '$frames კადრში არ ეტევა — საჭიროა მინიმუმ $needed კადრი';
  }

  @override
  String get photoDecodeError =>
      'ამ ფოტოს წაკითხვა ვერ ხერხდება. ორიგინალი ფაილის გასაგზავნად შეეხეთ „გამოტოვებას“.';

  @override
  String get photoMemoryError =>
      'ამ მოწყობილობაზე ამ ფოტოს ოპტიმიზაციისთვის საკმარისი მეხსიერება არ არის.';

  @override
  String photoResultLabel(int width, int height, int quality, int kb) {
    return '$width×$height · q$quality · $kb KB';
  }

  @override
  String get photoFewerFrames => 'ნაკლები კადრი';

  @override
  String get photoMoreFrames => 'მეტი კადრი';

  @override
  String get photoEditFrameCount => 'ორჯერ შეეხეთ რიცხვის შესაყვანად';

  @override
  String get shareWhileEncoding =>
      'ჯერ დაელოდეთ მიმდინარე შტრიხკოდის შექმნის დასრულებას, შემდეგ ხელახლა გააზიარეთ.';

  @override
  String get sharePresentConfirm =>
      'შეწყდეს ჩვენება და ჩაიტვირთოს გაზიარებული ელემენტი?';

  @override
  String get shareReplaceTextConfirm =>
      'ჩანაცვლდეს თქვენ მიერ აკრეფილი ტექსტი?';

  @override
  String get shareSendInstead => 'ამის ნაცვლად ამ ფოტოს გაგზავნა';

  @override
  String get commonYes => 'დიახ';

  @override
  String get commonNo => 'არა';

  @override
  String get wideSendEmpty => 'შტრიხკოდი აქ გამოჩნდება აკრეფისას';

  @override
  String get wideResultEmpty => 'დეკოდირებული ფაილი აქ გამოჩნდება';

  @override
  String get previewFullScreen => 'სრული ეკრანი';
}
