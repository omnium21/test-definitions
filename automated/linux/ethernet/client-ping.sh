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
#ipaddr=$(lava-echo-ipv4 "${ETH}" | tr -d '\0')
#if [ -z "${ipaddr}" ]; then
#	lava-test-raise "${ETH} not found"
#fi

get_ipaddr() {
	local ipaddr
	local interface

	interface="${1}"
	ipaddr=$(ip addr show "${interface}" | grep -a2 "state " | grep "inet "| tail -1 | awk '{print $2}' | cut -f1 -d'/')
	echo "${ipaddr}"
}

echo "################################################################################"
ip addr show
echo "################################################################################"

ipaddr=$(get_ipaddr $ETH)

if [ "${ipaddr}" != "" ]; then
	echo -n "Our date is " ; date --rfc-3339=ns
	datestr=$(date +%s)
	lava-send client-request request="ping" ipaddr="${ipaddr}" datestr="${datestr}"

	# wait for a response
	lava-wait client-ping-done

	# report pass/fail depending on whether we expected ping to succeed or not
	pingresult=$(grep "pingresult" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
	echo "The daemon says that pinging the client returned ${pingresult}"
	echo "We are expecting ping to ${EXPECTED_RESULT}"
	if [ "${pingresult}" = "${EXPECTED_RESULT}" ]; then
		actual_result="pass"
	else
		actual_result="fail"
	fi
	echo "client-ping-request ${actual_result}" | tee -a "${RESULT_FILE}"
else
	echo "ERROR: ipaddr is invalid"
fi
