// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appTitle => 'CimBar Tarayıcı';

  @override
  String get tabImport => 'GIF İçe Aktar';

  @override
  String get tabCamera => 'Kamera';

  @override
  String get tabSettings => 'Hakkında';

  @override
  String get importTitle => 'CimBar GIF İçe Aktar';

  @override
  String get cameraTitle => 'Kamera Tarayıcı';

  @override
  String get settingsTitle => 'Hakkında';

  @override
  String get selectFile => 'Dosya Seç';

  @override
  String get dropFileHere => 'Seçmek için dokunun veya dosyayı buraya bırakın';

  @override
  String get selectGifFile => 'Çözümlemek için bir CimBar GIF dosyası seçin';

  @override
  String get passphrase => 'Parola';

  @override
  String get passphraseHint => 'Şifre çözme parolasını girin';

  @override
  String get passphraseRequired => 'Parola gerekli';

  @override
  String get decode => 'Çöz';

  @override
  String get decoding => 'Çözümleniyor...';

  @override
  String get cancel => 'İptal';

  @override
  String get progressParsingGif => 'GIF ayrıştırılıyor...';

  @override
  String get progressDecodingFrames => 'Kareler çözümleniyor...';

  @override
  String progressDecodingFrame(int current, int total) {
    return 'Kare çözümleniyor $current/$total';
  }

  @override
  String get progressReedSolomon => 'Reed-Solomon çözümleme...';

  @override
  String get progressDecrypting => 'Şifre çözülüyor...';

  @override
  String get decodeSuccess => 'Başarıyla çözümlendi!';

  @override
  String decodedFile(String filename) {
    return 'Dosya: $filename';
  }

  @override
  String decodedSize(String size) {
    return 'Boyut: $size';
  }

  @override
  String get saveFile => 'Dosyayı Kaydet';

  @override
  String get shareFile => 'Dosyayı Paylaş';

  @override
  String get fileSaved => 'Dosya başarıyla kaydedildi';

  @override
  String get openFile => 'Aç';

  @override
  String get saveToDevice => 'Cihaza kaydet';

  @override
  String get savedToDevice => 'Dosya kaydedildi';

  @override
  String get noAppToOpen =>
      'Bu telefonda bu dosyayı açabilecek bir uygulama yok';

  @override
  String get openFailed => 'Dosya açılamadı';

  @override
  String get passphrasePrompt =>
      'Bu dosya şifreli. Şifresini çözmek için parolayı girin.';

  @override
  String get errorWrongPassphrase => 'Yanlış parola. Tekrar deneyin.';

  @override
  String get decrypt => 'Şifreyi çöz';

  @override
  String get errorGeneric => 'Bir hata oluştu';

  @override
  String get errorDecryption =>
      'Şifre çözme başarısız — yanlış parola veya bozuk veri';

  @override
  String get errorInvalidGif => 'Geçersiz veya desteklenmeyen GIF dosyası';

  @override
  String get errorNoFrames => 'GIF kare içermiyor';

  @override
  String get errorFileTooLarge => 'Dosya işlemek için çok büyük';

  @override
  String get cameraScanInstruction =>
      'Çözümlemek için bir CimBar barkodunun fotoğrafını çekin';

  @override
  String get cameraTakePhoto => 'Fotoğraf Çek';

  @override
  String get cameraFromGallery => 'Galeri';

  @override
  String get cameraRetake => 'Yeniden Çek';

  @override
  String get progressLocatingBarcode => 'Barkod aranıyor...';

  @override
  String get progressDetectingFrameSize => 'Kare boyutu algılanıyor...';

  @override
  String get errorBarcodeNotFound => 'Fotoğrafta barkod bulunamadı';

  @override
  String get errorNoFrameSizeMatch =>
      'Desteklenen hiçbir kare boyutunda barkod çözümlenemedi';

  @override
  String get language => 'Dil';

  @override
  String get systemDefault => 'Sistem Varsayılanı';

  @override
  String get about => 'Hakkında';

  @override
  String get aboutDescription =>
      'CimBar Tarayıcı, Renkli Simge Matris Barkodlarını çözümler. nfcarchiver.com/cimbar adresindeki CimBar web kodlayıcı ile uyumludur.';

  @override
  String get aboutSuccessor =>
      'CimBar Tarayıcı, sz3\'ün özgün Renkli Simge Matris Barkodu (Color Icon Matrix Barcode) projeleri libcimbar ve CFC\'nin halefidir. Kendine ait, daha yeni bir barkod biçimi kullanır; bu nedenle libcimbar veya CFC ile oluşturulan barkodları okuyamaz, onlar da bu uygulamanın barkodlarını okuyamaz.';

  @override
  String get webAppLabel => 'Web Uygulaması';

  @override
  String get webAppUrl => 'https://nfcarchiver.com/cimbar/';

  @override
  String version(String version) {
    return 'Sürüm $version';
  }

  @override
  String get liveScanButton => 'Canlı Tarama';

  @override
  String liveScanProgress(int captured, int total) {
    return 'Taranıyor... $captured/$total kare';
  }

  @override
  String get liveScanSearching => 'CimBar barkodu aranıyor...';

  @override
  String get liveScanComplete => 'Tüm kareler yakalandı!';

  @override
  String get liveScanError => 'Tarama başarısız';

  @override
  String get cameraPermissionDenied => 'Canlı tarama için kamera izni gerekli';

  @override
  String get noCameraAvailable => 'Bu cihazda kamera yok';

  @override
  String liveScanFramesAnalyzed(int count) {
    return '$count kare analiz edildi';
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
  String get errorPassphraseRequired => 'Bu dosya şifreli: parola gerekli';

  @override
  String errorDecoderFailed(String detail) {
    return 'Decoder failed: $detail';
  }

  @override
  String get errorNoBarcodeFound => 'No CimBar barcode found in the photo';

  @override
  String get shareReadFailed =>
      'Paylaşılan dosya okunamadı. Bunun yerine GIF İçe Aktar ile açın.';

  @override
  String get shareWhileDecoding =>
      'Önce mevcut çözümlemenin bitmesini bekleyin, ardından dosyayı yeniden paylaşın.';

  @override
  String get tabFiles => 'Dosyalar';

  @override
  String get filesTitle => 'Dosyalar';

  @override
  String get noFilesYet => 'Henüz dosya yok';

  @override
  String get delete => 'Sil';

  @override
  String get deleteFileTitle => 'Dosyayı Sil';

  @override
  String deleteFileConfirm(String filename) {
    return '$filename silinsin mi?';
  }

  @override
  String get fileDeleted => 'Dosya silindi';

  @override
  String get developerSection => 'Geliştirici';

  @override
  String get debugModeLabel => 'Hata Ayıklama Modu';

  @override
  String get debugModeDescription =>
      'Hata ayıklama günlüğü ve kare yakalamayı etkinleştir';

  @override
  String get privacyPolicy => 'Gizlilik Politikası';

  @override
  String get licenseInfo => 'MIT Lisansı';

  @override
  String get sourceCode => 'Kaynak Kodu';
}
