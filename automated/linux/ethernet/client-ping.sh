#!/bin/sh -ex

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/iperf.txt"
# If SERVER is blank, we are the server, otherwise
# If we are the client, we set SERVER to the ipaddr of the server
SERVER=""
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
ETH="eth0"

usage() {
    echo "Usage: $0 [-c server] [-e server ethernet device] [-t time] [-p number] [-v version] [-A cpu affinity] [-R] [-s true|false]" 1>&2
    exit 1
}

while getopts "A:c:e:t:p:v:s:Rh" o; do
  case "$o" in
    A) AFFINITY="-A ${OPTARG}" ;;
    c) SERVER="${OPTARG}" ;;
    e) ETH="${OPTARG}" ;;
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

# Run local iperf3 server as a daemon when testing localhost.
cmd="lava-echo-ipv4"
if which "${cmd}"; then
    ipaddr=$(${cmd} "${ETH}" | tr -d '\0')
    if [ -z "${ipaddr}" ]; then
        lava-test-raise "${ETH} not found"
    fi
	cmd="lava-send"
	if which "${cmd}"; then
		${cmd} client-request request="ping" ipaddr="${ipaddr}"
	fi

	# TODO - wait for a response
	cmd="lava-wait"
	if which "${cmd}"; then
		${cmd} client-ping-done
	fi

	# TODO - report pass/fail depending on whether we expected ping to succeed or not
else
    echo "WARNING: command ${cmd} not found. We are not running in the LAVA environment."
fi
