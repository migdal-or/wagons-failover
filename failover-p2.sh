#!/bin/bash -x

# v.13. TODO: rewrite using systemd

sleep 30 # cause otherwise iptables and all that is not loaded

DEBUG="1"
WAITREAD="0"
# Function to optionally handle executing included debug statements
_debug()
{
    # I prefer using if/then for readability, but this is an unusual case
    [ "${DEBUG}" -ne 0 ] && "$@"
}
# Function to optionally handle executing included debug statements
waitread()
{
    # I prefer using if/then for readability, but this is an unusual case
    [ "${WAITREAD}" -ne 0 ] && "$@"
}

# не включён ли уже маскарад? если включён, то похоже что наш скрипт уже гоняли. тогда нафиг пожалуйста.
RULE_NUMBER=$(iptables -t nat -L --line-numbers | grep -m1 MASQUERADE | sed -rn 's/([0-9]*).*MASQUERADE.*/\1/p')
if [ ! -v ${RULE_NUMBER:-} ]
then
  printf "Masquerade is already on. Please disable it and rerun because the script switches it:\niptables -t nat -D POSTROUTING $RULE_NUMBER\n"
#  _debug iptables -t nat -D POSTROUTING $RULE_NUMBER
  exit 1
fi

# Set defaults if not provided by environment
CHECK_DELAY=${CHECK_DELAY:-15}
CHECK_IP=${CHECK_IP:-8.8.4.4}

PING_PARAMETERS=${PING_PARAMETERS:-"-c5 -w 5 -n"}
PRIMARY_PING_PARAMETERS=${PRIMARY_PING_PARAMETERS:-"-c5 -w 10 -n"}

