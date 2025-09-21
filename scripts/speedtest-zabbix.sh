#!/bin/bash
#
# Author: Sebastian Plocek
# GitHub: https://github.com/sebastian13/zabbix-template-speedtest
# License: MIT
#
# This script runs a Speedtest and sends the results to Zabbix
# It supports optional parameters --city and --server-id:
#   - if --city is provided, it fetches server IDs for that city using the Speedtest.net API
#   - if --server-id is provided, it uses that server id directly
#

set -e

ZABBIX_DATA=/tmp/speedtest-zabbix-$(date +"%Y%m%d-%H%M%S").tmp
LOG_FILE=/var/log/zabbix/speedtest.log
CITY=""
SERVER_ID=""

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --city) CITY="$2"; shift ;;
        --server-id) SERVER_ID="$2"; shift ;;
    esac
    shift
done

# Check prerequisites
command -v speedtest >/dev/null 2>&1 || { echo "[Error] Please install speedtest"; exit 1; }
command -v awk >/dev/null 2>&1 || { echo "[Error] Please install awk"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "[Error] Please install curl"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[Error] Please install jq"; exit 1; }
command -v zabbix_sender >/dev/null 2>&1 || { echo "[Error] Please install zabbix-sender"; exit 1; }

# Check if official Speedtest CLI by Ookla is installed
if speedtest --version 2>&1 | grep -q "Speedtest by Ookla"; then
    echo "[Info] Official Speedtest CLI is installed"
else
    echo "[Error] Official Speedtest CLI not found"
    exit 1
fi

# Set Zabbix config file path
CONFIG_FILE=""
[ -f /etc/zabbix/zabbix_agent2.conf ] && CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
[ -f /etc/zabbix/zabbix_agentd.conf ] && CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
[ -n "$CONFIG_FILE" ] || { echo "[Error] Cannot find Zabbix config file"; exit 1; }

# Create the logfile if it doesn't exist
[ -f $LOG_FILE ] || touch $LOG_FILE
chown zabbix:zabbix $LOG_FILE
chmod 640 $LOG_FILE
echo | tee -a $LOG_FILE
echo "$(date +%F-%T)" | tee -a $LOG_FILE

# Determine the server ID to use
if [ -n "$SERVER_ID" ]; then
    # Use the provided server ID
    server_id="$SERVER_ID"
elif [ -n "$CITY" ]; then
    # Query the Speedtest.net API for servers in the specified city
    # Requires 'curl' and 'jq' to be installed
    server_id=$(curl -s "https://www.speedtest.net/api/js/servers?engine=js&https_functional=true&search=$CITY" \
        | jq -r '.[] | select(.name | test("'$CITY'" ; "i")) | .id' | shuf -n1)
fi

# Build the speedtest command
CMD="speedtest --accept-license --accept-gdpr --format=json"

# Append --server-id if a valid server ID was provided
if [[ -n "$server_id" && $server_id =~ ^[0-9]+$ ]]; then
    CMD="$CMD --server-id=$server_id"
fi

# Execute the speedtest
echo "Running command: $CMD" | tee -a "$LOG_FILE"
json_data=$(eval "$CMD")
echo "$json_data" | tee -a "$LOG_FILE"

# Extract measurement timestamp (ISO 8601), convert to epoch seconds
# If timestamp is missing or invalid, use current time
TS_ISO=$(jq -r '.timestamp? // empty' <<< "$json_data")
TS_EPOCH=$(date -u -d "$TS_ISO" +%s 2>/dev/null || date -u +%s)

# Extract server info
SRV_ID=$(jq -r '.server.id?         // empty' <<< "$json_data")
SRV_NAME=$(jq -r '.server.name?     // empty' <<< "$json_data")
SRV_CITY=$(jq -r '.server.location? // empty' <<< "$json_data")
SRV_CTRY=$(jq -r '.server.country?  // empty' <<< "$json_data")

# Extract ISP info
WAN_ISP=$(jq -r '.isp?                 // empty' <<< "$json_data")
WAN_IP=$(jq -r '.interface.externalIp? // empty' <<< "$json_data")

# Extract performance metrics
# Bandwidth in bytes per second, latency in milliseconds
DL_BYTES_S=$(jq -r '(.download.bandwidth? // 0) | floor'    <<< "$json_data")
UP_BYTES_S=$(jq -r '(.upload.bandwidth?   // 0) | floor'    <<< "$json_data")
PING_MS=$(jq -r '(.ping.latency?          // 0) | tonumber' <<< "$json_data")
PLOSS=$(jq -r '(.packetLoss?              // 0) | tonumber' <<< "$json_data")

# Convert to human-readable format for logging
DL_MBIT=$(awk "BEGIN {printf \"%.2f\", $DL_BYTES_S * 8 / 1000000}")
UP_MBIT=$(awk "BEGIN {printf \"%.2f\", $UP_BYTES_S * 8 / 1000000}")
PING=$(awk "BEGIN {printf \"%.2f\", $PING_MS}")

# Log results
echo "ping: ${PING} ms, down: ${DL_MBIT} Mbit/s, up: ${UP_MBIT} Mbit/s, server: ${SRV_NAME}" | tee -a "$LOG_FILE"

# Prepare data for Zabbix: Convert bandwidth to bits per second (bps)
DL_BPS=$(( DL_BYTES_S * 8 ))
UP_BPS=$(( UP_BYTES_S * 8 ))

# Create Zabbix data file
# <key> <timestamp> <value>
cat <<EOF >> "$ZABBIX_DATA"
- speedtest.srv.id $TS_EPOCH $SRV_ID
- speedtest.srv.name $TS_EPOCH $SRV_NAME
- speedtest.srv.city $TS_EPOCH $SRV_CITY
- speedtest.srv.country $TS_EPOCH $SRV_CTRY
- speedtest.wan.isp $TS_EPOCH $WAN_ISP
- speedtest.wan.ip $TS_EPOCH $WAN_IP
- speedtest.download $TS_EPOCH $DL_BPS
- speedtest.upload $TS_EPOCH $UP_BPS
- speedtest.ping $TS_EPOCH $PING_MS
- speedtest.packetloss $TS_EPOCH $PLOSS
EOF

# Send data to Zabbix
echo "Sending Data to Zabbix"
zabbix_sender --config $CONFIG_FILE -T -i $ZABBIX_DATA | tee -a $LOG_FILE

# Cleanup temporary file
rm $ZABBIX_DATA
