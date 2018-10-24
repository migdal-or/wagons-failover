#!/bin/bash -x

# setup main firewall rules
#iptables -t filter -A INPUT -i lo -j ACCEPT
#iptables -t filter -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
#iptables -t filter -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
#iptables -t filter -A INPUT -i eth0 -j DROP
#iptables -t filter -A FORWARD -i eth0 -p tcp -m tcp --dport 50000 -m state --state NEW -j ACCEPT

# не включён ли уже маскарад? если включён, то похоже что наш скрипт уже гоняли. тогда нафиг пожалуйста.
RULE_NUMBER=$(iptables -t nat -L --line-numbers | grep -m1 MASQUERADE | sed -rn 's/([0-9]*).*MASQUERADE.*/\1/p')
if [ ! -v ${RULE_NUMBER:-} ]
then
  printf "Masquerade is already on. Please disable it and rerun because the script switches it.\n"
#  exit 1
  iptables -t nat -D POSTROUTING $RULE_NUMBER
fi

# Set defaults if not provided by environment
CHECK_DELAY=${CHECK_DELAY:-5}
CHECK_IP=${CHECK_IP:-8.8.8.8}

# Первый — 3G/LTE модем.
PRIMARY_IF=${PRIMARY_IF:-br0.10}
# проверять есть ли там вообще адрес
PRIMARY_GW=${PRIMARY_GW:-192.168.0.1}
iptables -t nat -A POSTROUTING -o "$PRIMARY_IF" -j MASQUERADE

# Второй — хартинги
SECONDARY_IF=${SECONDARY_IF:-br0.20}
# узнать айпи на хартинговом интерфейсе
SECONDARY_NET=$(ip address show dev "$SECONDARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*).*$/\1/p')
SECONDARY_IP=$(ip address show dev "$SECONDARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*)\/.*$/\1/p')

# Третий — ADSL-модем Zyxel
TERTIARY_IF=${TERTIARY_IF:-br0.30}
# узнать айпи на adsl интерфейсе
TERTIARY_NET=$(ip address show dev "$TERTIARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*).*$/\1/p')
TERTIARY_IP=$(ip address show dev "$TERTIARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*)\/.*$/\1/p')

# Compare arg with current default gateway interface for route to healthcheck IP
gateway_if() {
  [[ "$1" = "$(ip r g "$CHECK_IP" | sed -rn 's/^.*dev ([^ ]*).*$/\1/p')" ]]
}

search_harting() {
  read
  (nmap -sn "$SECONDARY_NET" --exclude "$SECONDARY_IP" -oG - | grep "Status: Up" | sed -rn 's/Host: ([^ ]*) \(.*/\1/p') | while read -r line
  do
    read
    # в переменной line у нас перебираются возможные гейтвеи.
    # Если хоть один сработал, будем использовать его
    echo $line
    # надо проверить, есть ли в нём интернет
    ip r d default
    ip r a default via $line dev "$SECONDARY_IF"
    if ping -c1 -I "$SECONDARY_IF" "$CHECK_IP" &>/dev/null
    then
      # works, switch to this
      echo "nameserver $line" > /etc/resolv.conf 
      RULE_NUMBER=$(iptables -t nat -L --line-numbers | grep -m1 MASQUERADE | sed -rn 's/([0-9]*).*MASQUERADE.*/\1/p')
      iptables -t nat -D POSTROUTING $RULE_NUMBER
      iptables -t nat -A POSTROUTING -o "$SECONDARY_IF" -j MASQUERADE
    fi
  done
}

read
# Cycle healthcheck continuously with specified delay
while sleep "$CHECK_DELAY"
# TODO проверять br0.10 только если там есть адрес
# если адреса нету, значит модем выключен или сдох
# однако модем может в любой момент включиться и поднять адрес, что приведёт к съезду всей таблицы
# обработать это

do
  PRIMARY_IP=$(ip address show dev "$PRIMARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*)\/.*$/\1/p')
  echo 0
  # If healthcheck succeeds from primary interface
  if ping -I "$PRIMARY_IF" -c1 "$CHECK_IP" &>/dev/null
  then
    echo 1
    # Are we using any of the backups?
    if (gateway_if "$SECONDARY_IF") || (gateway_if "$TERTIARY_IF")
    then # Switch to primary
      ip r d default
      ip r a default via "$PRIMARY_GW" dev "$PRIMARY_IF"
      RULE_NUMBER=$(iptables -t nat -L --line-numbers | grep -m1 MASQUERADE | sed -rn 's/([0-9]*).*MASQUERADE.*/\1/p')
      iptables -t nat -D POSTROUTING "$RULE_NUMBER"
      iptables -t nat -A POSTROUTING -o "$PRIMARY_IF" -j MASQUERADE
      echo "nameserver $PRIMARY_IP" > /etc/resolv.conf 
      read # delete!!!!!!!!!!!!!!!!!!!!!!!!
    fi
  else # гугл недоступен по основному интерфейсу
    echo 2
    # Are we using the primary?
    if gateway_if "$PRIMARY_IF"
    then # Switch to backup
      echo calling hartings
    elif gateway_if "$SECONDARY_IF"
    then
      echo sdfsdf
    elif gateway_if "$TERTIARY_IF"
    then
      echo sdfsdf2
    elif gateway_if ""
    then
      # у нас нет никакого гейтвея. обычно это происходит если модем не поднял dhcp
      # ну или мы вручную удалили маршрут по умолчанию
      # наш скрипт удаляет дефолты бесследно
      # раз мы попали сюда, значит инета в 3ж-модеме уже нет.
      # в этом случае нам нужно искать интернеты в хартингах
      echo sdfsdf3
      search_harting      
    fi
  fi
done