# Первый — 3G/LTE модем.
PRIMARY_IF=${PRIMARY_IF:-eth0.10}
PRIMARY_GW=${PRIMARY_GW:-192.168.0.1}
PRIMARY_IP=$(ip address show dev "$PRIMARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*)\/.*$/\1/p')
# TODO убрать?
iptables -t nat -A POSTROUTING -o "$PRIMARY_IF" -j MASQUERADE

# Второй — хартинги
SECONDARY_IF=${SECONDARY_IF:-eth0.20}
# узнать сеть и адрес на хартинговом интерфейсе, понадобится для связи с соседями
SECONDARY_NET=$(ip address show dev "$SECONDARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*).*$/\1/p')
SECONDARY_IP=$(ip address show dev "$SECONDARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*)\/.*$/\1/p')

# Третий — ADSL-модем Zyxel
TERTIARY_IF=${TERTIARY_IF:-eth0.30}
# узнать айпи на adsl интерфейсе
TERTIARY_NET=$(ip address show dev "$TERTIARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*).*$/\1/p')
TERTIARY_IP=$(ip address show dev "$TERTIARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*)\/.*$/\1/p')

# Compare arg with current default gateway interface for route to healthcheck IP
gateway_if() {
  [[ "$1" = "$(ip route get "$CHECK_IP" | sed -rn 's/^.*dev ([^ ]*).*$/\1/p')" ]]
}

# TODO переписать на кэширование массива соседей, проверять их чтобы не гонять nmap зазря, а пинговать сначала этих
search_if2() {
  (nmap -sn "$SECONDARY_NET" -T5 --exclude "$SECONDARY_IP" -oG - | grep "Status: Up" | sed -rn 's/Host: ([^ ]*) \(.*/\1/p') | while read -r line
  do
      # в переменной line у нас перебираются соседи.
      # Если хоть один нашёлся, посмотрим есть ли у него интернет.
      # если да — будем использовать его
      _debug echo $line
      waitread read
      # надо проверить, есть ли в нём интернет
      ip route add "$CHECK_IP" via "$line" dev "$SECONDARY_IF"
      _debug echo ping "$PING_PARAMETERS" "$CHECK_IP"
      if ping "$PING_PARAMETERS" -I "$SECONDARY_IF" "$CHECK_IP" &>/dev/null
      then
        ip route delete "$CHECK_IP"
        _debug echo "works, switch to this $line"
        ip route delete default
        ip route add default via $line dev "$SECONDARY_IF"
        ip route flush cache
        echo "nameserver $line" > /etc/resolv.conf

        RULE_NUMBER=$(iptables -t nat -L --line-numbers | grep -m1 MASQUERADE | sed -rn 's/([0-9]*).*MASQUERADE.*/\1/p')
        iptables -t nat -D POSTROUTING $RULE_NUMBER
        iptables -t nat -A POSTROUTING -o "$SECONDARY_IF" -j MASQUERADE
      _debug echo break do
      break
    fi
    ip route delete "$CHECK_IP"
  done
}

search_if3() {
  (nmap -sn "$TERTIARY_NET" -T5 --exclude "$TERTIARY_IP" -oG - | grep "Status: Up" | sed -rn 's/Host: ([^ ]*) \(.*/\1/p') | while read -r line
  do
    # в переменной line у нас перебираются возможные гейтвеи.
    # Если хоть один сработал, будем использовать его
    _debug echo $line
    waitread read
    # надо проверить, есть ли в нём интернет
    ip route add "$CHECK_IP" via "$line" dev "$TERTIARY_IF"
    if ping "$PING_PARAMETERS" -I "$TERTIARY_IF" "$CHECK_IP" &>/dev/null
    then
      ip route delete "$CHECK_IP"
      # works, switch to this
      ip route delete default
      ip route add default via $line dev "$TERTIARY_IF"
      ip route flush cache
      echo "nameserver $line" > /etc/resolv.conf

      RULE_NUMBER=$(iptables -t nat -L --line-numbers | grep -m1 MASQUERADE | sed -rn 's/([0-9]*).*MASQUERADE.*/\1/p')
      iptables -t nat -D POSTROUTING $RULE_NUMBER
      iptables -t nat -A POSTROUTING -o "$TERTIARY_IF" -j MASQUERADE
      _debug echo break do
      break
    fi
    ip route delete "$CHECK_IP"
  done
_debug echo end cycle, none found2
}

echo "nameserver $PRIMARY_GW" > /etc/resolv.conf

# Cycle healthcheck continuously with specified delay
while true # sleep "$CHECK_DELAY" is in the end of this script
do
  _debug echo BEGIN
  waitread read
  ip route add "$CHECK_IP" via "$PRIMARY_GW" dev "$PRIMARY_IF"
  # If healthcheck succeeds from primary interface
  if ping "$PRIMARY_PING_PARAMETERS" -I "$PRIMARY_IF" "$CHECK_IP" &>/dev/null
  then
    # switch to it immediately
    ip route delete "$CHECK_IP"
    _debug echo "healthcheck succeeds from primary interface"
    # Are we using any of the backups?
    if (! gateway_if "$PRIMARY_IF")
    then # Switch to primary
      _debug echo "main interface is up, switch to it"
      ip route delete default
      ip route add default via "$PRIMARY_GW" dev "$PRIMARY_IF"
      ip route flush cache
      RULE_NUMBER=$(iptables -t nat -L --line-numbers | grep -m1 MASQUERADE | sed -rn 's/([0-9]*).*MASQUERADE.*/\1/p')
      iptables -t nat -D POSTROUTING "$RULE_NUMBER"
      iptables -t nat -A POSTROUTING -o "$PRIMARY_IF" -j MASQUERADE
      echo "nameserver $PRIMARY_GW" > /etc/resolv.conf
    else
      _debug echo "we were on primary, stay on it"
    fi
  else # гугл недоступен по основному интерфейсу
    ip route delete "$CHECK_IP"
    _debug echo "healthcheck fails from primary interface"
    # Are we using the primary?
    if gateway_if "$PRIMARY_IF"
    then # Switch to backup
      _debug echo "we used primary, check secondary"
      waitread read
      search_if2
      if ping "$PING_PARAMETERS" -I "$SECONDARY_IF" "$CHECK_IP" &>/dev/null
      then
        _debug echo "found secondary, switch ok 1"
      else
        _debug echo "secondary failed, searching tertiary"
        waitread read
        search_if3
        if ping "$PING_PARAMETERS" -I "$TERTIARY_IF" "$CHECK_IP" &>/dev/null
        then
          _debug echo "found tertiary, switch ok 1"
        else
          _debug echo "complete failure2"
        fi
      fi
    elif gateway_if "$SECONDARY_IF"
    then
      _debug echo "we used secondary, check it"
      # first check if secondary if works. if no, we will switch to tertiary
      # but we have to search secondary again TODO
      if ping "$PING_PARAMETERS" -I "$SECONDARY_IF" "$CHECK_IP" &>/dev/null
      then
        _debug echo "secondary works, stay on it"
      else
        _debug echo "secondary fails, search secondary again"
        waitread read
        search_if2
        if ping "$PING_PARAMETERS" -I "$SECONDARY_IF" "$CHECK_IP" &>/dev/null
        then
          _debug echo "found secondary, switch ok 2"
        else
	  search_if3
          if ping "$PING_PARAMETERS" -I "$TERTIARY_IF" "$CHECK_IP" &>/dev/null
          then
            _debug echo "found tertiary, switch ok 3"
          else
            _debug echo "complete failure3"
          fi
        fi
      fi
    elif gateway_if "$TERTIARY_IF"
    then
      _debug echo "we used tertiary, check it"
      # first check if tertiary interface works. if no, we will switch to secondary
      if ping "$PING_PARAMETERS" -I "$TERTIARY_IF" "$CHECK_IP" &>/dev/null
      then
        _debug echo "tertiary works, stay on it"
      else
        _debug echo "tertiary fails, search it again"
        waitread read
        search_if3
        if ping "$PING_PARAMETERS" -I "$TERTIARY_IF" "$CHECK_IP" &>/dev/null
        then
          _debug echo "found tertiary, switch ok 2"
        else
          search_if2
          if ping "$PING_PARAMETERS" -I "$SECONDARY_IF" "$CHECK_IP" &>/dev/null
          then
            _debug echo "found secondary, switch ok 3"
          else
            _debug echo "complete failure4"
          fi
        fi
      fi
    elif gateway_if ""
    then
      _debug echo "no interface at all, try if2 then if3"
      waitread read
      search_if2
      if ping "$PING_PARAMETERS" -I "$SECONDARY_IF" "$CHECK_IP" &>/dev/null
      then
        _debug echo "found secondary, switch ok 2"
      else
        search_if3
        if ping "$PING_PARAMETERS" -I "$TERTIARY_IF" "$CHECK_IP" &>/dev/null
        then
          _debug echo "found tertiary, switch ok 3"
        else
          _debug echo "complete failure3"
        fi
      fi
    else
      # у нас нет никакого гейтвея, никакого default route
      # возможно, это потому что не виден модем
      # ну или мы вручную удалили маршрут по умолчанию
      # или неправильные названия интерфейсов
      # тут какая-то херь
      echo "wtf"
      search_if2
    fi
  fi
  sleep "$CHECK_DELAY"
  waitread read
done
