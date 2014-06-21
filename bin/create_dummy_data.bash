#!/bin/bash
#
# Author: Jorgen Skogstad
# Last updated: 21st of June 2014
# Email: jorgen@skogstad.com
#
# Script info:
# ---------------------------------------------------
# This script was done to create dummy data by running over a few (or many) days, which produced the dummy data which was 
# inserted into the MySQL and WSO2BAM databases. This data was then exported, such that sample data is available
# to start creating hive queries, which is the essential logic to the Currentcost solution. 
#

echo "Start generating sample dummy data [ hit CTRL+C to stop]"

while :
do

	# Generate a radom temperature reading - we will use $RANDOM for the wattage reading
	r=$(( $RANDOM % 10 + 10 ))
	r2=$(( $RANDOM % 10 + 10 ))
	temp="$r.$r2"

	wattage=$RANDOM

	# Generate temporary xml to be used for the insertion
	cat ./ccost_data_sample.xml | sed "s/TEMP/$temp/g" > ./.temp1.xml
	cat ./.temp1.xml | sed "s/WATTAGE/$wattage/g" > ./.temp2.xml

	randtime=$(( $RANDOM % 10 ))
	current_time=`date`
	echo "$current_time: Lets wait for a random number of seconds: $randtime. Temperature=$temp, Watt=$wattage"
	sleep $randtime

	# Pump the random data into MySQL and WSO2BAM. Assuming here that the Perl daemon file is monitoring the local xml file rather than running production against serial port.
	cat ./.temp2.xml >> ../ccost.xml

	# Clean up before the next iteration; e.g. delete the temp xml files
	#rm ./.temp1.xml
	#rm ./.temp2.xml
	#exit

done

