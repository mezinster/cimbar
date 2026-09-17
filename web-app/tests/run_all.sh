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

echo ""; echo "--- Reed-Solomon ---"
node tests/test_rs.js

echo ""; echo "--- Goldens ---"
node tests/test_goldens.js

echo ""; echo "--- End-to-end pipeline ---"
node tests/test_pipeline_node.js

echo ""; echo "--- Deploy healthcheck ---"
node tests/test_healthcheck.js

echo ""
echo "=== All tests passed ==="
