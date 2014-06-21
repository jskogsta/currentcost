#!/usr/bin/perl -w
#
# File:			currentcost_daemon.pl
# Version info:	This version is the basic one, which only gets the raw data and transforms to BAM & MySQL data. It does not create the
#				added information that relates to watt_seconds, which can be used for the data presentation & assumptions. The background for
#				that requirement is that the Currentcost sends samples at varying times. Hence we have to normalise the data with this in 
#				mind.
# Project: 		Currentcost perl daemon to be run on a Tonidoplug v1
# Purpose: 		The purpose of this perl daemon is to continously monitor the inbound /dev/ttyUSB0 channel for XML data that represents energy
#				samples, which will have to be parsed and pumped into a MySQL database. This database will serve as the data store from which 
#				the front-end will derive its data to present useful graphs, events, triggers etc.
# Filename: 	ccost.pl
# Last updated:	Sunday June 8th 2014
# By whom?:		Jorgen Skogstad ( jorgen@skogstad.com )
#
# Information relevant to the program given below: 
# ---------------------------------------------------
#
# The following XML structure is the structured output given by the Currentcost meter
# as and when the sensor sends a trigger event. This is what we have to parse later, and
# extract then the TIME, CHANNEL and WATTAGE, which will be used to pump into the MySQL
# database.
#
# This was derived from the Currentcost XML spec here: http://www.currentcost.com/cc128/xml.htm & http://www.currentcost.com/download/Envi%20XML%20v19%20-%202011-01-11.pdf
# The EnviR can be paired against 10 sensors at max, and is a manual process. As such, the sensor ID uniquely identifies the bespoke sensor. See here: http://www.currentcost.com/product-cc128-installation.html
# In my basic build, I only have 1 sensor, which is for the whole of house (sensor 0). The three channels are got three phase power, but in most instances this is not required, and likely can only look at channel 1 in the xml.
# Info: "With the Envi model up to 3 channels for 3-phase power, or a secondary meter box, can be monitored. These will appear as the endpoints ch.1, ch.2 and ch.3"
# From: http://www.dbzoo.com/livebox/xap_currentcost
#
#	<msg>
#	   <src>CC128-v0.11</src>
#	   <dsb>00089</dsb>
#	   <time>13:02:39</time>
#	   <tmpr>18.7</tmpr>
#	   <sensor>1</sensor>
#	   <id>01234</id>
#	   <type>1</type>
#	   <ch1>
#	      <watts>00345</watts>
#	   </ch1>
#	   <ch2>
#	      <watts>02151</watts>
#	   </ch2>
#	   <ch3>
#	      <watts>00000</watts>
#	   </ch3>
#	</msg>
#
# The data above is sent over the serialport from the Currentcost as a single line (see url: http://www.jibble.org/currentcost/). Hence simple to parse based on inbound serial port loop!
# It seems like the Curentcost EnviR meter will send out a message of the type above for each sensor message that is received from the various sensors.
#
# The following is the simple MySQL database table that holds the sample data. This can be used in phpMyAdmin to create the base table that is required for this to work. 
#
#
#--
#-- Table structure for table `CurrentCostDataSamples_MySQL_Dump`
#--
#
# CREATE TABLE `CurrentCostDataSamples_MySQL_Dump` (
#   `messageRowID` varchar(100) NOT NULL,
#   `payload_sensor` tinyint(4) DEFAULT NULL,
#   `messageTimestamp` bigint(20) DEFAULT NULL,
#   `payload_temp` float DEFAULT NULL,
#   `payload_timestamp` bigint(20) DEFAULT NULL,
#   `payload_timestampmysql` datetime DEFAULT NULL,
#   `payload_watt` int(11) DEFAULT NULL,
#   `payload_wattseconds` bigint(20) DEFAULT NULL,
#   PRIMARY KEY (`messageRowID`)
# ) ENGINE=InnoDB DEFAULT CHARSET=latin1;
#
# - Starting the program can be done with a simple shell command (but remember to update the directory statements). Note that the Perl program will daemonise and run in the background.
# > root@TonidoPlug:~/projects/ccost# perl ./currentcost_daemon.pl
# - If you have enabled logging (by turning the switch further down to 1), you can tail the log file as exemplified here: 
# > root@TonidoPlug:~/projects/ccost# tail -f ./ccost.log
# - If you are running against a local file to test this (which also have to be turned on by the right switch further down), you can push another XML sample onto the inbound file like this: 
# > root@TonidoPlug:~/projects/ccost# cat ccost_data_sample.xml >> ccost.xml


