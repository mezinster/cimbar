# How it works

CimBar uses **CimBar-XL**, a colour barcode format made for sending files from a screen to a camera. It is an independent format, inspired by [libcimbar and CFC](https://github.com/sz3/libcimbar) by sz3, the original Color Icon Matrix Barcode projects, and is not compatible with them.

## A frame

Each frame is a 64 × 64 grid of cells. Four square finder patterns in the corners let the camera find the grid, even when the screen is tilted or seen at an angle. Every other cell holds one of 16 shapes in one of 4 colours, which is 6 bits per cell. One frame carries 2,880 bytes.

## Error correction

Part of every frame is Reed-Solomon error correction. A frame still reads correctly when some of its cells are misread because of glare, blur or a moiré pattern. Each frame carries about 2,100 bytes of the file itself.

## Many frames, any order

A file larger than one frame is split across several. Each frame says which file it belongs to and how many frames the file needs, so the receiver knows when it has enough.

After the file's own frames come **repair frames**. Each is a mix of the file's frames, computed so that *any* set of frames as large as the file, file frames and repair frames alike, is enough to rebuild it. The receiver doesn't have to catch a particular frame: a frame it missed is replaced by whatever comes next.

## Compression and encryption

Before splitting, CimBar compresses the file if that makes it at least 5% smaller (photos and archives usually are already compressed, and are sent as they are). Then, if you gave a passphrase, it [encrypts](encryption.md) the result.

## Everything stays on your devices

Encoding and decoding run entirely on your phone or in your browser. The code travels only as light, from a screen to a camera.

## Compatibility

All current CimBar clients (web, Android, iPhone) read each other's codes. GIFs made by the project's earliest releases, before this format, are not readable and must be made again.

The format is open: its specification and all the source code are on [GitHub](https://github.com/mezinster/cimbar).
