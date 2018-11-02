#!/bin/bash

printf "this is the internet checkup script on 765/630"

while true
do
	printf "\n\n"
	date +"--- this is the check at %s %T %Z %z---"
	printf "our ip is "
	curl -s http://whatismyip.akamai.com/
	printf " or maybe "
	dig +short myip.opendns.com @resolver1.opendns.com
        ping -c5 -W5 8.8.4.4 &
        ping -c5 -W5 1.1.1.1 &
	sleep 15
done
