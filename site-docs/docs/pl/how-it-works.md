# Jak to działa

CimBar używa formatu **CimBar-XL** — kolorowego kodu kreskowego stworzonego do przesyłania plików z ekranu do aparatu. To niezależny format, inspirowany projektami [libcimbar i CFC](https://github.com/sz3/libcimbar) autorstwa sz3, oryginalnymi projektami Color Icon Matrix Barcode, i nie jest z nimi zgodny.

## Klatka

Każda klatka to siatka 64 × 64 komórek. Cztery kwadratowe znaczniki w rogach pozwalają aparatowi znaleźć siatkę, nawet gdy ekran jest przechylony lub widziany pod kątem. Każda pozostała komórka zawiera jeden z 16 kształtów w jednym z 4 kolorów, co daje 6 bitów na komórkę. Jedna klatka niesie 2880 bajtów.

## Korekcja błędów

Część każdej klatki to korekcja błędów Reeda-Solomona. Klatka nadal odczytuje się poprawnie, gdy niektóre komórki zostaną źle odczytane z powodu odblasków, rozmycia lub mory. Każda klatka niesie około 2100 bajtów samego pliku.

## Wiele klatek, dowolna kolejność

Plik większy niż jedna klatka jest dzielony na kilka. Każda klatka mówi, do którego pliku należy i ilu klatek plik potrzebuje, więc odbiorca wie, kiedy ma ich wystarczająco dużo.

Po klatkach samego pliku następują **klatki naprawcze**. Każda z nich jest mieszanką klatek pliku, obliczoną tak, że *dowolny* zestaw klatek tak liczny jak plik — zarówno klatek pliku, jak i naprawczych — wystarcza do jego odtworzenia. Odbiorca nie musi złapać konkretnej klatki: przegapioną klatkę zastępuje to, co przyjdzie następne.

## Kompresja i szyfrowanie

Przed podziałem CimBar kompresuje plik, jeśli zmniejsza to jego rozmiar co najmniej o 5% (zdjęcia i archiwa są zwykle już skompresowane i wysyłane są bez zmian). Następnie, jeśli podano hasło, [szyfruje](encryption.md) wynik.

## Wszystko zostaje na Twoich urządzeniach

Kodowanie i dekodowanie odbywa się w całości na Twoim telefonie lub w przeglądarce. Kod podróżuje wyłącznie jako światło, z ekranu do aparatu.

## Zgodność

Wszystkie obecne klienty CimBar (internetowy, Android, iPhone) odczytują nawzajem swoje kody. GIF-y utworzone przez najwcześniejsze wydania projektu, sprzed tego formatu, nie są odczytywane i trzeba je utworzyć ponownie.

Format jest otwarty: jego specyfikacja i cały kod źródłowy są dostępne na [GitHubie](https://github.com/mezinster/cimbar).
