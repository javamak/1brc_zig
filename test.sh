#!/bin/bash
set -e

# Build the project
zig build -Doptimize=ReleaseFast

# Run the executable with the test file and capture output
./zig-out/bin/1brc_zig test-in.txt > output.txt

# Compare with expected output
diff output.txt test-out.txt && echo "Test passed!" || echo "Test failed!"