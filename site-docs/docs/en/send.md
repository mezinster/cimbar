# Send a file or text

Sending turns a file or a message into an animated code: a sequence of frames, each a grid of coloured shapes. Show it full screen and let the other device scan it, or share it as a GIF.

## In the app (Android, iPhone)

1. Open the **Send** tab.
2. Choose **Text** and type or paste your message, or choose **File** and pick a file.
3. Optional: enter a **Passphrase**. The receiver will need it to open what you send. See [Encryption](encryption.md).
4. Optional: change the **Frame delay**: 100, 200 or 400 ms per frame. Slower is easier for the receiving camera; faster finishes sooner.
5. Tap **Present on screen** to show the code full screen, or **Share GIF** to send it as an animated GIF through another app.

The line under the input shows the size and at most how many frames the code will have.

While presenting, the app keeps the screen on and turns the brightness up. Both go back to normal when you leave.

## In the web app

1. Open **Send**.
2. Choose **File** (pick or drop a file) or **Text** (type your message).
3. Optional: **Add a passphrase**.
4. Optional: under **Advanced**, choose the **Frame speed**.
5. Tap **Create code**. On the **Ready to send** screen, choose **Present full screen**, **Share GIF** (on phones that support sharing) or **Download**.

## Keep it playing

A presented code first shows every frame of the file once, then keeps showing *repair frames* without end. The receiver needs as many frames as the file has, and any of them will do. A frame it missed is made up for by whichever frame comes next, so there is no need to wait for the loop to come round again. Just keep the code on screen until the receiver says it is done.

A GIF carries the file's frames plus about a quarter more repair frames, so a receiver can miss a few frames on each pass.

## How big can it be?

Each frame carries about 2 KB. CimBar compresses what you send whenever that makes it smaller, so text usually needs fewer frames than its size suggests.

- Small files (up to about 80 KB) are the quickest: a few dozen frames.
- **Present** handles up to 4096 frames.
- **Share GIF** in the app is limited to 500 frames.

Large files work, but take a while to scan. Pick a slower frame speed for codes of more than about 100 frames.
