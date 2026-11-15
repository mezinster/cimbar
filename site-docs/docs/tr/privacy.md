# Gizlilik politikası

*Hukuken bağlayıcı olan İngilizce metindir: [Privacy policy](../../privacy/).*

**CimBar** · Son güncelleme: 15 Kasım 2026

Bu politika üç CimBar istemcisinin tamamını kapsar: [nfcarchiver.com/cimbar](https://nfcarchiver.com/cimbar/) adresindeki **web uygulaması**, **Android** uygulaması CimBar Scanner (`com.nfcarchiver.cimbar`) ve **iPhone** ile iPad uygulaması CimBar (`com.nfcarchiver.cimbar`). Bu dokümantasyon sitesini de kapsar.

## Kısaca

CimBar hiçbir şey toplamaz. Kodlama, çözme, sıkıştırma ve şifreleme tamamen cihazınızda gerçekleşir: tarayıcınızda ya da telefonunuzdaki uygulamada. Gönderdiğiniz veya aldığınız dosyalar ve mesajlar ile parolalarınız hiçbir sunucuya gönderilmez. Bir kod yalnızca ışık olarak, bir ekrandan bir kameraya gider.

## Veri toplama

**Hiçbir veri toplamıyoruz.** Ayrıntılı olarak:

- Kişisel bilgi yok.
- Kullanım analizi veya izleme yok.
- Çökme raporu yok.
- Çerez, reklam kimliği veya başka bir tanımlayıcı yok.
- Konum verisi yok.
- Gönderdiğiniz veya aldığınız dosyalar ve mesajlar yok, parolalar yok.

## Kamera

Kamera yalnızca CimBar kodlarını taramak için kullanılır (canlı tarama ve fotoğraflar). Kamera kareleri ve fotoğraflar bellekte çözülür ve ardından atılır; hiçbiri saklanmaz veya bir yere gönderilmez.

Tek istisna bir geliştirici seçeneğidir. Uygulamanın **Hakkında** sekmesinde **Hata Ayıklama Modu** açıkken, bir yakalama düğmesi dokunduğunuz kareyi uygulamanın özel depolama alanına kaydeder. Bu yalnızca siz dokunduğunuzda olur ve dosya cihazınızda kalır.

## Dosyalar ve mesajlar

- **Gönderme:** seçtiğiniz dosya veya yazdığınız metin cihazınızda okunur ve orada koda dönüştürülür. Paylaştığınız bir GIF yalnızca gönderdiğiniz yere gider.
- **Alma:** içe aktardığınız bir GIF veya fotoğraf, sistemin dosya seçicisi, fotoğraf seçicisi veya paylaşım sayfası üzerinden okunur; uygulama yalnızca sizin seçtiğinizi okur.
- **Alınan dosyalar** uygulamanın özel depolama alanında (uygulamada) saklanır ve yalnızca **Aç**, **Cihaza kaydet** veya **Paylaş**'ı seçtiğinizde oradan çıkar. Uygulamayı kaldırmak bunları siler. Web uygulaması hiçbir şey saklamaz: alınan bir dosya, siz onu kaydedene veya sayfadan ayrılana kadar sayfada bulunur.

## Şifreleme

Bir parolayla gönderdiğinizde içerik cihazınızda AES-256-GCM ile şifrelenir; anahtar parolanızdan PBKDF2-SHA256 ile türetilir (150.000 yineleme, her dosya için rastgele tuz). Parola asla saklanmaz, günlüğe yazılmaz veya iletilmez. Kaybolursa, biz de dahil hiç kimse içeriği kurtaramaz. Bkz. [Şifreleme](encryption.md).

## Web uygulaması

- Tamamen tarayıcınızda çalışır. Kodlama ve çözme hiçbir ağ isteği yapmaz.
- Sakladığı tek şey arayüz dilinizdir: dil seçiminin hatırlanması için tarayıcının yerel depolama alanında `cimbar.lang` anahtarı altında tutulur. Çerez kullanmaz. Sitenin verilerini temizlemek bunu siler.
- **Yazı tipleri:** sayfa yazı tiplerini Google Fonts'tan (`fonts.googleapis.com`, `fonts.gstatic.com`) yükler. Her web kaynağında olduğu gibi, tarayıcınızın isteği Google'a IP adresinizi ve tarayıcınızı gösterir; bkz. [Google Fonts gizlilik SSS](https://developers.google.com/fonts/faq/privacy). Dosya içeriği veya başka bir veri gönderilmez.
- **Barındırma:** sayfa, Amazon CloudFront üzerinden Amazon S3'ten sunulan statik bir sitedir. Amazon standart erişim günlüklerini (IP adresi, zaman, istenen adres, tarayıcı) kendi politikaları çerçevesinde tutar. Web uygulamasının kendisi hiçbir şey kaydetmez.

## Android uygulaması

Uygulamanın sahip olduğu her izin ve ne için olduğu:

- **Kamera** (`CAMERA`): CimBar kodlarını taramak için. Tek izin budur. Uygulamanın **internet izni yoktur** ve hiçbir sunucuya bağlanamaz.

Dil seçiminiz ve Hata Ayıklama Modu anahtarı uygulamanın yerel tercihlerinde saklanır. **Hakkında** sekmesindeki bağlantılar (gizlilik politikası, lisans, kaynak kodu) tarayıcınızda açılır; uygulamanın kendisi hiçbir ağ isteği yapmaz.

## iPhone ve iPad uygulaması

Uygulamanın isteyebileceği izinler ve ne için oldukları:

- **Kamera** (`NSCameraUsageDescription`): CimBar kodlarını taramak için.
- **Fotoğraflar** (`NSPhotoLibraryUsageDescription`): içlerindeki kodu çözmek üzere seçtiğiniz fotoğrafları açmak için. Uygulama yalnızca sizin seçtiğiniz fotoğrafları görür.
- **Mikrofon** (`NSMicrophoneUsageDescription`): uygulama **asla** ses kaydetmez ve mikrofon izni istemez. Bu açıklama yalnızca, kullandığı kamera bileşeni ses işlevleri de içerdiği için vardır; Apple bu işlevleri içeren her uygulamada açıklamanın bulunmasını şart koşar.

Başka bir uygulamadan CimBar'a bir dosya paylaştığınızda, paylaşım uzantısı dosyayı uygulamaya yalnızca ikisinin kullanabildiği bir depolama alanı (App Group) üzerinden iletir. Uygulama hiçbir ağ isteği yapmaz. Gizlilik bildirimi, izleme olmadığını ve hiçbir veri toplanmadığını beyan eder. Dil seçiminiz ve Hata Ayıklama Modu anahtarı cihazda saklanır.

## Bu web sitesi

Bu dokümantasyon sitesi çerez kullanmaz, analiz çalıştırmaz ve üçüncü taraf yazı tipi veya betik yüklemez. Araması tarayıcınızda yerel olarak çalışır. Web uygulamasıyla aynı şekilde barındırılır (Amazon S3 ve CloudFront, standart erişim günlükleriyle) ve bir kopyası GitHub Pages'ta yansıtılır; GitHub Pages kendi günlüklerini [GitHub gizlilik bildirimi](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) çerçevesinde tutar.

## Üçüncü taraf hizmetler

Uygulamalar hiçbir üçüncü taraf hizmet kullanmaz: analiz yok, bulut depolama yok, uzak sunucu yok, sosyal medya entegrasyonu yok. Web uygulaması, yukarıda açıklandığı gibi yalnızca Google Fonts'a ve barındırma hizmetine dayanır.

## Çocukların gizliliği

CimBar, çocuklar dahil hiç kimseden veri toplamaz.

## Bu politikadaki değişiklikler

Bu politika değişirse yeni metin bu sayfada yayımlanır ve yukarıdaki tarih güncellenir. Geçmişi [kaynak deposunda](https://github.com/mezinster/cimbar) bulunur.

## Açık kaynak

Web uygulaması ve uygulamalar açık kaynaklıdır (MIT lisansı): [github.com/mezinster/cimbar](https://github.com/mezinster/cimbar).

## İletişim

Bu politikayla ilgili sorular için: [support@nfcarchiver.com](mailto:support@nfcarchiver.com).
