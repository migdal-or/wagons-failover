#!/bin/bash

screen -L /tmp/internet-checkup.log -d -m -S inetcheck /home/user/wagons-failover/check-internet-script.sh
