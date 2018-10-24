#!/bin/bash -x

# setup main firewall rules
#iptables -t filter -A INPUT -i lo -j ACCEPT
#iptables -t filter -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
#iptables -t filter -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
#iptables -t filter -A INPUT -i eth0 -j DROP
#iptables -t filter -A FORWARD -i eth0 -p tcp -m tcp --dport 50000 -m state --state NEW -j ACCEPT

# Set defaults if not provided by environment
CHECK_DELAY=${CHECK_DELAY:-5}
CHECK_IP=${CHECK_IP:-8.8.8.8}

# Первый — 3G/LTE модем.
PRIMARY_IF=${PRIMARY_IF:-br0.10}
# проверить есть ли там вообще адрес
PRIMARY_IP=$(ip address show dev "$PRIMARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*)\/.*$/\1/p')
printf "ip is '$PRIMARY_IP'\n"

PRIMARY_GW=${PRIMARY_GW:-192.168.0.1}

RULE_NUMBER=$(iptables -t nat -L --line-numbers | grep -m1 MASQUERADE | sed -rn 's/([0-9]*).*MASQUERADE.*/\1/p')
printf "rule is '$RULE_NUMBER'\n"
if [ ! -v ${RULE_NUMBER:-} ]
then
	printf "Masquerade already on. Please disable it and rerun because the script switches it.\n"
	exit 1
else
	printf "sfdsdfsd \n"
fi

printf "next\n"
