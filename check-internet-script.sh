#!/bin/bash

printf "this is the internet checkup script on 765/630"

while true
do
	ping -c5 -W5 8.8.4.4 &
	ping -c5 -W5 1.1.1.1 &
	printf "\n\n"
	date +"--- this is the check at %s %T ---"
	sleep 15
done
