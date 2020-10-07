#!/bin/sh -ex

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

create_out_dir "${OUTPUT}"
cd "${OUTPUT}"

cmd="lava-send"
if which "${cmd}"; then
    ${cmd} client-request request="finished"
fi
