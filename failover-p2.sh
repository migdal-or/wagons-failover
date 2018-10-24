#!/bin/bash -x

# setup main firewall rules
#iptables -t filter -A INPUT -i lo -j ACCEPT
#iptables -t filter -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
#iptables -t filter -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
#iptables -t filter -A INPUT -i eth0 -j DROP
#iptables -t filter -A FORWARD -i eth0 -p tcp -m tcp --dport 50000 -m state --state NEW -j ACCEPT

/etc/profile.d/server_variables.sh

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

STATUS=0
PING_PARAMETERS=${PING_PARAMETERS:-"-w 1 -c1"}

# Первый — 3G/LTE модем.
PRIMARY_IF=${PRIMARY_IF:-enp3s6}
# проверять есть ли там вообще адрес
PRIMARY_GW=${PRIMARY_GW:-192.168.3.1}
PRIMARY_IP=$(ip address show dev "$PRIMARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*)\/.*$/\1/p')
# TODO убрать
iptables -t nat -A POSTROUTING -o "$PRIMARY_IF" -j MASQUERADE

# Второй — хартинги
SECONDARY_IF=${SECONDARY_IF:-enp2s0}
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
  [[ "$1" = "$(ip route get "$CHECK_IP" | sed -rn 's/^.*dev ([^ ]*).*$/\1/p')" ]]
}

search_if2() {
  STATUS=0
  (nmap -sn "$SECONDARY_NET" -T5 --exclude "$SECONDARY_IP" -oG - | grep "Status: Up" | sed -rn 's/Host: ([^ ]*) \(.*/\1/p') | while read -r line
  do
      # в переменной line у нас перебираются возможные гейтвеи.
      # Если хоть один сработал, будем использовать его
#      echo $line
#      read
      # надо проверить, есть ли в нём интернет
      ip route add "$CHECK_IP" via "$line" dev "$SECONDARY_IF"
      echo ping "$PING_PARAMETERS" "$CHECK_IP"
      if ping "$PING_PARAMETERS" "$CHECK_IP" &>/dev/null	# it was -I "$SECONDARY_IF" 
      then
        ip route delete "$CHECK_IP"
        echo "works, switch to this $line"
        ip route delete default
        ip route add default via $line dev "$SECONDARY_IF"
        echo "nameserver $line" > /etc/resolv.conf

        RULE_NUMBER=$(iptables -t nat -L --line-numbers | grep -m1 MASQUERADE | sed -rn 's/([0-9]*).*MASQUERADE.*/\1/p')
        iptables -t nat -D POSTROUTING $RULE_NUMBER
        iptables -t nat -A POSTROUTING -o "$SECONDARY_IF" -j MASQUERADE
#      return 1  # TODO!! DOES NOT RETURN!
      STATUS=1
#      echo break do
      break
#      echo after break do
    fi
    ip route delete "$CHECK_IP"
  done
#  echo end cycle, none found
  return "$STATUS"
}

search_if3() {
  STATUS=0
  (nmap -sn "$TERTIARY_NET" -T5 --exclude "$TERTIARY_IP" -oG - | grep "Status: Up" | sed -rn 's/Host: ([^ ]*) \(.*/\1/p') | while read -r line
  do
    # в переменной line у нас перебираются возможные гейтвеи.
    # Если хоть один сработал, будем использовать его
#    echo $line
    # надо проверить, есть ли в нём интернет
    ip route add "$CHECK_IP" via "$line" dev "$TERTIARY_IF"
    if ping "$PING_PARAMETERS" "$CHECK_IP" &>/dev/null
    then
      ip route delete "$CHECK_IP"
      # works, switch to this
      ip route delete default
      ip route add default via $line dev "$TERTIARY_IF"
      echo "nameserver $line" > /etc/resolv.conf

      RULE_NUMBER=$(iptables -t nat -L --line-numbers | grep -m1 MASQUERADE | sed -rn 's/([0-9]*).*MASQUERADE.*/\1/p')
      iptables -t nat -D POSTROUTING $RULE_NUMBER
      iptables -t nat -A POSTROUTING -o "$TERTIARY_IF" -j MASQUERADE
#      return 1  # TODO!! DOES NOT RETURN!
      STATUS=1
#      echo break do
      break
#      echo after break do
    fi
    ip route delete "$CHECK_IP"
#    echo trap2
  done
#  echo end cycle, none found2
  return "$STATUS"
}

