// This file is a manual stub so the project compiles before `flutter gen-l10n`.
// After running `flutter gen-l10n`, the real generated file replaces this.
// To regenerate: flutter gen-l10n

import 'package:flutter/widgets.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ru'),
    Locale('tr'),
    Locale('uk'),
    Locale('ka'),
  ];

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  String get appTitle => 'CimBar Scanner';
  String get tabImport => 'Import GIF';
  String get tabBinary => 'Import Binary';
  String get tabCamera => 'Camera';
  String get tabSettings => 'Settings';
  String get importTitle => 'Import CimBar GIF';
  String get importBinaryTitle => 'Import Binary File';
  String get cameraTitle => 'Camera Scanner';
  String get settingsTitle => 'Settings';
  String get selectFile => 'Select File';
  String get dropFileHere => 'Tap to select or drop a file here';
  String get selectGifFile => 'Select a CimBar GIF file to decode';
  String get selectBinaryFile => 'Select a binary file from C++ scanner';
  String get passphrase => 'Passphrase';
  String get passphraseHint => 'Enter decryption passphrase';
  String get passphraseRequired => 'Passphrase is required';
  String get decode => 'Decode';
  String get decoding => 'Decoding...';
  String get cancel => 'Cancel';
  String get progressParsingGif => 'Parsing GIF...';
  String get progressDecodingFrames => 'Decoding frames...';
  String progressDecodingFrame(int current, int total) =>
      'Decoding frame $current/$total';
  String get progressReedSolomon => 'Reed-Solomon decoding...';
  String get progressDecrypting => 'Decrypting...';
  String get decodeSuccess => 'Successfully decoded!';
  String decodedFile(String filename) => 'File: $filename';
  String decodedSize(String size) => 'Size: $size';
  String get saveFile => 'Save File';
  String get shareFile => 'Share File';
  String get fileSaved => 'File saved successfully';
  String get errorGeneric => 'An error occurred';
  String get errorDecryption =>
      'Decryption failed — wrong passphrase or corrupted data';
  String get errorInvalidGif => 'Invalid or unsupported GIF file';
  String get errorNoFrames => 'GIF contains no frames';
  String get errorFileTooLarge => 'File is too large to process';
  String get cameraScanInstruction =>
      'Take a photo of a CimBar barcode to decode it';
  String get cameraTakePhoto => 'Take Photo';
  String get cameraFromGallery => 'Gallery';
  String get cameraRetake => 'Retake';
  String get progressLocatingBarcode => 'Locating barcode...';
  String get progressDetectingFrameSize => 'Detecting frame size...';
  String get errorBarcodeNotFound => 'No barcode found in photo';
  String get errorNoFrameSizeMatch =>
      'Could not decode barcode at any supported frame size';
  String get language => 'Language';
  String get systemDefault => 'System Default';
  String get about => 'About';
  String get aboutDescription =>
      'CimBar Scanner decodes Color Icon Matrix Barcodes. Compatible with the CimBar web encoder at nfcarchiver.com/cimbar.';
  String get webAppLabel => 'Web App';
  String get webAppUrl => 'https://nfcarchiver.com/cimbar/';
  String version(String version) => 'Version $version';
  String get liveScanButton => 'Live Scan';
  String liveScanProgress(int captured, int total) =>
      'Scanning... $captured/$total frames captured';
  String get liveScanSearching => 'Scanning for CimBar barcode...';
  String get liveScanComplete => 'All frames captured!';
  String get liveScanError => 'Scan failed';
  String get cameraPermissionDenied =>
      'Camera permission is required for live scanning';
  String get noCameraAvailable => 'No camera available on this device';
  String liveScanFramesAnalyzed(int count) => '$count frames analyzed';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'ru', 'tr', 'uk', 'ka'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
