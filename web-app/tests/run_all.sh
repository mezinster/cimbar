#!/bin/sh
# Run all automated CimBar tests. Execute from the project root:
#   sh tests/run_all.sh
set -e

echo "=== CimBar Test Suite ==="

echo ""
echo "--- Symbol round-trip ---"
node tests/test_symbols.js

echo ""
echo "--- Reed-Solomon ---"
node tests/test_rs.js

echo ""
echo "--- GIF encode/decode pipeline with length prefix ---"
node tests/test_pipeline_node.js

echo ""
echo "=== All tests passed ==="
