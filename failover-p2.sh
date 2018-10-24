#!/bin/bash -x

# setup main firewall rules
iptables -t filter -A INPUT -i lo -j ACCEPT
iptables -t filter -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -t filter -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
#iptables -t filter -A INPUT -i eth0 -j DROP
#iptables -t filter -A FORWARD -i eth0 -p tcp -m tcp --dport 50000 -m state --state NEW -j ACCEPT

# Set defaults if not provided by environment
CHECK_DELAY=${CHECK_DELAY:-5}
CHECK_IP=${CHECK_IP:-8.8.8.8}

# Первый — 3G/LTE модем.
PRIMARY_IF=${PRIMARY_IF:-eth0.10}
PRIMARY_GW=${PRIMARY_GW:-192.168.0.1}

# по умолчанию в самом начале пробуем в модем
iptables -t nat -A POSTROUTING -o "$PRIMARY_IF" -j MASQUERADE
RULE_NUMBER=$(iptables -t nat -L --line-numbers | grep MASQUERADE | sed -rn 's/([0-9]*)MASQUERADE.*/\1/p')

# Второй — хартинги
SECONDARY_IF=${SECONDARY_IF:-eth0.20}
# узнать айпи на хартинговом интерфейсе
SECONDARY_NET=$(ip address show dev "$SECONDARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*).*$/\1/p')
SECONDARY_IP=$(ip address show dev "$SECONDARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*)\/.*$/\1/p')

# Третий — ADSL-модем Zyxel
TERTIARY_IF=${TERTIARY_IF:-eth0.30}
TERTIARY_GW=${TERTIARY_GW:-5.6.7.8}

# Compare arg with current default gateway interface for route to healthcheck IP
gateway_if() {
	[[ "$1" = "$(ip r g "$CHECK_IP" | sed -rn 's/^.*dev ([^ ]*).*$/\1/p')" ]]
}

# Cycle healthcheck continuously with specified delay
while sleep "$CHECK_DELAY"
do
	# If healthcheck succeeds from primary interface
	if ping -I "$PRIMARY_IF" -c1 "$CHECK_IP" &>/dev/null
	then
		# Are we using any of the backups?
		if (gateway_if "$SECONDARY_IF") || (gateway_if "$TERTIARY_IF")
		then # Switch to primary
			ip r d default
			ip r a default via "$PRIMARY_GW" dev "$PRIMARY_IF"
			iptables -t nat -D POSTROUTING "$RULE_NUMBER"
			iptables -t nat -A POSTROUTING -o "$PRIMARY_IF" -j MASQUERADE
			RULE_NUMBER=$(iptables -t nat -L --line-numbers | grep MASQUERADE | sed -rn 's/([0-9]*)MASQUERADE.*/\1/p')
			# TODO: share my internet
		fi
	else # гугл недоступен по основному интерфейсу
		# TODO попробовать получить dhclient eth0.10
		# Are we using the primary?
		if gateway_if "$PRIMARY_IF"
		then # Switch to backup
(nmap -sn "$SECONDARY_NET" --exclude "$SECONDARY_IP" -oG - | grep "Status: Up" | sed -rn 's/Host: ([^ ]*) \(.*/\1/p') | while read -r line
do
# в переменной у нас перебираются возможные гейтвеи. Если хоть один сработал, будем использовать его
	echo $line
	# надо проверить, есть ли в нём интернет
	echo ip r d "$SECONDARY_NET"
	echo ip r a $line dev "$SECONDARY_IF"
	if ping -c1 -I "$SECONDARY_IF" "$CHECK_IP" &>/dev/null
	then
		# works, switch to this
		echo ip r d default
		echo ip r a default via "$line" dev "$SECONDARY_IF"

		# и раздать через адсл
	fi
done

			ip r d default
# у нас неизвестен гейтвей на третьем
			ip r a default via "$SECONDARY_GW" dev "$SECONDARY_IF"
		fi
	fi
done
