#!/bin/bash

# This script runs a Speedtest and sends the results to Zabbix
# It supports optional parameters --city and --server:
#   - if --city is provided, it fetches server IDs for that city using the Speedtest.net API
#   - if --server is provided, it uses that server id directly
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
        --server) SERVER_ID="$2"; shift ;;
    esac
    shift
done

# Check prerequisites
command -v speedtest-cli >/dev/null 2>&1 || { echo "[Error] Please install speedtest-cli"; exit 1; }
command -v awk >/dev/null 2>&1 || { echo "[Error] Please install awk"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "[Error] Please install curl"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[Error] Please install jq"; exit 1; }
command -v zabbix_sender >/dev/null 2>&1 || { echo "[Error] Please install zabbix-sender"; exit 1; }

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
CMD="speedtest-cli --secure --json"

# Append --server if a valid server ID was provided
if [[ -n "$server_id" && "$server_id" =~ ^[0-9]+$ ]]; then
    CMD="$CMD --server $server_id"
fi

# Execute the speedtest
echo "Running command: $CMD" | tee -a "$LOG_FILE"
json_data=$(eval "$CMD")
echo "$json_data" | tee -a "$LOG_FILE"

# Extract values from JSON output
SRV_NAME=$(jq -r '.server.sponsor' <<< "$json_data")
DL=$(jq -r '.download' <<< "$json_data")
UP=$(jq -r '.upload' <<< "$json_data")
PING=$(jq -r '.ping' <<< "$json_data")
SRV_KM=$(jq -r '.server.d' <<< "$json_data")
SRV_CITY=$(jq -r '.server.name' <<< "$json_data")
WAN_IP=$(jq -r '.client.ip' <<< "$json_data")

# Convert and format speedtest results for readability here
DL_MBIT=$(awk "BEGIN {printf \"%.2f\", $DL / 1000000}")
UP_MBIT=$(awk "BEGIN {printf \"%.2f\", $UP / 1000000}")
PING_MS=$(awk "BEGIN {printf \"%.2f\", $PING}")

# Output formatted result
echo "ping: $PING_MS ms, down: $DL_MBIT Mbit/s, up: $UP_MBIT Mbit/s, server: $SRV_NAME" | tee -a "$LOG_FILE"

# Summarize data for Zabbix in sender format
cat <<EOF >> "$ZABBIX_DATA"
- speedtest.download $DL
- speedtest.upload $UP
- speedtest.wan.ip $WAN_IP
- speedtest.ping $PING
- speedtest.srv.name $SRV_NAME
- speedtest.srv.city $SRV_CITY
- speedtest.srv.km $SRV_KM
EOF

# Send data to Zabbix
echo "Sending Data to Zabbix"
zabbix_sender --config $CONFIG_FILE -i $ZABBIX_DATA | tee -a $LOG_FILE

# Cleanup temporary file
rm $ZABBIX_DATA
