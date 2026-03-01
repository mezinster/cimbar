import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ka.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_uk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ka'),
    Locale('ru'),
    Locale('tr'),
    Locale('uk')
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'CimBar Scanner'**
  String get appTitle;

  /// Bottom navigation tab for GIF import
  ///
  /// In en, this message translates to:
  /// **'Import GIF'**
  String get tabImport;

  /// Bottom navigation tab for binary import
  ///
  /// In en, this message translates to:
  /// **'Import Binary'**
  String get tabBinary;

  /// Bottom navigation tab for camera scanning
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get tabCamera;

  /// Bottom navigation tab for about/info
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get tabSettings;

  /// Title for GIF import screen
  ///
  /// In en, this message translates to:
  /// **'Import CimBar GIF'**
  String get importTitle;

  /// Title for binary import screen
  ///
  /// In en, this message translates to:
  /// **'Import Binary File'**
  String get importBinaryTitle;

  /// Title for camera screen
  ///
  /// In en, this message translates to:
  /// **'Camera Scanner'**
  String get cameraTitle;

  /// Title for about screen
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsTitle;

  /// Button to open file picker
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get selectFile;

  /// Hint text in file picker zone
  ///
  /// In en, this message translates to:
  /// **'Tap to select or drop a file here'**
  String get dropFileHere;

  /// Instruction for GIF import
  ///
  /// In en, this message translates to:
  /// **'Select a CimBar GIF file to decode'**
  String get selectGifFile;

  /// Instruction for binary import
  ///
  /// In en, this message translates to:
  /// **'Select a binary file from C++ scanner'**
  String get selectBinaryFile;

  /// Label for passphrase field
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get passphrase;

  /// Hint for passphrase field
  ///
  /// In en, this message translates to:
  /// **'Enter decryption passphrase'**
  String get passphraseHint;

  /// Error when passphrase is empty
  ///
  /// In en, this message translates to:
  /// **'Passphrase is required'**
  String get passphraseRequired;

  /// Button to start decoding
  ///
  /// In en, this message translates to:
  /// **'Decode'**
  String get decode;

  /// Status while decoding
  ///
  /// In en, this message translates to:
  /// **'Decoding...'**
  String get decoding;

  /// Cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Progress status
  ///
  /// In en, this message translates to:
  /// **'Parsing GIF...'**
  String get progressParsingGif;

  /// Progress status
  ///
  /// In en, this message translates to:
  /// **'Decoding frames...'**
  String get progressDecodingFrames;

  /// Progress status with frame number
  ///
  /// In en, this message translates to:
  /// **'Decoding frame {current}/{total}'**
  String progressDecodingFrame(int current, int total);

  /// Progress status
  ///
  /// In en, this message translates to:
  /// **'Reed-Solomon decoding...'**
  String get progressReedSolomon;

  /// Progress status
  ///
  /// In en, this message translates to:
  /// **'Decrypting...'**
  String get progressDecrypting;

  /// Success message
  ///
  /// In en, this message translates to:
  /// **'Successfully decoded!'**
  String get decodeSuccess;

  /// Decoded filename display
  ///
  /// In en, this message translates to:
  /// **'File: {filename}'**
  String decodedFile(String filename);

  /// Decoded file size display
  ///
  /// In en, this message translates to:
  /// **'Size: {size}'**
  String decodedSize(String size);

  /// Button to save decoded file
  ///
  /// In en, this message translates to:
  /// **'Save File'**
  String get saveFile;

  /// Button to share decoded file
  ///
  /// In en, this message translates to:
  /// **'Share File'**
  String get shareFile;

  /// Success message after saving
  ///
  /// In en, this message translates to:
  /// **'File saved successfully'**
  String get fileSaved;

  /// Generic error message
  ///
  /// In en, this message translates to:
  /// **'An error occurred'**
  String get errorGeneric;

  /// Decryption error message
  ///
  /// In en, this message translates to:
  /// **'Decryption failed — wrong passphrase or corrupted data'**
  String get errorDecryption;

  /// GIF parsing error
  ///
  /// In en, this message translates to:
  /// **'Invalid or unsupported GIF file'**
  String get errorInvalidGif;

  /// Empty GIF error
  ///
  /// In en, this message translates to:
  /// **'GIF contains no frames'**
  String get errorNoFrames;

  /// File size error
  ///
  /// In en, this message translates to:
  /// **'File is too large to process'**
  String get errorFileTooLarge;

  /// Instruction text on camera screen
  ///
  /// In en, this message translates to:
  /// **'Take a photo of a CimBar barcode to decode it'**
  String get cameraScanInstruction;

  /// Button to capture photo with camera
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get cameraTakePhoto;

  /// Button to pick photo from gallery
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get cameraFromGallery;

  /// Button to discard photo and take a new one
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get cameraRetake;

  /// Progress status while scanning photo for barcode
  ///
  /// In en, this message translates to:
  /// **'Locating barcode...'**
  String get progressLocatingBarcode;

  /// Progress status while trying frame sizes
  ///
  /// In en, this message translates to:
  /// **'Detecting frame size...'**
  String get progressDetectingFrameSize;

  /// Error when barcode region cannot be located
  ///
  /// In en, this message translates to:
  /// **'No barcode found in photo'**
  String get errorBarcodeNotFound;

  /// Error when no frame size produces valid decode
  ///
  /// In en, this message translates to:
  /// **'Could not decode barcode at any supported frame size'**
  String get errorNoFrameSizeMatch;

  /// Language setting label
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// System default language option
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// About section label
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// About section description
  ///
  /// In en, this message translates to:
  /// **'CimBar Scanner decodes Color Icon Matrix Barcodes. Compatible with the CimBar web encoder at nfcarchiver.com/cimbar.'**
  String get aboutDescription;

  /// Label for the web app link
  ///
  /// In en, this message translates to:
  /// **'Web App'**
  String get webAppLabel;

  /// URL of the CimBar web app
  ///
  /// In en, this message translates to:
  /// **'https://nfcarchiver.com/cimbar/'**
  String get webAppUrl;

  /// Version display
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String version(String version);

  /// Button to start live camera scanning
  ///
  /// In en, this message translates to:
  /// **'Live Scan'**
  String get liveScanButton;

  /// Progress during live scanning
  ///
  /// In en, this message translates to:
  /// **'Scanning... {captured}/{total} frames captured'**
  String liveScanProgress(int captured, int total);

  /// Status while searching for barcode in camera feed
  ///
  /// In en, this message translates to:
  /// **'Scanning for CimBar barcode...'**
  String get liveScanSearching;

  /// Status when all frames have been captured
  ///
  /// In en, this message translates to:
  /// **'All frames captured!'**
  String get liveScanComplete;

  /// Error during live scanning
  ///
  /// In en, this message translates to:
  /// **'Scan failed'**
  String get liveScanError;

  /// Error when camera permission is denied
  ///
  /// In en, this message translates to:
  /// **'Camera permission is required for live scanning'**
  String get cameraPermissionDenied;

  /// Error when no camera is found
  ///
  /// In en, this message translates to:
  /// **'No camera available on this device'**
  String get noCameraAvailable;

  /// Counter of camera frames processed during live scanning
  ///
  /// In en, this message translates to:
  /// **'{count} frames analyzed'**
  String liveScanFramesAnalyzed(int count);

  /// Bottom navigation tab for file explorer
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get tabFiles;

  /// Title for file explorer screen
  ///
  /// In en, this message translates to:
  /// **'Decoded Files'**
  String get filesTitle;

  /// Empty state message in file explorer
  ///
  /// In en, this message translates to:
  /// **'No decoded files yet'**
  String get noFilesYet;

  /// Delete action label
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Title for delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete File'**
  String get deleteFileTitle;

  /// Confirmation message for file deletion
  ///
  /// In en, this message translates to:
  /// **'Delete {filename}?'**
  String deleteFileConfirm(String filename);

  /// Snackbar message after file deletion
  ///
  /// In en, this message translates to:
  /// **'File deleted'**
  String get fileDeleted;

  /// Section title for camera decode tuning settings
  ///
  /// In en, this message translates to:
  /// **'Decode Tuning'**
  String get decodeTuning;

  /// Label for symbol detection threshold slider
  ///
  /// In en, this message translates to:
  /// **'Symbol Sensitivity'**
  String get symbolSensitivity;

  /// Description for symbol sensitivity slider
  ///
  /// In en, this message translates to:
  /// **'Higher = stricter dot detection (corners must be brighter to read as 1)'**
  String get symbolSensitivityDesc;

  /// Label for white balance toggle
  ///
  /// In en, this message translates to:
  /// **'White Balance Correction'**
  String get whiteBalanceLabel;

  /// Label for relative color matching toggle
  ///
  /// In en, this message translates to:
  /// **'Relative Color Matching'**
  String get relativeColorLabel;

  /// Label for quadrant offset slider
  ///
  /// In en, this message translates to:
  /// **'Quadrant Sample Offset'**
  String get quadrantOffsetLabel;

  /// Description for quadrant offset slider
  ///
  /// In en, this message translates to:
  /// **'Corner sample position as fraction of cell size'**
  String get quadrantOffsetDesc;

  /// Label for hash-based symbol detection toggle
  ///
  /// In en, this message translates to:
  /// **'Hash Symbol Detection'**
  String get hashDetectionLabel;

  /// Button to reset tuning to default values
  ///
  /// In en, this message translates to:
  /// **'Reset to Defaults'**
  String get resetDefaults;

  /// Section title for developer settings
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get developerSection;

  /// Label for debug mode toggle
  ///
  /// In en, this message translates to:
  /// **'Debug Mode'**
  String get debugModeLabel;

  /// Description for debug mode toggle
  ///
  /// In en, this message translates to:
  /// **'Enable debug logging and frame capture'**
  String get debugModeDescription;

  /// Label for Privacy Policy link
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// License name shown in About screen
  ///
  /// In en, this message translates to:
  /// **'MIT License'**
  String get licenseInfo;

  /// Label for source code / GitHub link
  ///
  /// In en, this message translates to:
  /// **'Source Code'**
  String get sourceCode;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'ka', 'ru', 'tr', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'ka': return AppLocalizationsKa();
    case 'ru': return AppLocalizationsRu();
    case 'tr': return AppLocalizationsTr();
    case 'uk': return AppLocalizationsUk();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
