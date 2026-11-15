# Szyfrowanie

Gdy wysyłasz z hasłem, plik lub wiadomość jest szyfrowana na Twoim urządzeniu, zanim stanie się kodem. Każdy może zeskanować kod, ale otworzyć jego zawartość może tylko ktoś, kto zna hasło.

- **Algorytm:** AES-256-GCM. Klucz jest wyprowadzany z hasła za pomocą PBKDF2-SHA256 (150 000 iteracji) i losowej soli dla każdego pliku.
- **Hasło nigdy nie opuszcza Twojego urządzenia.** Nie jest przechowywane, rejestrowane ani nigdzie wysyłane.
- **Odbiorca nie musi wiedzieć o tym z góry.** CimBar sam rozpoznaje zaszyfrowany plik i prosi o hasło, gdy dotrą wszystkie klatki.
- **Błędne hasło nic nie kosztuje.** Klatki są już zebrane: wpisz hasło ponownie, bez ponownego skanowania.

!!! warning "Utraconego hasła nie można odzyskać"
    Nikt, łącznie z nami, nie może otworzyć zaszyfrowanego pliku bez jego hasła.

Przekaż odbiorcy hasło inną drogą niż sam kod, na przykład osobiście.
