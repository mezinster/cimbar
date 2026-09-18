// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'CimBar Scanner';

  @override
  String get tabImport => 'Import GIF';

  @override
  String get tabCamera => 'Camera';

  @override
  String get tabSettings => 'About';

  @override
  String get importTitle => 'Import CimBar GIF';

  @override
  String get cameraTitle => 'Camera Scanner';

  @override
  String get settingsTitle => 'About';

  @override
  String get selectFile => 'Select File';

  @override
  String get dropFileHere => 'Tap to select or drop a file here';

  @override
  String get selectGifFile => 'Select a CimBar GIF file to decode';

  @override
  String get passphrase => 'Passphrase';

  @override
  String get passphraseHint => 'Enter decryption passphrase';

  @override
  String get passphraseRequired => 'Passphrase is required';

  @override
  String get decode => 'Decode';

  @override
  String get decoding => 'Decoding...';

  @override
  String get cancel => 'Cancel';

  @override
  String get progressParsingGif => 'Parsing GIF...';

  @override
  String get progressDecodingFrames => 'Decoding frames...';

  @override
  String progressDecodingFrame(int current, int total) {
    return 'Decoding frame $current/$total';
  }

  @override
  String get progressReedSolomon => 'Reed-Solomon decoding...';

  @override
  String get progressDecrypting => 'Decrypting...';

  @override
  String get decodeSuccess => 'Successfully decoded!';

  @override
  String decodedFile(String filename) {
    return 'File: $filename';
  }

  @override
  String decodedSize(String size) {
    return 'Size: $size';
  }

  @override
  String get saveFile => 'Save File';

  @override
  String get shareFile => 'Share File';

  @override
  String get fileSaved => 'File saved successfully';

  @override
  String get errorGeneric => 'An error occurred';

  @override
  String get errorDecryption =>
      'Decryption failed — wrong passphrase or corrupted data';

  @override
  String get errorInvalidGif => 'Invalid or unsupported GIF file';

  @override
  String get errorNoFrames => 'GIF contains no frames';

  @override
  String get errorFileTooLarge => 'File is too large to process';

  @override
  String get cameraScanInstruction =>
      'Take a photo of a CimBar barcode to decode it';

  @override
  String get cameraTakePhoto => 'Take Photo';

  @override
  String get cameraFromGallery => 'Gallery';

  @override
  String get cameraRetake => 'Retake';

  @override
  String get progressLocatingBarcode => 'Locating barcode...';

  @override
  String get progressDetectingFrameSize => 'Detecting frame size...';

  @override
  String get errorBarcodeNotFound => 'No barcode found in photo';

  @override
  String get errorNoFrameSizeMatch =>
      'Could not decode barcode at any supported frame size';

  @override
  String get language => 'Language';

  @override
  String get systemDefault => 'System Default';

  @override
  String get about => 'About';

  @override
  String get aboutDescription =>
      'CimBar Scanner decodes Color Icon Matrix Barcodes. Compatible with the CimBar web encoder at nfcarchiver.com/cimbar.';

  @override
  String get webAppLabel => 'Web App';

  @override
  String get webAppUrl => 'https://nfcarchiver.com/cimbar/';

  @override
  String version(String version) {
    return 'Version $version';
  }

  @override
  String get liveScanButton => 'Live Scan';

  @override
  String liveScanProgress(int captured, int total) {
    return 'Scanning... $captured/$total frames';
  }

  @override
  String get liveScanSearching => 'Scanning for CimBar barcode...';

  @override
  String get liveScanComplete => 'All frames captured!';

  @override
  String get liveScanError => 'Scan failed';

  @override
  String get cameraPermissionDenied =>
      'Camera permission is required for live scanning';

  @override
  String get noCameraAvailable => 'No camera available on this device';

  @override
  String liveScanFramesAnalyzed(int count) {
    return '$count frames analyzed';
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
  String get errorPassphraseRequired =>
      'This file is encrypted: a passphrase is required';

  @override
  String errorDecoderFailed(String detail) {
    return 'Decoder failed: $detail';
  }

  @override
  String get errorNoBarcodeFound => 'No CimBar barcode found in the photo';

  @override
  String get tabFiles => 'Files';

  @override
  String get filesTitle => 'Decoded Files';

  @override
  String get noFilesYet => 'No decoded files yet';

  @override
  String get delete => 'Delete';

  @override
  String get deleteFileTitle => 'Delete File';

  @override
  String deleteFileConfirm(String filename) {
    return 'Delete $filename?';
  }

  @override
  String get fileDeleted => 'File deleted';

  @override
  String get developerSection => 'Developer';

  @override
  String get debugModeLabel => 'Debug Mode';

  @override
  String get debugModeDescription => 'Enable debug logging and frame capture';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get licenseInfo => 'MIT License';

  @override
  String get sourceCode => 'Source Code';
}
