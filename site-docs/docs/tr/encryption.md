# Şifreleme

Bir parolayla gönderdiğinizde dosya veya mesaj, koda dönüşmeden önce cihazınızda şifrelenir. Kodu herkes tarayabilir, ancak taşıdığı içeriği yalnızca parolayı bilen biri açabilir.

- **Algoritma:** AES-256-GCM. Anahtar, parolanızdan PBKDF2-SHA256 (150.000 yineleme) ve her dosya için rastgele bir tuzla türetilir.
- **Parola cihazınızdan asla çıkmaz.** Saklanmaz, günlüğe yazılmaz ve hiçbir yere gönderilmez.
- **Alıcının önceden bilmesi gerekmez.** CimBar şifreli bir dosyayı kendiliğinden tanır ve tüm kareler geldiğinde parolayı sorar.
- **Yanlış parola bir şey kaybettirmez.** Kareler zaten toplanmıştır: parolayı yeniden girin, yeniden taramaya gerek yok.

!!! warning "Kaybolan parola kurtarılamaz"
    Biz de dahil hiç kimse, şifreli bir dosyayı parolası olmadan açamaz.

Parolayı alıcıya kodun kendisinden başka bir yolla iletin, örneğin yüz yüze.
