# Nasıl çalışır

CimBar, dosyaları bir ekrandan bir kameraya göndermek için tasarlanmış renkli bir barkod biçimi olan **CimBar-XL**'i kullanır. Bağımsız bir biçimdir; ilk Color Icon Matrix Barcode projeleri olan, sz3'ün [libcimbar ve CFC](https://github.com/sz3/libcimbar) projelerinden esinlenmiştir ve onlarla uyumlu değildir.

## Bir kare

Her kare 64 × 64 hücrelik bir ızgaradır. Köşelerdeki dört kare konum deseni, ekran eğik olsa veya açılı görülse bile kameranın ızgarayı bulmasını sağlar. Diğer her hücre, 4 renkten birinde 16 şekilden birini taşır; bu da hücre başına 6 bit eder. Bir kare 2.880 bayt taşır.

## Hata düzeltme

Her karenin bir kısmı Reed-Solomon hata düzeltmesidir. Parlama, bulanıklık veya hare deseni yüzünden bazı hücreler yanlış okunsa da kare doğru okunur. Her kare, dosyanın kendisinden yaklaşık 2.100 bayt taşır.

## Çok sayıda kare, herhangi bir sıra

Bir kareden büyük bir dosya birkaç kareye bölünür. Her kare hangi dosyaya ait olduğunu ve dosyanın kaç kareye ihtiyaç duyduğunu söyler; böylece alıcı yeterince kare topladığını bilir.

Dosyanın kendi karelerinden sonra **onarım kareleri** gelir. Her biri dosyanın karelerinin bir karışımıdır ve öyle hesaplanır ki, dosya kareleri ya da onarım kareleri fark etmeksizin, dosya kadar kareden oluşan *herhangi* bir küme onu yeniden oluşturmaya yeter. Alıcının belirli bir kareyi yakalaması gerekmez: kaçırdığı bir karenin yerini sonra gelen herhangi bir kare alır.

## Sıkıştırma ve şifreleme

CimBar, bölmeden önce dosyayı en az %5 küçültecekse sıkıştırır (fotoğraflar ve arşivler genellikle zaten sıkıştırılmıştır ve olduğu gibi gönderilir). Ardından, bir parola verdiyseniz sonucu [şifreler](encryption.md).

## Her şey cihazlarınızda kalır

Kodlama ve çözme tamamen telefonunuzda veya tarayıcınızda çalışır. Kod yalnızca ışık olarak, bir ekrandan bir kameraya gider.

## Uyumluluk

Güncel tüm CimBar istemcileri (web, Android, iPhone) birbirlerinin kodlarını okur. Projenin bu biçimden önceki ilk sürümleriyle yapılan GIF'ler okunamaz ve yeniden oluşturulmaları gerekir.

Biçim açıktır: belirtimi ve tüm kaynak kodu [GitHub](https://github.com/mezinster/cimbar)'da.
