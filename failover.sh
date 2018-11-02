#!/bin/bash

#iptables -t nat --flush

#rm /tmp/failover.log
screen -L /tmp/failover.log -d -m -S failover /etc/failover-p2.sh

#screen -d -m -S failover /etc/failover-p2.sh
