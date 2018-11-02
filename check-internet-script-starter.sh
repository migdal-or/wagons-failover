#!/bin/bash

screen -L /tmp/internet-checkup.log -d -m -S inetcheck /home/user/wagons-failover-master/check-internet-script.sh
