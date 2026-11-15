# Pobierz aplikację

## Aplikacja internetowa { #web-app }

Otwórz **[nfcarchiver.com/cimbar](https://nfcarchiver.com/cimbar/)** w przeglądarce. Działa na telefonach i komputerach i nie wymaga instalacji ani konta.

Skanowanie aparatem wymaga, aby strona była otwarta przez `https://` (tak jak pod tym adresem). Kopia otwarta z pliku na komputerze nadal może wysyłać oraz dekodować GIF lub zdjęcia, ale przeglądarki nie uruchomią jej skanera aparatu.

## Android { #android }

Aplikacja nazywa się **Skaner CimBar**. Wymaga Androida 7.0 lub nowszego. Prosi o jedno uprawnienie, aparat, i nie ma dostępu do internetu.

- **[F-Droid](https://f-droid.org/packages/com.nfcarchiver.cimbar/)**: budowana przez F-Droid z opublikowanego kodu źródłowego i aktualizowana automatycznie przez aplikację F-Droid.
- **[Wydania na GitHubie](https://github.com/mezinster/cimbar/releases)**: plik APK dołączony do każdego wydania.

!!! note "Wersji z F-Droid i GitHuba nie można mieszać"
    F-Droid podpisuje swoje wersje własnym kluczem, więc APK z GitHuba nie może zaktualizować instalacji z F-Droid i odwrotnie. Aby się przełączyć, zapisz zdekodowane pliki, odinstaluj aplikację i zainstaluj ją z drugiego źródła.

Wersje do 0.10.1 miały inny identyfikator aplikacji (`com.cimbar.scanner`). Nowsze wersje instalują się obok starej aplikacji zamiast ją zastępować. Zapisz potrzebne pliki ze starej aplikacji, a następnie ją odinstaluj.

## iPhone i iPad { #iphone }

**CimBar** na iPhone'a i iPada (iOS 15 lub nowszy) jest testowany w Apple **TestFlight** i nie ma go jeszcze w App Store. Do tego czasu [aplikacja internetowa](#web-app) działa w Safari na iPhonie i iPadzie, łącznie ze skanowaniem aparatem.