# Cycle healthcheck continuously with specified delay
# while true
while sleep "$CHECK_DELAY"
do
#  echo BEGIN
  read
  # If healthcheck succeeds from primary interface
  ip route add "$CHECK_IP" via "$PRIMARY_GW" dev "$PRIMARY_IF"
  if ping "$PING_PARAMETERS" "$CHECK_IP" &>/dev/null
  then
    ip route delete "$CHECK_IP"
    echo "healthcheck succeeds from primary interface"
    # Are we using any of the backups?
    if (! gateway_if "$PRIMARY_IF")
    then # Switch to primary
      echo "main interface is up, switch to it"
      ip route delete default
      ip route add default via "$PRIMARY_GW" dev "$PRIMARY_IF"
      RULE_NUMBER=$(iptables -t nat -L --line-numbers | grep -m1 MASQUERADE | sed -rn 's/([0-9]*).*MASQUERADE.*/\1/p')
      iptables -t nat -D POSTROUTING "$RULE_NUMBER"
      iptables -t nat -A POSTROUTING -o "$PRIMARY_IF" -j MASQUERADE
      echo "nameserver $PRIMARY_GW" > /etc/resolv.conf 
    fi
  else # гугл недоступен по основному интерфейсу
    ip route delete "$CHECK_IP"
    echo "healthcheck fails from primary interface"
    # Are we using the primary?
    if gateway_if "$PRIMARY_IF"
    then # Switch to backup
      echo "we used primary, check secondary"
      read
      if [[ "$(search_if2)" = "1" ]]
#      search_if2
#      if ping "$PING_PARAMETERS" "$CHECK_IP" &>/dev/null
      then
        #:
        echo "found secondary, switch ok 1"
      else
        echo "secondary failed, searching tertiary"
        read
        if [[ "$(search_if3)" = "1" ]]
#        if ping "$PING_PARAMETERS" -I "$TERTIARY_IF" "$CHECK_IP" &>/dev/null
        then
          #:
          echo "found tertiary, switch ok 1"
        else
          #:
          echo "complete failure2"
        fi
      fi
    elif gateway_if "$SECONDARY_IF"
    then
      echo "we used secondary, check it"
      # first check if secondary if has internet. if no, we will switch to tertiary
      # but we have to search secondary again TODO
      if ping "$PING_PARAMETERS" "$CHECK_IP" &>/dev/null
      then
        echo "secondary works, stay on it"
        #:
      else
        echo "secondary fails, search secondary again"
        read
      if [[ "$(search_if2)" = "1" ]]
#        if ping "$PING_PARAMETERS" -I "$TERTIARY_IF" "$CHECK_IP" &>/dev/null
        then
          #:
          echo "found secondary, switch ok 2"
        else
	# search if3
        if [[ "$(search_if3)" = "1" ]]
          then
            #:
            echo "found tertiary, switch ok 3"
          else
            echo "complete failure3"
          fi
        fi
      fi
    elif gateway_if "$TERTIARY_IF"
    then
      #:
      echo "we used tertiary"
      # first check if tertiary interface has internet. if no, we will switch to secondary
      if ping "$PING_PARAMETERS" "$CHECK_IP" &>/dev/null
      then
        echo "tertiary works, stay on it"
        #:
      else
        echo "tertiary fails, search it again"
        read
        if [[ "$(search_if3)" = "1" ]]
      then
          #:
          echo "found tertiary, switch ok 2"
        else
          if [[ "$(search_if2)" = "1" ]]
#          if ping "$PING_PARAMETERS" "$CHECK_IP" &>/dev/null
          then
            #:
            echo "found secondary, switch ok 3"
          else
            echo "complete failure4"
          fi
        fi
      fi

    else
      # у нас нет никакого гейтвея. обычно это происходит если модем не поднял dhcp
      # ну или мы вручную удалили маршрут по умолчанию
      # тут какая-то херь
      # наш скрипт удаляет дефолты бесследно
      # раз мы попали сюда, значит инета в 3ж-модеме уже нет.
      # в этом случае нам нужно искать интернеты в хартингах
      echo "wtf"
      # search_if2      
    fi
  fi
done
