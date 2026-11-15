# Dosya veya metin gönderme

Gönderme, bir dosyayı veya mesajı animasyonlu bir koda dönüştürür: her biri renkli şekillerden oluşan bir ızgara olan bir kare dizisi. Kodu tam ekranda gösterip diğer cihazın taramasını bekleyin ya da GIF olarak paylaşın.

## Uygulamada (Android, iPhone)

1. **Gönder** sekmesini açın.
2. **Metin**'i seçip mesajınızı yazın veya yapıştırın ya da **Dosya**'yı seçip bir dosya seçin.
3. İsteğe bağlı: bir **Parola** girin. Alıcının gönderdiğinizi açması için buna ihtiyacı olacak. Bkz. [Şifreleme](encryption.md).
4. İsteğe bağlı: **Kare gecikmesi**'ni değiştirin: kare başına 100, 200 veya 400 ms. Yavaş olan, alıcı kamera için daha kolaydır; hızlı olan daha çabuk biter.
5. Kodu tam ekranda göstermek için **Ekranda göster**'e, başka bir uygulama üzerinden animasyonlu GIF olarak göndermek için **GIF paylaş**'a dokunun.

Giriş alanının altındaki satır, boyutu ve kodun en fazla kaç kareden oluşacağını gösterir.

Gösterim sırasında uygulama ekranı açık tutar ve parlaklığı artırır. Çıktığınızda ikisi de normale döner.

## Web uygulamasında

1. **Gönder**'i açın.
2. **Dosya** (bir dosya seçin veya sürükleyip bırakın) ya da **Metin** (mesajınızı yazın) seçeneğini seçin.
3. İsteğe bağlı: **Parola ekle**.
4. İsteğe bağlı: **Gelişmiş** altında **Kare hızı**'nı seçin.
5. **Kod oluştur**'a dokunun. **Göndermeye hazır** ekranında **Tam ekranda göster**, **GIF paylaş** (paylaşımı destekleyen telefonlarda) veya **İndir**'i seçin.

## Oynamaya devam etsin

Gösterilen bir kod önce dosyanın her karesini bir kez gösterir, ardından durmadan *onarım kareleri* göstermeye devam eder. Alıcının dosyadaki kare sayısı kadar kareye ihtiyacı vardır ve hangileri olduğu fark etmez. Kaçırılan bir karenin yerini sonra gelen kare tutar; bu yüzden döngünün yeniden başlamasını beklemeye gerek yoktur. Alıcı bitti diyene kadar kodu ekranda tutun, yeter.

Bir GIF, dosyanın karelerine ek olarak yaklaşık dörtte biri kadar onarım karesi taşır; böylece alıcı her geçişte birkaç kareyi kaçırabilir.

## Ne kadar büyük olabilir?

Her kare yaklaşık 2 KB taşır. CimBar, gönderdiğinizi küçültecekse her zaman sıkıştırır; bu yüzden metin genellikle boyutunun düşündürdüğünden daha az kareye ihtiyaç duyar.

- Küçük dosyalar (yaklaşık 80 KB'a kadar) en hızlısıdır: birkaç düzine kare.
- **Göster** en fazla 4096 kareyi kaldırır.
- Uygulamadaki **GIF paylaş** 500 kareyle sınırlıdır.

Büyük dosyalar da çalışır, ancak taranmaları biraz sürer. Yaklaşık 100 kareden uzun kodlar için daha yavaş bir kare hızı seçin.
