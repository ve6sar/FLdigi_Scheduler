#!/usr/bin/perl -w
# This is a PERL based beacon timer for FLDIGI by Sean Smith, VE6SAR
# Version 0.3 alpha - Add database detection and log file creation / upload
# Version 0.3a alpha - Adjust database parameters
# Version 0.3b alpha - Fixed date format for database insertion
# Version 0.3c alpha - Fixed Database insertion
# Version 0.4 alpha - Added DNS lookup to determine the Database IP address.
#
# Ensure to set your beacon times in @shed and the macro number in $macro_number
# 
# fldigi RPC Port 7362

use strict;
use Socket;
use RPC::XML;
use RPC::XML::Client;
use POSIX qw(strftime);
use Time::HiRes qw(usleep nanosleep);
use DBI;

################ User specific variables ##########################################################
my $callSign = '';  			# Your Call Sign in Capitals
my $gridLocation = ''; 		# Your Grid Square format DO16ee
my $txPower = '40 Watts'; 			# Your Transmit Power to the antenna
my $antennaDesc = 'Inverted V'; 	# What Antenna are you running
my @sched = ("15:00", "45:00"); 	# minutes and seconds after the hour as assigned by the project team

#Set up configuration variables for Fldigi
my $frequency = '5357000.000000'; 	# Frequency in Hz must have 6 zeros after decimal!
my $modem = 'Olivia-4-250';			# The modem that should be used
my $macro_number = 7; 					# Count macro number from left to right starting at 0
my $carrier = 1500;						# Carrier audio centre

############## No Editing required below this line ###############################################

#Set up timer variables
my $now_string = strftime "%M:%S", localtime;
# or for GMT formatted appropriately for your locale:
my $now_gmt = strftime "%a %b %e %H:%M:%S %Y", gmtime;
my $beacon_state;

#Set the rest of our variables
my $resp;
my $date;
my $unixEpoch;
my $modemName;
my $rigFrequency;
my $beaconLog = 'tx-beacons.log';

#Database variables
my $dbh;
my $sth;
my $driver = "mysql";
#my $db_server = "159.89.122.183"; # Uncomment to use ip address
my $db_server = inet_ntoa(inet_aton('auroralpower.ca')); # Insert DB server domain name or comment out to use ip address
my $db_database = "";
my $db_user = "";
my $db_pass = "";
my $dsn = "DBI:$driver:database=$db_database;host=$db_server";
my $db_st = 0; #Database connection status



#Setup connection to fldigi
my $cli = RPC::XML::Client->new('http://127.0.0.1:7362');

print "Fldigi PERL beacon timer Alpha Version 0.4\r\n";
print "Written by Sean Smith, VE6SAR for the auroralpower.ca 60m propagation experiment\r\n";
print "Questions can by sent to ve6sar at gmail.com\r\n\r\n";
print "The database server location is $db_server \r\n\r\n";
print "Beacons are scheduled to be sent at to following times each hour \r\n"; 
foreach my $y (@sched) {
	print "$y ";	
}
print ".\r\n";


