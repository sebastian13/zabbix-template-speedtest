# Zabbix Template: Speedtest

Monitoring internet bandwidth using speedtest and zabbix. The script uses `zabbix_sender` to send the values to a Zabbix Server. The interval is set via cron. By default, it uses the server selected by Ookla's speedtest cli. In addition, you can provide a City or a specific Sever-ID.

## Screenshots
### Gathered Data
![Latest Data](screenshots/data.png)

### Graphs
![Triggers](screenshots/graph-up-down.png)


## Requirements
- Zabbix server (tested with Zabbix 7.0 LTS)
- Speedtest CLI (by Ookla)
- curl, jq, awk, zabbix_sender
- Debian 12+

## Script Options
- `--city <City>`: Use a Speedtest server located in the specified city.
- `--server-id <ID>`: Use a specific Speedtest server by ID.

## How to Use

1. Install [Speedtest® CLI](https://www.speedtest.net/apps/cli)

	```bash
	## If migrating from prior bintray install instructions please first...
	# sudo rm /etc/apt/sources.list.d/speedtest.list
	# sudo apt-get update
	# sudo apt-get remove speedtest
	## Other non-official binaries will conflict with Speedtest CLI
	# Example how to remove using apt-get
	# sudo apt-get remove speedtest-cli
	sudo apt-get install curl
	curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
	sudo apt-get install speedtest
	```

1. Download `speedtest-zabbix.sh`

	```bash
	mkdir -p /etc/zabbix/scripts
	cd /etc/zabbix/scripts
	curl -LO https://raw.githubusercontent.com/sebastian13/zabbix-template-speedtest/master/scripts/speedtest-zabbix.sh
	chmod +x speedtest-zabbix.sh
	```

1. Create Cron

	```bash
	curl -Lo /etc/cron.d/speedtest-zabbix https://raw.githubusercontent.com/sebastian13/zabbix-template-speedtest/master/speedtest-zabbix.cron
	service cron reload
	```

1. Import the Template `zbx_template_speedtest.xml` to Zabbix and assign in to a server.

### Additional Resources

- [Manpage: Zabbix Sender](https://www.zabbix.com/documentation/current/manpages/zabbix_sender)
- [List of Speedtest Server](https://gist.github.com/ofou/654efe67e173a6bff5c64ba26c09d058)
- [Query the Speedtest API](https://stackoverflow.com/a/77814522/8940679)

Inspired by

- https://git.cdp.li/polcape/zabbix/tree/master/zabbix-speedtest
- https://github.com/sk3pp3r/speedtest2zabbix
