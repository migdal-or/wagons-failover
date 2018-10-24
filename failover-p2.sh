#!/bin/bash

# Set defaults if not provided by environment
CHECK_DELAY=${CHECK_DELAY:-5}
CHECK_IP=${CHECK_IP:-8.8.8.8}

# Первый — 3G/LTE модем.
PRIMARY_IF=${PRIMARY_IF:-eth0.10}
PRIMARY_GW=${PRIMARY_GW:-192.168.0.1}

# Второй — хартинги
SECONDARY_IF=${SECONDARY_IF:-eth0.20}
# узнать айпи на хартинговом интерфейсе
SECONDARY_NET=$(ip address show dev "$SECONDARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*).*$/\1/p')
SECONDARY_IP=$(ip address show dev "$SECONDARY_IF" | grep -m1 inet | sed -rn 's/.*inet ([^ ]*)\/.*$/\1/p')



SECONDARY_GW=${SECONDARY_GW:-2.3.4.5}


