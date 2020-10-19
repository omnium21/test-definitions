#!/bin/sh -x

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
ETH="eth0"
EXPECTED_RESULT="pass"
IPERF3_SERVER_RUNNING="no"
CMD="usage"

usage() {
    echo "Usage: $0 [-c command] [-e server ethernet device] [-t time] [-p number] [-v version] [-A cpu affinity] [-R] [-r expected ping result] [-s true|false] -w <switch-interface>" 1>&2
    exit 1
}

while getopts "A:a:c:d:e:l:t:p:v:s:r:Rh" o; do
  case "$o" in
    A) AFFINITY="-A ${OPTARG}" ;;
    a) AUTONEG="${OPTARG}" ;;
    c) CMD="${OPTARG}" ;;
    d) DUPLEX="${OPTARG}" ;;
    e) ETH="${OPTARG}" ;;
    l) LINKSPEED="${OPTARG}" ;;
    t) TIME="${OPTARG}" ;;
    p) THREADS="${OPTARG}" ;;
    r) EXPECTED_RESULT="${OPTARG}" ;;
    R) REVERSE="-R" ;;
    v) VERSION="${OPTARG}" ;;
    w) SWITCH_IF="${OPTARG}" ;;
    s) SKIP_INSTALL="${OPTARG}" ;;
    h|*) usage ;;
  esac
done

create_out_dir "${OUTPUT}"
cd "${OUTPUT}"

if [ "${SKIP_INSTALL}" = "true" ] || [ "${SKIP_INSTALL}" = "True" ]; then
    info_msg "iperf3 installation skipped"
else
    dist_name
    # shellcheck disable=SC2154
    case "${dist}" in
        debian|ubuntu|fedora)
            install_deps "iperf3"
            ;;
        centos)
            install_deps "wget gcc make"
            wget https://github.com/esnet/iperf/archive/"${VERSION}".tar.gz
            tar xf "${VERSION}".tar.gz
            cd iperf-"${VERSION}"
            ./configure
            make
            make install
            ;;
    esac
fi

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

dump_msg_cache(){
	# TODO -delete this debug
	echo "################################################################################"
	echo "/tmp/lava_multi_node_cache.txt"
	echo "################################################################################"
	cat /tmp/lava_multi_node_cache.txt || true
	echo "################################################################################"
}


wait_for_msg(){
	local message="${1}"
	local msgseq="${2}"

	while [ true ]; do
		# Wait for the daemon to respond
		lava-wait "${message}"

		dump_msg_cache

		# report pass/fail depending on whether we expected ping to succeed or not
		rx_msgseq=$(grep "msgseq" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')

		if [ "${rx_msgseq}" -lt "${msgseq}" ]; then
			echo "WARNING: Ignoring duplicate message (${rx_msgseq} < ${msgseq})"
			rm -f /tmp/lava_multi_node_cache.txt
			continue
		elif [ "${rx_msgseq}" -gt "${msgseq}" ]; then
			echo "ERROR: We missed the reply to our message (rx_msgseq=${rx_msgseq} > msgseq=${msgseq})"
			# TODO - report lava test fail
			exit 1
		else
			echo "ACK: we found the droid we were looking for..."
			break
		fi
	done
}

################################################################################
################################################################################
################################################################################
################################################################################
################################################################################
################################################################################
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
		check_return "ethernet-${interface}-state-up ${result}"
	fi
}


if_down() {
	local interface
	local result

	interface="${1}"
	result=fail

	echo "Bringing interface ${interface} down"
	ifconfig "${interface}" down
	if_state "${interface}"
	check_return "ethernet-${interface}-state-down"
}

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
	check_return "ethernet-${interface}-ping-get-ipaddr"

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
		check_return "ethernet-${interface}-${test_string}-remove-ipaddr"
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
		check_return "ethernet-${interface}-${test_string}-assign-ipaddr"
	fi
	ping_test "${INTERFACE}" "ethernet-${interface}-${test_string}-assign-ipaddr-ping"
}

dump_link_settings(){
	local interface
	local speed
	local duplex
	local autoneg

	interface="${1}"
	speed=$(get_link_speed "${interface}")
	duplex=$(get_link_duplex "${interface}")
	autoneg=$(get_link_autoneg "${interface}")

	echo "Current settings for interface ${interface}"
	echo "  Auto-neg: ${autoneg}"
	echo "  Speed:    ${speed}"
	echo "  Duplex:   ${duplex}"
}