#Timer loop will run forever....
while (1){
	$now_string = strftime "%M:%S", localtime; #Get current minutes and seconds to compare against our schedule
	$now_gmt = strftime "%a %b %e %H:%M:%S %Y", gmtime; #Get current UTC time for printing the status message

	foreach my $x (@sched){
		if ($x eq $now_string) { 
				$beacon_state = 1; #Set the beacon flag to send the beacon		
			} else { 
				$beacon_state = 0; #Set the beacon flag to not send the beacon
			}

		if ($beacon_state == 1) {

			#Get fldigi version to test if it's running 	
			$resp = $cli->send_request('fldigi.version');

			if ($resp =~ m/(HTTP server error)/) {
				print "Looks like Fldigi isn't running lets start it\r\n";
				system ("nohup /usr/bin/fldigi >/dev/null 2>&1 &"); #run fldigi
				sleep 10; #let fldigi load
			}

			#Get Fldigi version for printing to screen
			$resp = $cli->send_request('fldigi.version');
			print "Fldigi Version = ".$resp->value."\r\n";

			#Set frequency
			$resp = $cli->send_request('main.set_frequency', $frequency);
			print "Old Frequency was ".$resp->value." hz\r\n";

			#Get New Frequency
			$resp = $cli->send_request('main.get_frequency');
			print "Frequency set to ".$resp->value."  hz\r\n";

			#Set modem
			$resp = $cli->send_request('modem.set_by_name', $modem);
			print "Old modem was ".$resp->value."\r\n";

			$resp = $cli->send_request('modem.get_name');
			print "Modem now set to ".$resp->value."\r\n";

			#Set the carrier frequency
			$resp = $cli->send_request('modem.set_carrier', $carrier);
			print "Modem was ".$resp->value." Hz.\r\nNow set to $carrier Hz\r\n";

			#Send the beacon
			$resp = $cli->send_request('main.run_macro', $macro_number);
			print "Sending Beacon\r\n";
			
			$unixEpoch = time; #Get current UTC time for printing the status message
			$date = strftime "%Y-%m-%d %H:%M:%S", gmtime; #Get current UTC time for printing the status message

			
			#Pause to allow the transmitter to start transmitting
			sleep 2; 

			#Check that the transmitter is transmitting
			$resp = $cli->send_request('main.get_trx_status'); 

			if ($resp->value eq 'tx' ) {
				print "All good we are transmitting!\r\n";
				##### Put database insertion code here	#####
				$rigFrequency = $frequency / 1000000; # Convert from Hz to mHz
				$rigFrequency = $rigFrequency." MHz";
			
				#Update database when we transmit
				#Connect to the Database
				print "Connecting to Database.....\r\n";
				
				#Check our connection to the database
				$dbh = DBI->connect($dsn, $db_user, $db_pass, {
      			PrintError => 0,
      			RaiseError => 0
  				}  );
				unless (!$dbh) { #If connected changed our state variable 
					$db_st = 1; 
					print "Connected\r\n";
					$dbh->disconnect or warn $dbh->errstr;
					} 
				unless ($dbh) { # If NOT connected save the file
					$db_st = 0; 
					print "Not Able to Connect saving to log file\r\n";
					open(my $fh, '>>', $beaconLog) or die "Could not open file '$beaconLog' $!";
					say $fh "'$callSign', '$date', '$unixEpoch', '$gridLocation', '$txPower', '$antennaDesc', '$modem', '$rigFrequency'\r\n";
					close $fh;
					}				
					
				
				if ($db_st == 1) {
					$dbh = DBI->connect($dsn, $db_user, $db_pass ) or die $DBI::errstr;
					$sth = $dbh->prepare("INSERT INTO `beacons` (`id`, `callSign`, `date`, `unixEpoch`, `gridLocation`, `txPower`, `antennaDesc`, `modemName`, `rigFrequency`) 
									VALUES (NULL, '$callSign', '$date', '$unixEpoch', '$gridLocation', '$txPower', '$antennaDesc', '$modem', '$rigFrequency');");

					$sth->execute() or warn $DBI::errstr;
					print "Inserting into Database.....\r\n";
	
	
					if (-e $beaconLog) {
 						print "Log File Exists, uploading to DB\r\n";
 						upload (); # Insert Log file entries into the database 
 					}	
	
					#Close database connection
					$dbh->disconnect or warn $dbh->errstr;					
					$db_st = 0; # Reset the connection variable
				}
				print "Waiting for next beacon time......\r\n";							
			} else { 
				print "Something went wrong! We aren't transmitting!\r\n";
			}
			my $datestring = localtime();
			print "Local date and time $datestring\n";
			print "Waiting for next beacon time......\r\n";
		}
	}
usleep (250000);
}

sub upload { # Insert log entries into the database and remove the file
	open(my $fh, $beaconLog) or die "Could not open file '$beaconLog' $!";
	while (my $row = <$fh>) {
   	chomp $row;
    	print "$row";
		if ($row){    	
#    		print "INSERT INTO `beacons` (`id`, `callSign`, `date`, `unixEpoch`, `gridLocation`, `txPower`, `antennaDesc`, `modemName`, `rigFrequency`) 
#									VALUES (NULL, $row);\r\n";
    		$sth = $dbh->prepare("INSERT INTO `beacons` (`id`, `callSign`, `date`, `unixEpoch`, `gridLocation`, `txPower`, `antennaDesc`, `modemName`, `rigFrequency`) 
										VALUES (NULL, $row);");

			$sth->execute() or die $DBI::errstr;
			print "Inserting into Database.....\r\n";
		}
  	}	
	close $fh;
	unlink $beaconLog;  	# Delete the log file 
}
