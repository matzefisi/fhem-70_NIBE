#!/usr/bin/perl -w

use strict;
use Device::SerialPort;

print "Initialize Serial Interface\n";

# Please change here the serial device. E.g. /dev/ttyS0
my $serial = Device::SerialPort->new("/dev/serial_heizung")
     || die "Can't open Device: $!\n";

$serial->baudrate(9600);	# Set the baudrate / port speed
$serial->databits(8);		# 8 Databits
$serial->parity("none");	# No parity bit
$serial->stopbits(1);		# One Stopbit
$serial->purge_all();		# ????
$serial->lookclear();		# Clear all the buffers

# Define the basic variables
my $counter=0;			# General counter to stop the programm after a certain period
my @daten;			# Array for storing the mesage
my $serial_write="";		# String for the data which should be sent
my $serial_read="";		# String for reading the serial data

while($counter < 39999) {
	# Increase counter to have a predefined stop point of the script to cleanly close the serial port. 
	$counter=$counter+1;

	# Read One byte from the serial line
	my($count, $serial_read) = $serial->read(1);

	# Check for the beginning of a message 
	if (unpack("H*",$serial_read) eq "5c") {
		@daten=();
	}

	# Add the newly read data to the array
	if (unpack("H*",$serial_read) ne "") {
		push (@daten, unpack("H*",$serial_read));
	}

	# Check if the end of the message has arrived
	if (defined $daten [0] && $daten[0] eq "5c" && defined $daten[4] && defined $daten[5]) {

		# Check if the length of the message is reached.	
		if (0+@daten==hex($daten[4])+6) {

			# Send the ACK byte. This currently does not work. The script stops at this point without any error message. TODO!
			# If this is not solved, the heater jumps within a few seconds into alert mode. 
			#$serial->write("\x06")  || die "Cant write to serial port. $^E\n";
	                #$serial->write_drain;

			# Calculate checksum
			my $j=0;
			my $checksum=0;

			for (my $j = 2; $j < hex($daten[4])+5; $j++) {
        			$checksum = $checksum^hex($daten[$j]);
  			}

			print "Header: $daten[0]$daten[1] Busaddr: $daten[2] CMD: $daten[3] LEN: $daten[4] CHK: $daten[@daten-1]";
		
			if ($checksum==hex($daten[@daten-1])) {
				print " - Checksum OK\n";
			} else {
				print " - Checksum not OK\n";
			}

			# Print the full data
			for (my $j = 0; $j < 0+@daten; $j++) {
				print $daten[$j];
			}
			print "\n\n";


			@daten=();
		}
	}
}

$serial->close ||warn "Close Failed";
print "\nScript Ended\n";
