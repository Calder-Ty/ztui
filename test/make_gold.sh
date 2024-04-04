#!/bin/sh
# Generate the _gold_ file
INPUT="./test_events"
GOLD_EXE="./zig-out/bin/ztui-integration-tests"

tr -d "\n" < ./test_events | $GOLD_EXE 2> gold_data.txt
