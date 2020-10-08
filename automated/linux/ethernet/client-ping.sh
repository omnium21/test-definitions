#!/bin/sh -ex

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
ETH="eth0"

create_out_dir "${OUTPUT}"
cd "${OUTPUT}"

while getopts "A:c:e:t:p:v:s:Rh" o; do
  case "$o" in
    e) ETH="${OPTARG}" ;;
    h|*) usage ;;
  esac
done

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
	result=$(grep "result" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
	echo "The daemon says that pinging the client returned ${result}"
	if [ "${result}" = 0 ]; then
		echo "ping: pass"
	else
		echo "ping: fail"
	fi
else
    echo "WARNING: command ${cmd} not found. We are not running in the LAVA environment."
fi

