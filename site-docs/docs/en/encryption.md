# Encryption

When you send with a passphrase, the file or message is encrypted on your device before it becomes a code. Anyone can scan the code, but only someone with the passphrase can open what it carries.

- **Algorithm:** AES-256-GCM. The key is derived from your passphrase with PBKDF2-SHA256 (150,000 iterations) and a random salt for every file.
- **The passphrase never leaves your device.** It is not stored, not logged and not sent anywhere.
- **The receiver doesn't need to know in advance.** CimBar recognises an encrypted file by itself and asks for the passphrase once every frame is in.
- **A wrong passphrase costs nothing.** The frames are already collected: enter the passphrase again, with no re-scanning.

!!! warning "A lost passphrase can't be recovered"
    Nobody, including us, can open an encrypted file without its passphrase.

Tell the receiver the passphrase some other way than the code itself, for example in person.
