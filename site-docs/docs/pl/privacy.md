# Polityka prywatności

*Wiążący prawnie jest tekst angielski: [Privacy policy](../../privacy/).*

**CimBar** · Ostatnia aktualizacja: 15 listopada 2026

Niniejsza polityka obejmuje wszystkie trzy klienty CimBar: **aplikację internetową** pod adresem [nfcarchiver.com/cimbar](https://nfcarchiver.com/cimbar/), aplikację na **Androida** Skaner CimBar (`com.nfcarchiver.cimbar`) oraz aplikację na **iPhone'a** i iPada CimBar (`com.nfcarchiver.cimbar`). Obejmuje również tę witrynę z dokumentacją.

## W skrócie

CimBar niczego nie zbiera. Kodowanie, dekodowanie, kompresja i szyfrowanie odbywają się w całości na Twoim urządzeniu: w przeglądarce lub w aplikacji na telefonie. Pliki i wiadomości, które wysyłasz lub odbierasz, oraz Twoje hasła nigdy nie są wysyłane na żaden serwer. Kod podróżuje wyłącznie jako światło, z ekranu do aparatu.

## Zbieranie danych

**Nie zbieramy żadnych danych.** W szczególności:

- Żadnych danych osobowych.
- Żadnej analityki użytkowania ani śledzenia.
- Żadnych raportów o awariach.
- Żadnych plików cookie, identyfikatorów reklamowych ani innych identyfikatorów.
- Żadnych danych o lokalizacji.
- Żadnych plików ani wiadomości, które wysyłasz lub odbierasz, i żadnych haseł.

## Aparat

Aparat jest używany wyłącznie do skanowania kodów CimBar (skanowanie na żywo i zdjęcia). Klatki z aparatu i zdjęcia są dekodowane w pamięci, a następnie odrzucane; żadne nie są przechowywane ani nigdzie wysyłane.

Jedynym wyjątkiem jest opcja dla programistów. Gdy na karcie **Informacje** w aplikacji włączony jest **Tryb debugowania**, przycisk przechwytywania zapisuje klatkę, dla której go dotkniesz, w prywatnej pamięci aplikacji. Dzieje się to tylko wtedy, gdy go dotkniesz, a plik pozostaje na Twoim urządzeniu.

## Pliki i wiadomości

- **Wysyłanie:** wybrany plik lub wpisany tekst jest odczytywany na Twoim urządzeniu i tam zamieniany w kod. Udostępniony GIF trafia tylko tam, gdzie go wyślesz.
- **Odbieranie:** importowany GIF lub zdjęcie jest odczytywane przez systemowy selektor plików, selektor zdjęć lub arkusz udostępniania; aplikacja odczytuje tylko to, co wybierzesz.
- **Odebrane pliki** są przechowywane w prywatnej pamięci aplikacji (w aplikacji) i opuszczają ją tylko wtedy, gdy wybierzesz **Otwórz**, **Zapisz na urządzeniu** lub **Udostępnij**. Odinstalowanie aplikacji je usuwa. Aplikacja internetowa niczego nie przechowuje: odebrany plik istnieje na stronie, dopóki go nie zapiszesz lub jej nie opuścisz.

## Szyfrowanie

Gdy wysyłasz z hasłem, zawartość jest szyfrowana na Twoim urządzeniu algorytmem AES-256-GCM; klucz jest wyprowadzany z hasła za pomocą PBKDF2-SHA256 (150 000 iteracji, losowa sól dla każdego pliku). Hasło nigdy nie jest przechowywane, rejestrowane ani przesyłane. Jeśli zostanie utracone, nikt, łącznie z nami, nie może odzyskać zawartości. Zobacz [Szyfrowanie](encryption.md).

## Aplikacja internetowa

- Działa w całości w przeglądarce. Kodowanie i dekodowanie nie wykonują żadnych żądań sieciowych.
- Jedyne, co przechowuje, to język interfejsu, pod kluczem `cimbar.lang` w pamięci lokalnej przeglądarki, aby zapamiętać wybór języka. Nie ustawia plików cookie. Wyczyszczenie danych witryny go usuwa.
- **Czcionki:** strona wczytuje kroje pisma z Google Fonts (`fonts.googleapis.com`, `fonts.gstatic.com`). Jak w przypadku każdego zasobu internetowego, żądanie przeglądarki ujawnia Google Twój adres IP i przeglądarkę; zobacz [FAQ dotyczące prywatności Google Fonts](https://developers.google.com/fonts/faq/privacy). Nie jest wysyłana żadna zawartość plików ani inne dane.
- **Hosting:** strona jest statyczną witryną serwowaną z Amazon S3 przez Amazon CloudFront. Amazon prowadzi standardowe logi dostępu (adres IP, czas, żądany adres, przeglądarka) zgodnie z własnymi zasadami. Sama aplikacja internetowa niczego nie rejestruje.

## Aplikacja na Androida

Każde uprawnienie, które ma aplikacja, i do czego służy:

- **Aparat** (`CAMERA`): do skanowania kodów CimBar. To jedyne uprawnienie. Aplikacja **nie ma uprawnienia do internetu** i nie może łączyć się z żadnym serwerem.

Wybór języka i przełącznik trybu debugowania są przechowywane w lokalnych preferencjach aplikacji. Linki w sekcji **Informacje** (polityka prywatności, licencja, kod źródłowy) otwierają się w przeglądarce; sama aplikacja nie wykonuje żadnych żądań sieciowych.

## Aplikacja na iPhone'a i iPada

O co aplikacja może prosić i do czego to służy:

- **Aparat** (`NSCameraUsageDescription`): do skanowania kodów CimBar.
- **Zdjęcia** (`NSPhotoLibraryUsageDescription`): do otwierania wybranych przez Ciebie zdjęć, aby zdekodować znajdujący się na nich kod. Aplikacja widzi tylko zdjęcia, które wybierzesz.
- **Mikrofon** (`NSMicrophoneUsageDescription`): aplikacja **nigdy** nie nagrywa dźwięku i nigdy nie prosi o dostęp do mikrofonu. Opis istnieje tylko dlatego, że używany przez nią komponent aparatu zawiera także funkcje audio, a Apple wymaga tego opisu od każdej aplikacji, która je zawiera.

Gdy udostępniasz plik do CimBar z innej aplikacji, rozszerzenie udostępniania przekazuje go aplikacji przez obszar pamięci, z którego mogą korzystać tylko one dwie (App Group). Aplikacja nie wykonuje żadnych żądań sieciowych. Jej manifest prywatności deklaruje brak śledzenia i brak zbieranych danych. Wybór języka i przełącznik trybu debugowania są przechowywane na urządzeniu.

## Ta witryna

Ta witryna z dokumentacją nie ustawia plików cookie, nie uruchamia analityki i nie wczytuje czcionek ani skryptów stron trzecich. Jej wyszukiwarka działa lokalnie w przeglądarce. Jest hostowana tak samo jak aplikacja internetowa (Amazon S3 i CloudFront, ze standardowymi logami dostępu), a jej kopia jest udostępniana na GitHub Pages, które prowadzi własne logi zgodnie z [oświadczeniem o prywatności GitHuba](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

## Usługi stron trzecich

Aplikacje nie korzystają z żadnych usług stron trzecich: bez analityki, bez przechowywania w chmurze, bez zdalnych serwerów, bez integracji z mediami społecznościowymi. Aplikacja internetowa korzysta tylko z Google Fonts i swojego hostingu, jak opisano powyżej.

## Prywatność dzieci

CimBar nie zbiera danych od nikogo, w tym od dzieci.

## Zmiany niniejszej polityki

Jeśli ta polityka się zmieni, nowy tekst zostanie opublikowany na tej stronie, a powyższa data zaktualizowana. Jej historia znajduje się w [repozytorium źródłowym](https://github.com/mezinster/cimbar).

## Otwarte źródło

Aplikacja internetowa i aplikacje mobilne mają otwarty kod źródłowy (licencja MIT): [github.com/mezinster/cimbar](https://github.com/mezinster/cimbar).

## Kontakt

Pytania dotyczące niniejszej polityki: [support@nfcarchiver.com](mailto:support@nfcarchiver.com).
