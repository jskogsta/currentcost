#!/usr/bin/perl
 
use Device::SerialPort qw( :PARAM :STAT 0.07 );
use XML::Simple;

$port = "/dev/ttyUSB0";

 

$ob = Device::SerialPort->new($port) or die "Can not open port $port\n";
$ob->baudrate(57600);
$ob->write_settings;
$ob->close;


# using XML::Parser speeds xml parsing up lots!
$backend = 'XML::Parser';
$ENV{XML_SIMPLE_PREFERRED_PARSER} = $backend;


# we use this to only do 1 iteration (or not)
$escape=0; 


open(SERIAL, "<$port");

while($escape <= 0) {
	sleep(2);

	while ($line = <SERIAL>) {

		# for debug
		#print $line;

		$isValid = (index($line,"<msg>") != -1);


		if (!$isValid) { last; }

		print "This data is".($isValid==1?"":" not")." valid\n";

		# force XML::Simple to see this as a string not as a file
		# since XML::Simple is stupid and needs to be shot

		$line = "<fakeTag>$line</fakeTag>";

		$isHistoric = (index($line,"<hist>") != -1);

		$nref = XMLin($line,forcearray => 0);

		$ref = $nref->{msg};

		# just for reference, show if data is historic or not

		print "This data is".($isHistoric==1?"":" not")." historic\n";


		if (!$isHistoric) {

	        	$dsb        = 0 + $ref->{dsb};
        		$recordTime = $ref->{time};
        		$ccname     = $ref->{src};
        		$temp       = $ref->{tmpr};
			$ch1watts   = 0 + $ref->{ch1}->{watts};
			$sensor     = 0 + $ref->{sensor};
			$id         = $ref->{id};
			$type       = 0 + $ref->{type};


			if (defined $ref->{whatever}) {
				# do something based on whatever
				
			}

        		print "This $ccname was born $dsb days ago as at $recordTime - temperature is: $temp :: Current Watts in use on channel 1 are $ch1watts :: Sensor is $sensor, with an id of $id and a type of $type\n";

			# for cacti you'd probably just want to output CC_Temperature:$temp CC_Watts1:$ch1watts 

			# insert data into db

			# if you want to exit after a 'good' iteration set this to 1 otherwise set it to 0 (or don't change it to 1 :) );
			$escape=1;


		} else {
			#process or ignore historic data


		}
	}
}

close(SERIAL);




