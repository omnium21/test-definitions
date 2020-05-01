#!/bin/sh

# shellcheck disable=SC1091
. ../../lib/sh-test-lib

OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
export RESULT_FILE

# Default ethernet interface
INTERFACE="eth0"

usage() {
    echo "Usage: $0 [-i <ethernet-interface> -w <switch-interface> -s <true|false>]" 1>&2
    exit 1
}

while getopts "s:i:w:" o; do
  case "$o" in
    s) SKIP_INSTALL="${OPTARG}" ;;
    # Ethernet interface
    i) INTERFACE="${OPTARG}" ;;
    w) SWITCH_IF="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Test run.
! check_root && error_msg "This script must be run as root"
create_out_dir "${OUTPUT}"

pkgs="net-tools"
install_deps "${pkgs}" "${SKIP_INSTALL}"

# Print all network interface status
ip addr

echo ""
echo "Current Interface"
# Print given network interface status
ip addr show "${INTERFACE}"



if_state() {
	local interface
	local if_info
	local state
	local ret

	interface=${1}
	ret=0

	if_info=$(ip addr show "${SWITCH_IF}" | grep -a2 "state DOWN" | tail -1 )

	if [ -n "${if_info}" ]; then
		state=down
	else
		state=up
		ret=1
	fi
	echo "${state}"
	return "${ret}"
}

wait_for_if_up() {
	local interface
	local state

	interface=${1}

	retries=0
	max_retries=100
	while [ $(if_state ${interface}) = "down" ] && [ "$((retries++))" -lt "${max_retries}" ]; do
		sleep 0.1
	done
	if_state ${interface} && return -1
	return 0
}

if_up() {
	local interface
	interface=$1

	if if_state ${interface} ; then
		echo "Bringing interface ${interface} up"
		ifconfig "${interface}" up
		wait_for_if_up ${interface} 2>&1 > /dev/null
		#exit_on_fail "ethernet-${interface}-state-UP"
	fi
	ip addr show "${interface}"

	# DELME
	if_state ${interface} || echo interface $interface is up
	if_state ${interface} && echo interface $interface is down
	if_state ${interface}
	ret=$?
	if [ "${ret}" -eq "0" ]; then
		echo interface $interface is down
	else
		echo interface $interface is up
	fi

	ret=$?
	if if_state ${interface} ; then
		echo interface $interface is down
	else
		echo interface $interface is up
	fi
	# finsihed playing
}

ping_test() {
	local interface
	interface=$1
	# Get IP address of a given interface
	IP_ADDR=$(ip addr show "${interface}" | grep -a2 "state UP" | tail -1 | awk '{print $2}' | cut -f1 -d'/')

	echo IP_ADDR=$IP_ADDR
	[ -n "${IP_ADDR}" ]
	exit_on_fail "ethernet-ping-state-UP" "ethernet-ping-route"

	# Get default Route IP address of a given interface
	ROUTE_ADDR=$(ip route list  | grep default | awk '{print $3}' | head -1)

	# Run the test
	run_test_case "ping -c 5 ${ROUTE_ADDR}" "ethernet-ping-route"
}
#ping_test "${INTERFACE}"

if [ -n "${SWITCH_IF}" ]; then
	echo "${INTERFACE} is a port on switch ${SWITCH_IF}"
	ip addr show "${SWITCH_IF}"
	if_up "${SWITCH_IF}"
fi