get_link_speed(){
	local interface
	local speed

	interface="${1}"
	speed=$(ethtool "${interface}" \
		| grep -e "Speed" \
		| sed  -e "s/Speed: //g" \
		| sed  -e 's/\t//g' -e 's/ //g' -e 's/Mb\/s//g')
	echo "${speed}"
}
get_link_duplex(){
	local interface
	local duplex

	interface="${1}"
	duplex=$(ethtool "${interface}" \
		| grep -e "Duplex" \
		| sed  -e "s/Duplex: //g" \
		| sed  -e 's/\t//g' -e 's/ //g' \
		| awk '{print tolower($0)}')
	echo "${duplex}"
}
get_link_autoneg(){
	local interface
	local autoneg

	interface="${1}"
	autoneg=$(ethtool "${interface}" \
		| grep -e "Advertised auto-negotiation" \
		| sed  -e "s/Advertised auto-negotiation://g" \
		| sed  -e 's/\t//g' -e 's/ //g' \
		| awk '{print tolower($0)}')

	case "${autoneg}" in
		no|off) autoneg=off ;;
		yes|on) autoneg=on ;;
	esac
	echo "${autoneg}"
}

check_link_settings(){
	local interface
	local requested_speed
	local requested_duplex
	local requested_autoneg
	local actual_speed
	local actual_duplex
	local actual_autoneg
	local test_string

	interface="${1}"
	requested_speed="${2}"
	requested_duplex="${3}"
	requested_autoneg="${4}"
	test_string="${5}"

	dump_link_settings "${interface}"

	actual_speed=$(get_link_speed "${interface}")
	actual_duplex=$(get_link_duplex "${interface}")
	actual_autoneg=$(get_link_autoneg "${interface}")

	[ "${actual_autoneg}" = "${requested_autoneg}" ]
	check_return "ethernet-${interface}-${test_string}-check-link-autoneg"

	if [ "${requested_autoneg}" = "off" ]; then
		[ "${actual_speed}" = "${requested_speed}" ]
		check_return "ethernet-${interface}-${test_string}-check-link-speed"
		[ "${actual_duplex}" = "${requested_duplex}" ]
		check_return "ethernet-${interface}-${test_string}-check-link-duplex"
	fi
}


test_ethtool(){
	local interface
	local speed
	local duplex
	local autoneg

	interface="${1}"
	speed="${2}"
	duplex="${3}"
	autoneg="${4}"

	dump_link_settings "${interface}"

	echo "Requested Settings:"
	echo "  Auto-neg: ${autoneg}"
	echo "  Speed:    ${speed}"
	echo "  Duplex:   ${duplex}"

	if [ "${autoneg}" = "on" ]; then
		echo "Setting ${interface} to auto-negotiate"
		ethtool -s "${interface}" autoneg on
	else
		echo "Setting ${interface} to manual negotiation for ${speed}Mbps at ${duplex} duplex"
		ethtool -s "${interface}" speed "${speed}" duplex "${duplex}" autoneg "${autoneg}"
	fi
	echo ""
	sleep 10
	echo ""
	check_link_settings "${interface}" "${speed}" "${duplex}" "${autoneg}" "ethtool"
}

################################################################################
################################################################################
################################################################################
################################################################################
################################################################################


# Take all interfaces down
echo "################################################################################"

# TODO: iflist should be auto-generated or able to deal with other boards
iflist=( eth0 eth1 lan0 lan1 lan2 )
[ "${BOARD}" = "soca9" ] && iflist=(${iflist[@]} eth2)

for intf in ${iflist[@]}; do
	if_down "${intf}"
done
sleep 2
echo "################################################################################"

# Bring up the interface we want to test
echo "################################################################################"
echo "Bring ${INTERFACE} up"
echo "################################################################################"
if [ -n "${SWITCH_IF}" ]; then
	echo "${INTERFACE} is a port on switch ${SWITCH_IF}"
	ip addr show "${SWITCH_IF}"
	if_up "${SWITCH_IF}"
	ip addr show "${SWITCH_IF}"
fi
if_up "${INTERFACE}"
echo "################################################################################"


echo "################################################################################"
ip addr show
echo "################################################################################"

# Try to get the stashed IP address first, otherwise, try to work it out
ipaddrstash="/tmp/ipaddr-${ETH}.txt"
if [ -e "${ipaddrstash}" ]; then
	ipaddr="$(cat ${ipaddrstash})"
else
	ipaddr=$(get_ipaddr $ETH)
	echo "${ipaddr}" > "${ipaddrstash}"
fi
echo "My IP address is ${ipaddr}"

dump_msg_cache
rm -f /tmp/lava_multi_node_cache.txt

if [ "${ipaddr}" = "" ]; then
	echo "ERROR: ipaddr is invalid"
	actual_result="fail"
