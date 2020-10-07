#!/bin/sh -ex

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/iperf3.txt"
# Time in seconds to transmit for
TIME="10"
# Number of parallel client streams to run
THREADS="1"
# Specify iperf3 version for CentOS.
VERSION="3.1.4"
# By default, the client sends to the server,
# Setting REVERSE="-R" means the server sends to the client
REVERSE=""
# CPU affinity is blank by default, meaning no affinity.
# CPU numbers are zero based, eg AFFINITY="-A 0" for the first CPU
AFFINITY=""

usage() {
    echo "Usage: $0 [-t time] [-p number] [-v version] [-A cpu affinity] [-R] [-s true|false]" 1>&2
    exit 1
}

while getopts "A:c:e:t:p:v:s:Rh" o; do
  case "$o" in
    A) AFFINITY="-A ${OPTARG}" ;;
    t) TIME="${OPTARG}" ;;
    p) THREADS="${OPTARG}" ;;
    R) REVERSE="-R" ;;
    v) VERSION="${OPTARG}" ;;
    s) SKIP_INSTALL="${OPTARG}" ;;
    h|*) usage ;;
  esac
done

create_out_dir "${OUTPUT}"
cd "${OUTPUT}"

SERVER="$(cat /tmp/server.ipaddr)"
if [ -z "${SERVER}" ]; then
	echo "ERROR: no server specified"
	exit 1
else
	echo "Using SERVER=${SERVER}"
fi
# We are running in client mode
# Run iperf3 test with unbuffered output mode.
stdbuf -o0 iperf3 -c "${SERVER}" -t "${TIME}" -P "${THREADS}" "${REVERSE}" "${AFFINITY}" 2>&1 \
	| tee "${LOGFILE}"

# Parse logfile.
if [ "${THREADS}" -eq 1 ]; then
	grep -E "(sender|receiver)" "${LOGFILE}" \
		| awk '{printf("iperf3_%s pass %s %s\n", $NF,$7,$8)}' \
		| tee -a "${RESULT_FILE}"
elif [ "${THREADS}" -gt 1 ]; then
	grep -E "[SUM].*(sender|receiver)" "${LOGFILE}" \
		| awk '{printf("iperf3_%s pass %s %s\n", $NF,$6,$7)}' \
		| tee -a "${RESULT_FILE}"
fi
