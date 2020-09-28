#!/bin/sh

# shellcheck disable=SC1091
. ../../lib/sh-test-lib

OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
export RESULT_FILE

# Default ethernet interface
INTERFACE="eth0"

usage() {
    echo "Usage: $0 [-i <ethernet-interface> -w <switch-interface> -I <static-ip-addr> -s <true|false>]" 1>&2
    exit 1
}

while getopts "s:i:I:w:" o; do
  case "$o" in
    s) SKIP_INSTALL="${OPTARG}" ;;
    # Ethernet interface
    i) INTERFACE="${OPTARG}" ;;
    I) IPADDR="${OPTARG}" ;;
    g) GATEWAY="${OPTARG}" ;;
    w) SWITCH_IF="${OPTARG}" ;;
    *) usage ;;
  esac
done

# Test run.
! check_root && error_msg "This script must be run as root"
create_out_dir "${OUTPUT}"

pkgs="net-tools"
install_deps "${pkgs}" "${SKIP_INSTALL}"


if [ -z "${INTERFACE}" ]; then
	# TODO - this should check if the interface exists
	echo "ERROR: ethernet interface not specified"
	exit 1
fi

if [ -z "${IPADDR}" ]; then
	echo "ERROR: static IP address not specified"
	exit 1
fi

if [ -z "${GATEWAY}" ]; then
	GATEWAY=$(echo "${IPADDR}" | awk -F. '{print $1"."$2"."$3".254"}')
	echo "WARNING: default gateway not specified. Setting to ${GATEWAY}"
fi

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
	echo "Current ipaddr=${ipaddr}/${netmask}"
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



assign_ipaddr(){
	local interface
	local ipaddr
	local netmask
	local static_ipaddr

	interface="${1}"
	static_ipaddr="${2}"

	if [ -z "${static_ipaddr}" ]; then
		test_string="udhcp"
	else
		test_string="static-ip"
	fi

	show_ip "${interface}"
	ipaddr=$(get_ipaddr "${interface}")
	netmask=$(get_netmask "${interface}")
	if [ ! -z "${ipaddr}" ]; then
		echo "ip address already set... removing"
		ip addr del "${ipaddr}"/"${netmask}" dev "${interface}"

		echo "Check IP address removed"
		show_ip "${interface}"
		ipaddr=$(get_ipaddr "${interface}")
		[ -z "${ipaddr}" ]
		exit_on_fail "ethernet-${interface}-${test_string}-remove-ipaddr"
	fi

	if [ -z "${static_ipaddr}" ]; then
		echo "Running udhcpc on ${interface}..."
		udhcpc -i "${interface}"
		# TODO - wait for IP addr assignment?
	else
		echo "Setting a static IP address to ${static_ipaddr}..."
		ifconfig "${interface}" "${static_ipaddr}"
		echo "Setting default gateway to ${GATEWAY}"
		route add default gw "${GATEWAY}"
	fi

	show_ip "${interface}"
	ipaddr=$(get_ipaddr "${interface}")
	if [ -z "${ipaddr}" ]; then
		exit_on_fail "ethernet-${interface}-${test_string}-assign-ipaddr"
	fi
	ping_test "${INTERFACE}" "ethernet-${interface}-${test_string}-assign-ipaddr-ping"
}


q_hostping(){
	local test_string
	local expect_failure
	local interface

	interface="${1}"
	test_string="${2}"
	expect_failure="${3}"

	if [ -z "${expect_failure}" ]; then
		query="succeeds"
	else
		query="times out"
	fi

	read -p "Check ping ${IPADDR} from your host machine ${query}? (Y/n) " y
	test "${y}" != "n" -a "${y}" != "N"
	exit_on_fail "ethernet-${interface}-ping-from-host-${test_string}"
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
echo "Run udhcpc test on ${INTERFACE}"
echo "################################################################################"
assign_ipaddr "${INTERFACE}"
echo "################################################################################"
gap

echo "################################################################################"
echo "Run fixed IP test on ${INTERFACE}"
echo "################################################################################"
assign_ipaddr "${INTERFACE}" "${IPADDR}"
echo "################################################################################"
gap





echo "################################################################################"
echo "Check ping from the host works"
echo "################################################################################"
q_hostping "${INTERFACE}" TB2
echo "################################################################################"
gap


echo "################################################################################"
echo "Disconnect the ethernet cable"
echo "################################################################################"
q_hostping "${INTERFACE}" TB3 fail
echo "################################################################################"
gap


echo "################################################################################"
echo "Reconnect the ethernet cable"
echo "################################################################################"
q_hostping "${INTERFACE}" TB4
echo "################################################################################"
gap


#xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# TODO - ethtool
# ethtool -s ${eth} speed 100 duplex full autoneg off # TB1
# ethtool -s ${eth} speed 100 duplex half autoneg off # TB5
# ethtool -s ${eth} speed 100 duplex full autoneg off # TB6
# ethtool -s ${eth} autoneg on # TB7
#xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
test_ethtool(){
	local test_string
	local interface
	local speed
	local duplex
	local autoneg

	interface="${1}"
	test_string="${2}"
	speed="${3}"
	duplex="${4}"
	autoneg="${5}"

	echo "Requested Settingsi:"
	echo "Link speed: ${speed}"
	echo "Duplex:     ${duplex}"
	echo "Auto-neg:   ${autoneg}"

	# TODO - set ethtool settings
	if [ "${autoneg}" = "on" ]; then
		echo "Setting autoneg on"
		ethtool -s "${interface} autoneg on"
	else
		echo "Setting manual negotiation"
		ethtool -s "${interface}" speed "${speed}" duplex "${duplex}" autoneg "${autoneg}"
	fi
	sleep 5

	# TODO - dump actual settings - i.e parse ethtool output 
	ethtool "${interface}" \
		| grep -e "Advertised auto-negotiation" -e "Speed" -e "Duplex" \
		| sed -e "s/Advertised auto-negotiation/Auto-neg/g" -e "s/Speed: /Speed:    /g" -e "s/Duplex: /Duplex:   /g"

	# TODO - check actual settings match final settings

	q_hostping "${INTERFACE}" "${test_string}"
}
echo "################################################################################"
echo "Link speed and duplex settings"
echo "################################################################################"
test_ethtool "${INTERFACE}" "ethtool-TB1" 100 full off
test_ethtool "${INTERFACE}" "ethtool-TB5" 100 half off
test_ethtool "${INTERFACE}" "ethtool-TB6" 100 full off
test_ethtool "${INTERFACE}" "ethtool-TB7" any any  on
echo "################################################################################"
gap


#systemctl start NetworkManager.service
#systemctl daemon-reload