else
	case "$CMD" in
		"daemon")
			previous_msgseq=""
			while [ true ]; do
				# Wait for the client to make a request
				lava-wait client-request

				# read the client request
				request=$(grep "request" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
				msgseq=$(grep "msgseq" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')

				if [ "${msgseq}" = "${previous_msgseq}" ]; then
					echo "Ignoring duplicate message ${msgseq}"
					continue
				fi

				# log this message so we don't handle it again
				previous_msgseq="${msgseq}"

				echo "client-request \"${request}\" with stamp ${msgseq} received"

				# perform the client request
				case "${request}" in
					"finished")
						echo "Client has signalled we are finished. Exiting."
						exit 0
						;;
					"request-server-address")
						dump_msg_cache
						lava-send server-address ipaddr="${ipaddr}" msgseq="${msgseq}"
						;;
					"iperf3-server")
						dump_msg_cache
						if [ "${IPERF3_SERVER_RUNNING}" != "pass" ]; then
							################################################################################
							# Start the server
							# report pass/fail as a test result
							# send the server's IP address to the client(s)
							################################################################################
							echo "Client has asked us to start the iperf3 server"
							cmd="iperf3 -s -D"
							${cmd}
							if pgrep -f "${cmd}" > /dev/null; then
								IPERF3_SERVER_RUNNING="pass"
							else
								IPERF3_SERVER_RUNNING="fail"
							fi
							echo "iperf3-server-running ${IPERF3_SERVER_RUNNING}" | tee -a "${RESULT_FILE}"
						else
							echo "iperf3 server is already running"
						fi

						if [ "${IPERF3_SERVER_RUNNING}" = "pass" ]; then
							lava-send iperf3-server-ready ipaddr="${ipaddr}" msgseq="${msgseq}"
						fi
						;;
					"ping-request")
						dump_msg_cache

						ipaddr=$(grep "ipaddr" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
						msgseq=$(grep "msgseq" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
						echo "Client has asked us to ping address ${ipaddr} with msgseq=${msgseq}"
						pingresult=pass
						ping -c 5 "${ipaddr}" || pingresult="fail"
						lava-send client-ping-done pingresult="${pingresult}" msgseq="${msgseq}"
						;;
					"ssh-request")
						dump_msg_cache
						their_filename=$(grep "filename" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
						their_ipaddr=$(grep "ipaddr" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
						msgseq=$(grep "msgseq" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
						echo "Client has asked us to ssh in and md5sum ${their_filename}"
						our_sum=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes root@"${their_ipaddr}" md5sum "${their_filename}" | tail -1 | cut -d " " -f 1 | tee -a "${their_filename}".md5)
						echo "Our md5sum is ${our_sum}"
						lava-send ssh-result md5sum="${our_sum}" msgseq="${msgseq}"
						;;
					"md5sum-request")
						dump_msg_cache
						filename=$(grep "filename" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
						msgseq=$(grep "msgseq" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
						echo "Client has asked us to md5sum ${filename}"
						our_sum=$(md5sum "${filename}" | tail -1 | cut -d " " -f 1 | tee -a "${filename}".md5)
						echo "Our md5sum is ${our_sum}"
						lava-send md5sum-result md5sum="${our_sum}" msgseq="${msgseq}"
						;;
					"scp-request")
						dump_msg_cache
						their_filename=$(grep "filename" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
						their_ipaddr=$(grep "ipaddr" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
						msgseq=$(grep "msgseq" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
						echo "Client has asked us to send them ${filename}"

						# first create the file
						our_filename=$(mktemp ~/largefile.XXXXX)
						dd if=/dev/urandom of="${our_filename}" bs=1M count=1024
						our_sum=$(md5sum "${our_filename}" | tail -1 | cut -d " " -f 1 | tee -a "${our_filename}".md5)
						scp -o StrictHostKeyChecking=no -o BatchMode=yes "${our_filename}" root@"${their_ipaddr}":"${their_filename}"
						echo "Our md5sum is ${our_sum}"
						lava-send scp-result md5sum="${our_sum}" msgseq="${msgseq}"
						rm -f "${our_filename}"
						;;
					*) echo "Unknown client request: ${request}" ;;
				esac
				rm -f /tmp/lava_multi_node_cache.txt
			done
			;;
		"ping-request")
			tx_msgseq="$(date +%s)"
			lava-send client-request request="ping-request" ipaddr="${ipaddr}" msgseq="${tx_msgseq}"
			wait_for_msg client-ping-done "${tx_msgseq}"

			pingresult=$(grep "pingresult" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
			echo "The daemon says that pinging the client returned ${pingresult}"
			echo "We are expecting ping to ${EXPECTED_RESULT}"

			if [ "${pingresult}" = "${EXPECTED_RESULT}" ]; then
				result="pass"
			else
				result="fail"
			fi
			echo "client-ping-request ${result}" | tee -a "${RESULT_FILE}"
			;;
		"request-server-address"|"iperf3-server")
			# The mechanism for requesting the servier address, or for requesting
			# the the daemon starts the iperf3 daemon are the same:
			# - we send the request
			# - the server does what it needs to
			# - the server replies with its IP address
			tx_msgseq="$(date +%s)"
			lava-send client-request request="${CMD}" msgseq="${tx_msgseq}"
			case "${CMD}" in
				"iperf3-server") wait_msg=iperf3-server-ready ;;
				*) wait_msg=server-address ;;
			esac
			wait_for_msg "${wait_msg}" "${tx_msgseq}"

			server=$(grep "ipaddr" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')

			if [ -z "${server}" ]; then
				echo "ERROR: no server specified"
				result="fail"
			else
				SERVER="${server}"
				echo "${CMD}: ${SERVER}"
				echo "${SERVER}" > /tmp/server.ipaddr
				result="pass"
			fi
			echo "${CMD}" | tee -a "${RESULT_FILE}"
			;;
		"iperf3-client")
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
			;;
		"ssh-host-to-target")
			# SSH into the target and md5sum a file. Send the md5sum back to the target for verification
			filename=$(mktemp /tmp/magic.XXXXX)
			dd if=/dev/urandom of="${filename}" bs=1024 count=1
			our_sum=$(md5sum "${filename}" | tail -1 | cut -d " " -f 1 | tee -a "${filename}".md5)

			tx_msgseq="$(date +%s)"
			lava-send client-request request="ssh-request" ipaddr="${ipaddr}" filename="${filename}" msgseq="${tx_msgseq}"
			wait_for_msg ssh-result "${tx_msgseq}"
			their_sum=$(grep "md5sum" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')

			if [ "${their_sum}" = "${our_sum}" ]; then
				result=pass
			else
				result=fail
			fi
			echo "ssh-host-to-target ${result}" | tee -a "${RESULT_FILE}"
			rm -f "${filename}"
			;;
		"scp-host-to-target")
			# SCP a file from the host (server) to the target (client)
			filename=$(mktemp ~/largefile.XXXXX)
			tx_msgseq="$(date +%s)"
			lava-send client-request request="scp-request" ipaddr="${ipaddr}" filename="${filename}" msgseq="${tx_msgseq}"
			wait_for_msg scp-result "${tx_msgseq}"
			their_sum=$(grep "md5sum" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
			our_sum=$(md5sum "${filename}" | tail -1 | cut -d " " -f 1 | tee -a "${filename}".md5)

			if [ "${their_sum}" = "${our_sum}" ]; then
				result=pass
			else
				result=fail
			fi
			echo "scp-host-to-target ${result}" | tee -a "${RESULT_FILE}"
			rm -f "${filename}"
			;;
		"scp-target-to-host")
			# SCP a file from the target (client, DUT) to the host (server)
			# TODO - this relies on running iperf3 tests first
			SERVER="$(cat /tmp/server.ipaddr)"
			if [ -z "${SERVER}" ]; then
				echo "ERROR: no server specified"
				exit 1
			else
				echo "Using SERVER=${SERVER}"
			fi

			filename=$(mktemp ~/largefile.XXXXX)
			dd if=/dev/urandom of="${filename}" bs=1M count=1024
			scp -o StrictHostKeyChecking=no -o BatchMode=yes "${filename}" root@"${SERVER}":"${filename}"
			tx_msgseq="$(date +%s)"
			lava-send client-request request="md5sum-request" filename="${filename}" msgseq="${tx_msgseq}"
			our_sum=$(md5sum "${filename}" | tail -1 | cut -d " " -f 1 | tee -a "${filename}".md5)
			wait_for_msg md5sum-result "${tx_msgseq}"
			their_sum=$(grep "md5sum" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')

			if [ "${their_sum}" = "${our_sum}" ]; then
				result=pass
			else
				result=fail
			fi
			echo "scp-target-to-host ${result}" | tee -a "${RESULT_FILE}"

			# Send an empty file back to the host to overwrite the large file, effectively deleting the file, so we don't eat their disk space
			smallfilename=$(mktemp /tmp/smallfile.XXXXX)
			scp -o StrictHostKeyChecking=no -o BatchMode=yes "${smallfilename}" root@"${SERVER}":"${filename}"
			rm -f "${filename}" "${smallfilename}"
			;;
		"ethtool")
			test_ethtool "${ETH}" "${LINKSPEED}" "${DUPLEX}" "${AUTONEG}"
			;;
		"finished")
			lava-send client-request request="finished"
			;;
		*)
			usage
			;;
	esac
fi
echo "$0 ${result}" | tee -a "${RESULT_FILE}"