use strict;
use warnings;
use Device::SerialPort qw( :PARAM :STAT 0.07 );	# Uncomment when using on Tonidoplug
use XML::LibXML;
use DateTime::Format::MySQL;
use 5.12.5;
use Time::localtime; 
use DateTime;
use DBI; 
use File::Tail;						# Use to test local file based input VS ongoing serial port input.
use Data::Dumper;
use Log::Log4perl qw(:easy);
use Proc::Daemon;
use LWP::UserAgent;
use File::Slurp;

# Daemonise the Perl program to log the Currentcost data to MySQL
#Proc::Daemon::Init;
#my $continue = 1;
#$SIG{TERM} = sub { $continue = 0 };

# Initialize Logger
my $log_conf = q(
   log4perl.rootLogger              = DEBUG, LOG1
   log4perl.appender.LOG1           = Log::Log4perl::Appender::File
   log4perl.appender.LOG1.filename  = /Users/jskogsta/projects/ccost/ccost.log
   log4perl.appender.LOG1.mode      = append
   log4perl.appender.LOG1.layout    = Log::Log4perl::Layout::PatternLayout
   log4perl.appender.LOG1.layout.ConversionPattern = %d %p %m %n
);
Log::Log4perl::init(\$log_conf);

my $logger = Log::Log4perl->get_logger();

# Use local file for inbound test OR serial port
my $local_or_serial = 0;	# 0 = local file, 1 = serial port
my $local_xmlfile = "/Users/jskogsta/projects/ccost/ccost.xml";
# Are we going to use debug logging, or not?
my $logging = 1;			# 0 = logging off, 1 = logging on. 
my $cc_last_sample_epoch_time = 0;		# storing the last epoch which was the last time the CC sent a sample. Used to calculate watt_seconds

# invoke the ConnectToMySQL sub-routine to make the database connection
my $db_connection = ConnectToMySql(my $database);

# Given we daemonise the program, it will just continue to loop through from there and continue pumping data to MySQL ..
#while ($continue) {

	if ($local_or_serial == 0) {
			# Testing against local file
			if ($logging == 1) { $logger->info("Testing against local file: $local_xmlfile") };

			# Max time to wait between checks. File::Tail uses an adaptive
			# algorithm to vary the time between file checks, depending on the
			# amount of data being written to the file. This is the maximum
			# allowed interval.
			my $maxinterval = 1;

			my $file = File::Tail->new(name=>$local_xmlfile, maxinterval=> $maxinterval, adjustafter=>3) or ( say "Dying!" && die );

			# Loop as long as we keep getting lines from the file
			while (defined(my $line = $file->read)) {
				if ($logging == 1) { $logger->info("Input XML: ", $line) };
				&parse_cc_xml($line, $db_connection);

			}

		} else {
			# Production; using the serial port
			my $PORT = "/dev/ttyUSB0";

			if ($logging == 1) { $logger->info("Running production against: $PORT") };

			# Connect to Current Cost device
			# This is the serial port in the Tonidoplug - uncomment when using this script on the Tonidoplug with the Currentcost data cable
			my $ob = Device::SerialPort->new($PORT) || die "Can't open $PORT: $!\n";
			$ob->baudrate(57600);
			$ob->write_settings;

			# Continously loop through serial input from currentcost // START
			open(SERIAL, "+>$PORT") or die "$!\n";

			while (my $line = <SERIAL>) {
				if ($logging == 1) { $logger->info("Inbound line: $line") };
				&parse_cc_xml($line, $db_connection);

			}		

		}
