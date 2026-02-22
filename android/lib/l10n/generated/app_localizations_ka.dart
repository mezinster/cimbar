import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Georgian (`ka`).
class AppLocalizationsKa extends AppLocalizations {
  AppLocalizationsKa([String locale = 'ka']) : super(locale);

  @override
  String get appTitle => 'CimBar სკანერი';

  @override
  String get tabImport => 'GIF იმპორტი';

  @override
  String get tabBinary => 'ბინარული იმპორტი';

  @override
  String get tabCamera => 'კამერა';

  @override
  String get tabSettings => 'შესახებ';

  @override
  String get importTitle => 'CimBar GIF იმპორტი';

  @override
  String get importBinaryTitle => 'ბინარული ფაილის იმპორტი';

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
  String get selectBinaryFile => 'აირჩიეთ ბინარული ფაილი C++ სკანერიდან';

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
  String get errorGeneric => 'მოხდა შეცდომა';

  @override
  String get errorDecryption => 'გაშიფვრა ვერ მოხერხდა — არასწორი პაროლი ან დაზიანებული მონაცემები';

  @override
  String get errorInvalidGif => 'არასწორი ან მხარდაუჭერელი GIF ფაილი';

  @override
  String get errorNoFrames => 'GIF არ შეიცავს კადრებს';

  @override
  String get errorFileTooLarge => 'ფაილი ძალიან დიდია დასამუშავებლად';

  @override
  String get cameraScanInstruction => 'გადაუღეთ ფოტო CimBar შტრიხკოდს დეკოდირებისთვის';

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
  String get errorNoFrameSizeMatch => 'შტრიხკოდის დეკოდირება ვერ მოხერხდა არცერთ მხარდაჭერილ კადრის ზომაზე';

  @override
  String get language => 'ენა';

  @override
  String get systemDefault => 'სისტემის ნაგულისხმევი';

  @override
  String get about => 'შესახებ';

  @override
  String get aboutDescription => 'CimBar სკანერი დეკოდირებს ფერადი ხატულების მატრიცულ შტრიხკოდებს. თავსებადია CimBar ვებ-კოდირებასთან: nfcarchiver.com/cimbar.';

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
    return 'სკანირება... $captured/$total კადრი დაფიქსირდა';
  }

  @override
  String get liveScanSearching => 'CimBar შტრიხკოდის ძიება...';

  @override
  String get liveScanComplete => 'ყველა კადრი დაფიქსირდა!';

  @override
  String get liveScanError => 'სკანირება ვერ მოხერხდა';

  @override
  String get cameraPermissionDenied => 'პირდაპირი სკანირებისთვის საჭიროა კამერის ნებართვა';

  @override
  String get noCameraAvailable => 'ამ მოწყობილობაზე კამერა მიუწვდომელია';

  @override
  String liveScanFramesAnalyzed(int count) {
    return '$count კადრი გაანალიზებულია';
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
  String get decodeTuning => 'Decode Tuning';

  @override
  String get symbolSensitivity => 'Symbol Sensitivity';

  @override
  String get symbolSensitivityDesc => 'Higher = stricter dot detection (corners must be brighter to read as 1)';

  @override
  String get whiteBalanceLabel => 'White Balance Correction';

  @override
  String get relativeColorLabel => 'Relative Color Matching';

  @override
  String get quadrantOffsetLabel => 'Quadrant Sample Offset';

  @override
  String get quadrantOffsetDesc => 'Corner sample position as fraction of cell size';

  @override
  String get resetDefaults => 'Reset to Defaults';

  @override
  String get privacyPolicy => 'კონფიდენციალურობის პოლიტიკა';

  @override
  String get licenseInfo => 'MIT ლიცენზია';

  @override
  String get sourceCode => 'საწყისი კოდი';
}
