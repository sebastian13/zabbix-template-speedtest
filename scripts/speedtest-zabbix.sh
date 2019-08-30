#!/bin/bash
set -e

CACHE_FILE=/tmp/speedtest.tmp
ZABBIX_DATA=/tmp/speedtest-zabbix.tmp
LOG_FILE=/var/log/zabbix/speedtest.log

# Create logfile
touch $LOG_FILE
chown zabbix:zabbix $LOG_FILE
chmod 640 $LOG_FILE
echo | tee -a $LOG_FILE
echo "$(date +%F-%T)" | tee -a $LOG_FILE

# Randomly choose one of the 10 closest servers
ID=$(/usr/bin/speedtest-cli --list | head -n 11 | tail -n +2 | cut -f 1 -d ")" | shuf -n1)

# Gather data
echo "Running Speedtest"
/usr/bin/speedtest-cli --server $ID --csv > $CACHE_FILE \
	| tee -a $LOG_FILE

# Extract fields
output=$(cat $CACHE_FILE)
    WAN_IP=$(echo "$output" | cut -f10 -d ',')
    PING=$(echo "$output" | cut -f6 -d ',')
    SRV_NAME=$(echo "$output" | cut -f2 -d ',')
    SRV_CITY=$(echo "$output" | cut -f3 -d ',')
    SRV_KM=$(echo "$output" | cut -f5 -d ',' | cut -b1-5)
    DL=$(echo "$output" | cut -f7 -d ',')
    UP=$(echo "$output" | cut -f8 -d ',')

# Print some results
echo "ping: $PING, down: $DL, up: $UP, server: $SRV_NAME" | tee -a $LOG_FILE

# Summarize Data for Zabbix
 echo "-" speedtest.download $DL >> $ZABBIX_DATA 
 echo "-" speedtest.upload $UP >> $ZABBIX_DATA 
 echo "-" speedtest.wan.ip $WAN_IP >> $ZABBIX_DATA 
 echo "-" speedtest.ping $PING >> $ZABBIX_DATA
 echo "-" speedtest.srv.name $SRV_NAME >> $ZABBIX_DATA
 echo "-" speedtest.srv.city $SRV_CITY >> $ZABBIX_DATA
 echo "-" speedtest.srv.km $SRV_KM >> $ZABBIX_DATA

# Send data to Zabbix
echo "Sending Data to Zabbix"
/usr/bin/zabbix_sender --config /etc/zabbix/zabbix_agentd.conf -i $ZABBIX_DATA \
	| tee -a $LOG_FILE

# Clean data
rm $CACHE_FILE $ZABBIX_DATA
