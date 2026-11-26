# Photo fixtures

## `rotated.heic`

A 64×32 HEIC image, left half red `#ff0000`, right half blue `#0000ff`, stored
with EXIF orientation 6 (rotate 90° clockwise to display), which libheif's
encoder writes as an `irot` transform. Decoded with the transform applied it
is **32×64 with red on top**; `web-app/tests/test_image_decode.js` decodes it
through the vendored `web-app/vendor/libheif/` and checks exactly that.

The file has no Exif, XMP or other metadata item: the orientation is passed to
the encoder directly, not through an Exif block.

Made with pillow-heif 1.9.0 (Pillow 13.0.0, Python 3.12) in a throwaway venv
(`python3 -m venv venv && venv/bin/pip install pillow-heif`), running
`venv/bin/python make_rotated.py rotated.heic` with this script:

```python
import sys
from PIL import Image
from pillow_heif.constants import HeifCompressionFormat
from pillow_heif.misc import CtxEncode

img = Image.new("RGB", (64, 32), (0, 0, 255))
img.paste((255, 0, 0), (0, 0, 32, 32))
ctx = CtxEncode(HeifCompressionFormat.HEVC, quality=90)
ctx.add_image(img.size, img.mode, img.tobytes(), image_orientation=6, primary=True)
ctx.save(sys.argv[1])
```

The x265 encoder's output may differ by version; any file it produces that
decodes to the shape and colours above serves.
