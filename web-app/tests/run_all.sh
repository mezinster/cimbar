#!/bin/sh
# Run all automated CimBar web tests. Execute from web-app/:
#   sh tests/run_all.sh
set -e

echo "=== CimBar Web Test Suite (v2) ==="

echo ""; echo "--- Tile rules and generator ---"
node tests/test_tiles.js

echo ""; echo "--- Format spec, header, packing ---"
node tests/test_format.js

echo ""; echo "--- Frame render/decode, RS framing, assembler ---"
node tests/test_frame.js

echo ""; echo "--- Rateless coding ---"
node tests/test_rateless.js

echo ""; echo "--- Reed-Solomon ---"
node tests/test_rs.js

echo ""; echo "--- Compression ---"
node tests/test_compress.js

echo ""; echo "--- Goldens ---"
node tests/test_goldens.js

echo ""; echo "--- End-to-end pipeline ---"
node tests/test_pipeline_node.js

echo ""; echo "--- UI strings (five languages) ---"
node tests/test_i18n.js

echo ""; echo "--- Browser script load (shared global scope) ---"
node tests/test_browser_load.js

echo ""; echo "--- Photo decode geometry (RgbBuffer, LumaPlane, Homography) ---"
node tests/test_photo_geometry.js

echo ""; echo "--- Finder locator (camera path) ---"
node tests/test_finder_locator.js

echo ""; echo "--- Cell decode (white point, sampler, classifier) ---"
node tests/test_cell_decode.js

echo ""; echo "--- Drift solver (flood-fill sub-pixel alignment) ---"
node tests/test_drift.js

echo ""; echo "--- Deploy healthcheck ---"
node tests/test_healthcheck.js

echo ""; echo "--- Icons, manifest and deploy staging ---"
node tests/test_web_icons.js

echo ""
echo "=== All tests passed ==="
