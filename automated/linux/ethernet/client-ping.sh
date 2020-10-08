#!/bin/sh -ex

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
ETH="eth0"
EXPECTED_RESULT="pass"

create_out_dir "${OUTPUT}"
cd "${OUTPUT}"

while getopts "A:c:e:t:p:v:s:r:Rh" o; do
  case "$o" in
    A) AFFINITY="-A ${OPTARG}" ;;
    c) SERVER="${OPTARG}" ;;
    e) ETH="${OPTARG}" ;;
    t) TIME="${OPTARG}" ;;
    p) THREADS="${OPTARG}" ;;
    r) EXPECTED_RESULT="${OPTARG}" ;;
    R) REVERSE="-R" ;;
    v) VERSION="${OPTARG}" ;;
    s) SKIP_INSTALL="${OPTARG}" ;;
    h|*) usage ;;
  esac
done

command_exists(){
	local cmd

	cmd="$1"

	if ! which "${cmd}"; then
		echo "ERROR: ${cmd} not available"
		exit 1
	fi
}
command_exists "lava-echo-ipv4"
command_exists "lava-send"
command_exists "lava-wait"
command_exists "ping"

# Run local iperf3 server as a daemon when testing localhost.
ipaddr=$(lava-echo-ipv4 "${ETH}" | tr -d '\0')
if [ -z "${ipaddr}" ]; then
	lava-test-raise "${ETH} not found"
fi
lava-send client-request request="ping" ipaddr="${ipaddr}"

# wait for a response
lava-wait client-ping-done

# report pass/fail depending on whether we expected ping to succeed or not
result=$(grep "result" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
echo "The daemon says that pinging the client returned ${result}"
echo "We are expecting ping to ${EXPECTED_RESULT}"
if [ "${result}" = "0" ] && [ "${EXPECTED_RESULT}" == "pass" ];
	actual_result="pass"
elif [ "${result}" != "0" ] && [ "${EXPECTED_RESULT}" == "fail" ];
	actual_result="pass"
else
	actual_result="fail"
fi
echo "client-ping-request ${actual_result}" | tee -a "${RESULT_FILE}"
