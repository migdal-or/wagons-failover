#!/bin/bash

screen -L /tmp/internet-checkup.log -d -m -S inetcheck /tmp/inetcheck/wagons-failover/check-internet-script.sh
