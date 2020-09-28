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

if_state() {
	local interface
	local if_info
	local state

	interface="${1}"
	state=0 # zero is down, 1 is up

	if_info=$(ip addr show "${interface}" | grep -a2 "state DOWN" | tail -1 )

	if [ -z "${if_info}" ]; then
		state=1
	fi

	echo "if_state: interface ${interface} is in state ${state}"
	return "${state}"
}

wait_for_if_up() {
	local interface
	local state

	interface="${1}"

	retries=0
	max_retries=100
	while if_state "${interface}" && [ "$((retries++))" -lt "${max_retries}" ]; do
		sleep 0.1
	done
	if_state "${interface}" && return -1
	return 0
}

if_up() {
	local interface
	interface="${1}"

	if if_state "${interface}" ; then
		echo "Bringing interface ${interface} up"
		ifconfig "${interface}" up
		wait_for_if_up "${interface}" 2>&1 > /dev/null
		exit_on_fail "ethernet-${interface}-state-up"
	fi
}


if_down() {
	local interface
	local result

	interface="${1}"
	result=fail

	echo "Bringing interface ${interface} down"
	ifconfig "${interface}" down
	if_state "${interface}" || exit_on_fail "ethernet-${interface}-state-down"
}

################################################################################
# A test function checking different ways to call if_state
################################################################################
delete_this_function() { # TODO
	local interface
	interface="${1}"

	if_state "${interface}" || echo "interface ${interface} is up"
	if_state "${interface}" && echo "interface ${interface} is down"
	if_state "${interface}"
	ret="$?"
	if [ "${ret}" -eq "0" ]; then
		echo "interface ${interface} is down"
	else
		echo "interface ${interface} is up"
	fi

	ret=$?
	if if_state "${interface}" ; then
		echo "interface ${interface} is down"
	else
		echo "interface ${interface} is up"
	fi
}
################################################################################

get_ipaddr() {
	local ipaddr
	local interface

	interface="${1}"
	ipaddr=$(ip addr show "${interface}" | grep -a2 "state " | grep "inet "| tail -1 | awk '{print $2}' | cut -f1 -d'/')
	echo "${ipaddr}"
}

get_netmask() {
	local netmask
	local interface

	interface="${1}"
	netmask=$(ip addr show "${interface}" | grep -a2 "state " | grep "inet " | tail -1 | awk '{print $2}' | cut -f2 -d'/')
	echo "${netmask}"
}

show_ip() {
	local interface
	local ipaddr
	local netmask

	interface="${1}"

	ipaddr=$(get_ipaddr "${interface}")
	netmask=$(get_netmask "${interface}")
	echo Current ipaddr=$ipaddr netmask=$mask
}

ping_test() {
	local interface
	local test_string

	interface="${1}"
	test_string="${2}"

	# Get IP address of a given interface
	show_ip "${interface}"
	ipaddr=$(get_ipaddr "${interface}")
	[ -n "${ipaddr}" ]
	exit_on_fail "ethernet-${interface}-ping-get-ipaddr"

	# Get default Route IP address of a given interface
	ROUTE_ADDR=$(ip route list  | grep default | awk '{print $3}' | head -1)

	# Run the test
	run_test_case "ping -I ${interface} -c 5 ${ROUTE_ADDR}" "${test_string}"
}



do_udhcpc(){
	local interface
	local ipaddr
	local netmask

	interface="${1}"

echo "xxx"
	show_ip "${interface}"
echo "xxx"
	ipaddr=$(get_ipaddr "${interface}")
echo "xxx"
	netmask=$(get_netmask "${interface}")
echo "xxx"
	if [ ! -z "${ipaddr}" ]; then
echo "xxx"
		echo "ip address already set... removing"
		ip addr del "${ipaddr}"/"${netmask}" dev "${interface}"
echo "xxx"

		echo "Check IP address removed"
		show_ip "${interface}"
echo "xxx"
		ipaddr=$(get_ipaddr "${interface}")
		[ -z "${ipaddr}" ]
		exit_on_fail "ethernet-${interface}-udhcp-remove-ipaddr"
	fi

echo "xxx"
	echo "Running udhcpc on ${interface}..."
	udhcpc -i "${interface}"

	# TODO - wait for IP addr assignment

	show_ip "${interface}"
	ipaddr=$(get_ipaddr "${interface}")
	if [ -z "${ipaddr}" ]; then
		exit_on_fail "ethernet-${interface}-udhcp-assign-ipaddr"
	fi
	ping_test "${INTERFACE}" "ethernet-udhcp-ping"
}




gap() {
	echo ""
	echo ""
	echo ""
	echo ""
	echo ""
	echo ""
	echo ""
	echo ""
	echo ""
	echo ""
}

# Disable networkmanager
# TODO - save state and restore saved state at the end
#systemctl stop NetworkManager.service
#systemctl daemon-reload




# Print all network interface status
gap
echo "################################################################################"
ip addr
echo "################################################################################"
gap

if [ -n "${SWITCH_IF}" ]; then
	echo "${INTERFACE} is a port on switch ${SWITCH_IF}"
	ip addr show "${SWITCH_IF}"
	if_up "${SWITCH_IF}"
	ip addr show "${SWITCH_IF}"
fi

#delete_this_function ${SWITCH_IF}


gap
echo "################################################################################"
echo "Current state of interface ${INTERFACE}"
# Print given network interface status
ip addr show "${INTERFACE}"
echo "################################################################################"
gap

# Take all interfaces down
echo "################################################################################"
iflist=( eth0 eth1 eth2 lan0 lan1 lan2 )
for intf in ${iflist[@]}; do
	if_down "${intf}"
done
sleep 2
echo "################################################################################"
gap


echo "################################################################################"
echo "Bring ${INTERFACE} up"
echo "################################################################################"
if_up "${INTERFACE}"
echo "################################################################################"
gap




echo "################################################################################"
echo "Run udhcpc on ${INTERFACE}"
echo "################################################################################"
do_udhcpc "${INTERFACE}"
echo "################################################################################"
gap





#systemctl start NetworkManager.service
#systemctl daemon-reload