#}

sub parse_cc_xml {
	if ($logging ==1) { $logger->info("parse_cc_xml") };

	my $logger = Log::Log4perl->get_logger();

	# Create a new XML parser
	my $parser = XML::LibXML->new();
	my $doc = $parser->parse_string( $_[0] );
	# <msg><src>CC128-v0.11</src><dsb>00089</dsb><time>13:02:39</time><tmpr>18.7</tmpr><sensor>1</sensor><id>01234</id><type>1</type><ch1><watts>00345</watts></ch1></msg>

	# DEFINE CORRECT MySQL TIMESTAMP
	# Find the timestamp in the XML file, but will not use this given the uncertainty of the timestamp being correct. Rather use the NTP sync'ed value on the computer ..
	my $time = $doc->find('//time');
	# Break up the HH:MM:SS format derived from the Currentcost xml
	my ($hours, $minutes, $seconds) = split(/:/, $time);
	my $tm = localtime; 
	#my $timestamp = ($tm->hour . ':' . $tm->min . ':' . $tm->sec);					# No need for this based on current time as this is given by the Currentcost meter, or could replace if need be.. prob better if computers are NTP time sync'ed.
	my $datestamp = ($tm->year+1900 . '-' . (($tm->mon)+1) . '-' . $tm->mday);
	# Using the computers timestamp given this is NTP sync'ed, which most likely is better given the uncertainty on wrong timestamps set on Currentcost itself .. 
	my $dat = DateTime->new( year => $tm->year+1900, month => (($tm->mon)+1), day => $tm->mday, hour => $tm->hour, minute => $tm->min, second => $tm->sec );
	#my $dat = DateTime->new( year => $tm->year+1900, month => (($tm->mon)+1), day => $tm->mday, hour => $hours, minute => $minutes, second => $seconds );
	# Convert to MySQL datetime format, ready for SQL INSERT statement
	my $mysql_datetime_stamp = DateTime::Format::MySQL->format_datetime($dat);

	# DEFINE TEMP (CELCIUS)
	my $temp = $doc->find('//tmpr');

	# DEFINE SENSOR ID
	my $sensor_id = $doc->find('//sensor');

	# DEFINE WATTAGE
	my $wattage = $doc->find('./msg/ch1/watts');
	#my @channels;
	#my @nodelist = $nodeset1->get_nodelist;
	#@channels = map($_->string_value, @nodelist);
	# Remove leading 0'es from the wattage strings, and assuming that each sensor have only ONE channel - e.g. one WATTAGE item..
	$wattage =~ s/^0+//;
	
	if ($logging ==1) { $logger->info($temp, ", ", $sensor_id, ", ", $mysql_datetime_stamp, ", ", $wattage) };

	# Prepare the local temp JSON data object that will be pushed to WSO2BAM using curl. The data structure of the file is:
	#
	#	[
	#		{
	#		"payloadData" : ["SENSOR", TEMP, TIMESTAMP, WATT] ,
	#		}
	#	]

	my $sensor_old = "SENSOR";
	my $sensor_new = $sensor_id;
	my $temp_old = "TEMP";
	my $temp_new = $temp;
	my $unix_epoch_time_old = "TIMESTAMP";
	my $unix_epoch_time_new = time;
	my $timestamp_mysql_old = "MYSQL";
	my $timestamp_mysql_new = "$mysql_datetime_stamp";
	my $watt_old = "WATT";
	my $watt_new = int($wattage); 					# $watt_old is not defined; just using the reference to the value array later..
	my $watt_seconds_old = "WSECONDS";				# this holds the consumed watts since last sample, using UNIX epoch time as the reference
	my $epoch_seconds_diff = 0;

	# Read the JSON template that we have to update with the right values. Done only once..
	my $json_template = read_file( 'currentcostRealtime_json_template_simple.json' ) ;
	my $json_template_payload = read_file( 'currentcostRealtime_json_template_payload_simple.json' );

	$json_template_payload =~ s/$sensor_old/$sensor_new/g;
	$json_template_payload =~ s/$temp_old/$temp_new/g;
	$json_template_payload =~ s/$unix_epoch_time_old/$unix_epoch_time_new/g;
	$json_template_payload =~ s/$timestamp_mysql_old/$timestamp_mysql_new/g;
	$json_template_payload =~ s/$watt_old/$watt_new/g;
	# Calculate the watt seconds consumed since last sample
	if ($logging == 1) { $logger->info("The local UNIX epoch time is: $unix_epoch_time_new, and the last sample time was: $cc_last_sample_epoch_time") };
	if ($cc_last_sample_epoch_time == 0) {
		$cc_last_sample_epoch_time = $unix_epoch_time_new;
	} else {
		$epoch_seconds_diff = ($unix_epoch_time_new - $cc_last_sample_epoch_time);
		$cc_last_sample_epoch_time = $unix_epoch_time_new;
	}

	if ($logging == 1) { $logger->info("Seconds since last sample: $epoch_seconds_diff") };

	my $watt_seconds_new = $watt_new * $epoch_seconds_diff; 	# This derives the amount of watt_seconds consumed since last sample, and is what we will store as consumed energy.
	$json_template_payload =~ s/$watt_seconds_old/$watt_seconds_new/g;
	if ($logging == 1) { $logger->info("Number of watt_seconds consumption in between now and last sample is $watt_seconds_new") };

	open FILE, ">.currentcostRealtime_json_template_test.json";  #opens file to be written to
	print FILE $json_template;             #write it to our file
	close FILE;                   #then close our file.
	open FILE, ">.currentcostRealtime_json_template_payload_test.json";  #opens file to be written to
	print FILE $json_template_payload;             #write it to our file
	close FILE;                   #then close our file.

	system('/opt/local/bin/curl -k --user admin:admin https://localhost:9443/datareceiver/1.0.0/streams/ --data @.currentcostRealtime_json_template_test.json -H "Accept: application/json" -H "Content-type: application/json" -X POST');
	system('/opt/local/bin/curl -k --user admin:admin https://localhost:9443/datareceiver/1.0.0/stream/currentcost.stream/1.0.18/ --data @.currentcostRealtime_json_template_payload_test.json -H "Accept: application/json" -H "Content-type: application/json" -X POST');



	# Build the MySQL INSERT query that has to be executed
	my $query = "insert into CurrentCostDataSamples_MySQL_Dump_Raw (timestamp, temp, sensor_id, watts) 
		values (?, ?, ?, ?) ";

	# prepare your statement for connecting to the database
	my $statement = $_[1]->prepare($query);

	# execute your SQL statement
	$statement->execute($mysql_datetime_stamp, $temp, $sensor_id, $watt_new);

}

sub ConnectToMySql {
	my $logger = Log::Log4perl->get_logger();

	# MySQL database configuration
	my $db = 'currentcost';
	my $host = '127.0.0.1';
	my $user = 'currentcost';
	my $pass = 'currentcost';
	my $port = '8889';

	# connect to the remote MySQL database that has the Currentcost table(s)
	my $dsn = "DBI:mysql:database=$db;host=$host;port=$port";
	my $dbh  = DBI->connect($dsn, $user ,$pass , { RaiseError => 1 }) or die ( "Couldn't connect to database: " . DBI->errstr );
	if ($logging == 1) { $logger->info("Connected to the MySQL database.") };

	# the value of this connection is returned by the sub-routine
	return $dbh;

}


