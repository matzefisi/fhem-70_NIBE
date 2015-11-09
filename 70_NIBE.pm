#################################################################################
# 70_NIBE.pm
# Module to read and write messages to NIBE heat pumps
# Supported models: F750, F1245, ....
#
# Currently this module works with a USB to RS485 interface which is directly 
# connected to the heatpump using the MODBUS 40 address. The MODBUS 40 module
# is NOT needed for this to work.
#
# Matthias Rammes
#
# German comments: Input from FHEMWIKI
# English comments: from Matthias
#
##############################################

package main;

use strict;
use warnings;
use Device::SerialPort;

sub NIBE_Initialize ($)
{
#(initialisiert das Modul und gibt de Namen der zusätzlichen Funktionen bekannt)

	# Load the DevIo Module of FHEM
	require "$attr{global}{modpath}/FHEM/DevIo.pm";
	
	# Read the parameters into $hash
	my ($hash) = @_;
	
	# Define the functions
	$hash->{ReadFn}     = "NIBE_Read";				# Read serial data
	$hash->{ReadyFn}    = "NIBE_Ready"; 			# ????
	$hash->{DefFn}      = "NIBE_Define";			# Define the device
	$hash->{UndefFn}    = "NIBE_Undef"; 			# Delete the device
	$hash->{GetFn}      = "NIBE_Get";				# Manually get data
	$hash->{ParseFn}    = "NIBE_Parse";				# Parse function - Only used for two step modules?
	$hash->{StateFn}    = "NIBE_SetState";			# Only used for setting the state of the module?
	# $hash->{Match}      = ".*";						# ???????????????????
	$hash->{AttrList}   = $readingFnAttributes;		# Define the possible Attributes
	$hash->{ShutdownFn} = "NIBE_Shutdown";			# ????
}

sub NIBE_Define ($)
{
	#(wird beim define aufgerufen)
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	return "wrong syntax: 'define <name> NIBE <devicename>'"
	if(@a < 3);

	DevIo_CloseDev($hash);

	my $name = $a[0];
	my $dev = $a[2];
		
	#$hash->{fhem}{interfaces} = "power";

	$attr{$name}{"event-min-interval"} = ".*:30";

    # set baudrate to 9600 if not defined
	my ($devname, $baudrate) = split("@", $dev);
	$dev .= '@9600' if (!defined($baudrate));

	$hash->{DeviceName}   = $dev;

	Log3 $hash, 5, "NIBE: Defined";

	my $ret = DevIo_OpenDev($hash, 0, "NIBE_DoInit");

	return $ret;
}

sub NIBE_SetState($$$$) {
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

sub NIBE_Clear($) {
	my $hash = shift;
	my $buf;
	# clear buffer:
	if($hash->{NIBE}) 
	   {
	   while ($hash->{NIBE}->lookfor()) 
		  {
		  $buf = DevIo_DoSimpleRead($hash);
		  $buf = uc(unpack('H*',$buf));
		  }
	   }

	return $buf;
} 

sub NIBE_DoInit($) {
	my $hash = shift;
	my $name = $hash->{NAME}; 
	my $init ="?";
	my $buf;

	#$serial->baudrate(9600);	# Set the baudrate / port speed
	#$serial->databits(8);		# 8 Databits
	#$serial->parity("none");	# No parity bit
	#$serial->stopbits(1);		# One Stopbit
	#$serial->purge_all();		# ????
	#$serial->lookclear();		# Clear all the buffers

	NIBE_Clear($hash); 

	return undef; 
}

sub NIBE_Undef ($) {
#(wird beim Löschen einer Geräteinstanz aufgerufen - Gegenteil zu define)
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};
	delete $hash->{FD};
	$hash->{STATE}='close';
	$hash->{NIBE}->close() if($hash->{NIBE});
	Log3 $hash, 0, "NIBE: Undefined";
	return undef;
}

sub NIBE_Shutdown($) {
  my ($hash) = @_;
  DevIo_CloseDev($hash); 
  return undef;
}

sub NIBE_Disconnected($) {
  my $hash = shift;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
 	
  return if(!defined($hash->{FD})); # Already deleted
	
  DevIo_CloseDev($hash);
  Log3 $hash, 1, "NIBE: $dev disconnected, waiting to reappear";

  $readyfnlist{"$name.$dev"} = $hash; # Start polling
  $hash->{STATE} = "disconnected";
	
  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");
} 

sub NIBE_Set ($)
{
# wird beim Befehl set aufgerufen um Daten an das Gerät zu senden
# We need this eventually later when we try to send messages to the heatpump.
# Usecase: Reduce ventilation speed when the wood stove is heating up

	#http://elektronikforumet.com/forum/viewtopic.php?f=4&t=13714&sid=34bc49f6c5651c1464df383af2906265&start=165
	#sendBuffer[0] = 0x01; // To the master address 1
	#sendBuffer[1] = 0x10; // Write command
	#sendBuffer[2] = 0xB7; // High byte address register
	#sendBuffer[3] = 0xA3; // Low byte address register
	#sendBuffer[4] = 0x00; // Number of register to write high byte
	#sendBuffer[5] = 0x01; // Number of register to write low byte
	#sendBuffer[6] = 0x02; // Number of following bytes
	#tempshort = short.Parse(textBox29.Text);
	#shortBuffer = BitConverter.GetBytes(tempshort);
	#sendBuffer[7] = shortBuffer[1]; // Value to set, high byte
	#sendBuffer[8] = shortBuffer[0]; // Value to set, low byte
	#CRC = ModRTU_CRC(sendBuffer, 9);
	#sendBuffer[9] = (byte)CRC;
	#sendBuffer[10] = (byte)(CRC / 256);

	return 0;
}

sub NIBE_Get ($) {
#(wird beim Befehl get aufgerufen um Daten vom Gerät abzufragen)

#Just a short queue to print out the content of the hash.
	my ($hash) = @_;
	my $name = $hash->{NAME};
	while ( my($k,$v) = each $hash ) {
		Log3 $name, 5, "$k => $v";
	}
}

#sub NIBE_Attr ($) {
#(wird beim Befehl attr aufgerufen um beispielsweise Werte zu prüfen)
#}

sub NIBE_ParseFrame ($$$) {
    my ($hash, $length, $command) = @_;
    my $name = $hash->{NAME};
    my $frame = substr($hash->{helper}{buffer}, index($hash->{helper}{buffer},"5c00"));
    
    Log3 $name, 4, "$name: parse: $frame";

    # Calculate checksum
    my $j=0;
    my $checksum=0;
    for (my $j = 2; $j < $length+5; $j++) {
            $checksum = $checksum^hex(substr($frame, $j*2 ,2));
    }

    # what we got so far
    Log3 $name, 4, "$name: HEAD: ".substr($frame,0,4)." ADDR: ".substr($frame,4,2)
                        ." CMD: ".substr($frame,6,2)." LEN: ".substr($frame,8,2)
                        ." CHK: ".substr($frame,length($frame)-2,2);


    if ($checksum==hex(substr($frame, length($frame)-2, 2))) {
        Log3 $name, 4, "$name: Checksum OK";

        # Check if we got a message with the command 68 
        # In this message we can expect 20 values from the heater which were defined with the help of ModbusManager
        if ($command eq "68") {
            # Populate the reading(s)
            readingsBeginUpdate($hash);

            my $j=10;
            while($j <  $length*2) {
                if (substr($frame,$j,8) =~ m/(.{2})(.{2})(.{2})(.{2})/) {
                    my $register = $2.$1;
                    my $value    = $4.$3;
  
                    if ($register ne "ffff") {    
                        # Getting the register name
                        my $reading = return_register( hex($register),0);
                    
                        # Calculating the actual value
                        my $reading_value;
                        if (defined($reading)) {
                            my $valuetype  = return_register( hex($register),3);
                            my $factor     = return_register( hex($register),4);
                            $reading_value = return_normalizedvalue($valuetype,$value)/$factor;
                        } else {
                            Log3 $name, 3, "$name: Register ".hex($register)." not defined";
                            $reading_value = $value;
                        }

                        readingsBulkUpdate($hash, $reading, $reading_value);
                    }
                }
                $j += 8;
            }

            readingsEndUpdate($hash, 1);
        }
    } else {
        Log3 $name, 4, "$name: Checksum not OK";
    }
    
    $hash->{helper}{buffer} = "";
}

sub NIBE_Read ($)
{
#(wird vom globalen select aufgerufen, falls Daten zur Verfuegung stehen)
#$hash->{READINGS}{state}
    my $hash = shift;
    my $name = $hash->{NAME};
    my $buf  = DevIo_SimpleRead($hash);

	if(!defined($buf) || length($buf) == 0) {
		NIBE_Disconnected($hash);
		return "";
	}

    Log3 $name, 5, "$name: raw read: " . unpack ('H*', $buf);

    $hash->{helper}{buffer} .= unpack ('H*', $buf);
    if ($hash->{helper}{buffer} =~ m/5c00(.{2})(.{2})(.{2}).*/) {
        my $address = $1;
        my $command = $2;
        my $length  = hex($3);
        
        if (length($hash->{helper}{buffer})/2 >= index($hash->{helper}{buffer}, "5c00") + $length + 6) {
            # Send the ACK byte.
            DevIo_SimpleWrite($hash, '06', 1);
            # Parse
            NIBE_ParseFrame($hash, $length, $command);
        }
    }  
}

sub  NIBE_Parse 
{
#(wird bei zweistufigen Modulen vom Dispatch aufgerufen und muss hier noch beschrieben werden)
}

sub NIBE_Ready 
{
#(wird unter windows als ReadFn-Erstatz benoetigt bzw. um zu pruefen, ob ein Geraet wieder eingesteckt ist)
  my ($hash) = @_;
  return DevIo_OpenDev($hash, 0, "NIBE_DoInit")
	if($hash->{STATE} eq "disconnected");
}
	
#NIBE_Notify (falls man benachrichtigt werden will)
#NIBE_Rename (falls ein Gerät umbenannt wird)


sub return_normalizedvalue {
	# Helper for normalizing the value
	#s16, #s32, #u16, u8, #u32, #s8
	my ($type, $value) = @_;
	if ($type eq "s8") {
	    return 0 if $value !~ /^[0-9A-Fa-f]{1,2}$/;
		my $num = hex($value);
		return $num >> 7 ? $num - 2 ** 8 : $num;
	}
	elsif ($type eq "s16") {
		return 0 if $value !~ /^[0-9A-Fa-f]{1,4}$/;
		my $num = hex($value);
		return $num >> 15 ? $num - 2 ** 16 : $num;
	}
	elsif ($type eq "s32") {
		return 0 if $value !~ /^[0-9A-Fa-f]{1,8}$/;
		my $num = hex($value);
		return $num >> 31 ? $num - 2 ** 32 : $num;
	}
	else {
		# To be done!
		# Lazy replacement for U8 -> U32
		return hex($value);
	}
}

sub return_register {

	# Content of each hash entry:
	#Title  = 0
	#Info	= 1
	#Unit	= 2
	#Size	= 3
	#Factor	= 4
	#Min	= 5
	#Max	= 6
	#Default= 7
	#Mode	= 8
	
	my (@input) = @_;
	my %register = (
	40004 => ["BT1 Outdoor temp","Outdoor temperature","°C","s16","10","0","0","0","R"],
	40005 => ["EB23-BT2 Supply temp S4","Supply temperature for system 4","°C","s16","10","0","0","0","R"],
	40005 => ["EB23-BT2 Supply temp S4","Supply temperature for system 4","°C","s16","10","0","0","0","R"],
	40006 => ["EB22-BT2 Supply temp S3","Supply temperature for system 3","°C","s16","10","0","0","0","R"],
	40007 => ["EB21-BT2 Supply temp S2","Supply temperature for system 2","°C","s16","10","0","0","0","R"],
	40008 => ["BT2 Supply temp S1","Supply temperature for system 1","°C","s16","10","0","0","0","R"],
	40012 => ["EB100-EP14-BT3 Return temp","Return temperature","°C","s16","10","0","0","0","R"],
	40013 => ["BT7 Hot Water top","","°C","s16","10","0","0","0","R"],
	40014 => ["BT6 Hot Water load","","°C","s16","10","0","0","0","R"],
	40017 => ["EB100-EP14-BT12 Cond. out","","°C","s16","10","0","0","0","R"],
	40018 => ["EB100-EP14-BT14 Hot gas temp","","°C","s16","10","0","0","0","R"],
	40019 => ["EB100-EP14-BT15 Liquid line","","°C","s16","10","0","0","0","R"],
	40020 => ["EB100-BT16 Evaporator temp","","°C","s16","10","0","0","0","R"],
	40022 => ["EB100-EP14-BT17 Suction","","°C","s16","10","0","0","0","R"],
	40025 => ["EB100-BT20 Exhaust air temp.","","°C","s16","10","0","0","0","R"],
	40026 => ["EB100-BT21 Vented air temp.","","°C","s16","10","0","0","0","R"],
	40030 => ["EB23-BT50 Room Temp S4","","°C","s16","10","0","0","0","R"],
	40031 => ["EB22-BT50 Room Temp S3","","°C","s16","10","0","0","0","R"],
	40032 => ["EB21-BT50 Room Temp S2","","°C","s16","10","0","0","0","R"],
	40033 => ["BT50 Room Temp S1","","°C","s16","10","0","0","0","R"],
	40045 => ["EQ1-BT64 PCS4 Supply Temp","PCS4 Only","°C","s16","10","0","0","0","R"],
	40047 => ["EB100-BT61 Supply Radiator Temp","","°C","s16","10","0","0","0","R"],
	40048 => ["EB100-BT62 Return Radiator Temp","","°C","s16","10","0","0","0","R"],
	40050 => ["EB100-BS1 Air flow","","","s16","10","0","0","0","R"],
	40051 => ["EB100-BS1 Air flow unfiltered","Unfiltered air flow value","","s16","100","0","0","0","R"],
	40054 => ["EB100-FD1 Temperature limiter","","","s16","1","0","0","0","R"],
	40067 => ["BT1 Average","EB100-BT1 Outdoor temperature average","°C","s16","10","0","0","0","R"],
	40071 => ["BT25 external supply temp","","°C","s16","10","0","0","0","R"],
	40072 => ["BF1 Flow","Current flow","l/m","s16","10","0","0","0","R"],
	40074 => ["EB100-FR1 Anode Status","","","s16","1","0","0","0","R"],
	40077 => ["BT6 external water heater load temp.","This includes DEW and SCA accessory","°C","s16","10","0","0","0","R"],
	40078 => ["BT7 external water heater top temp.","This includes DEW and SCA accessory","°C","s16","10","0","0","0","R"],
	40079 => ["EB100-BE3 Current Phase 3","","A","s32","10","0","0","0","R"],
	40081 => ["EB100-BE2 Current Phase 2","","A","s32","10","0","0","0","R"],
	40083 => ["EB100-BE1 Current Phase 1","","A","s32","10","0","0","0","R"],
	40107 => ["EB100-BT20 Exhaust air temp.","","°C","s16","10","0","0","0","R"],
	40108 => ["EB100-BT20 Exhaust air temp.","","°C","s16","10","0","0","0","R"],
	40109 => ["EB100-BT20 Exhaust air temp.","","°C","s16","10","0","0","0","R"],
	40110 => ["EB100-BT21 Vented air temp.","","°C","s16","10","0","0","0","R"],
	40111 => ["EB100-BT21 Vented air temp.","","°C","s16","10","0","0","0","R"],
	40112 => ["EB100-BT21 Vented air temp.","","°C","s16","10","0","0","0","R"],
	40127 => ["EB23-BT3 Return temp S4","Return temperature for system 4","°C","s16","10","0","0","0","R"],
	40128 => ["EB22-BT3 Return temp S3","Return temperature for system 3","°C","s16","10","0","0","0","R"],
	40129 => ["EB21-BT3 Return temp S2","Return temperature for system 2","°C","s16","10","0","0","0","R"],
	40141 => ["AZ2-BT22 Supply air temp. SAM","","ºC","s16","10","0","0","0","R"],
	40142 => ["AZ2-BT23 Outdoor temp. SAM","","ºC","s16","10","0","0","0","R"],
	40143 => ["AZ2-BT68 Flow temp. SAM","Heat medium flow temperature to SAM module","°C","s16","10","0","0","0","R"],
	40144 => ["AZ2-BT69 Return temp. SAM","Heat medium return temperature from SAM module","°C","s16","10","0","0","0","R"],
	40157 => ["EP30-BT53 Solar Panel Temp","","°C","s16","10","0","0","0","R"],
	40158 => ["EP30-BT54 Solar Load Temp","","°C","s16","10","0","0","0","R"],
	43001 => ["Software version","","","u16","1","0","0","0","R"],
	43005 => ["Degree Minutes","","","s16","10","-30000","30000","0","R/W"],
	43006 => ["Calculated Supply Temperature S4","","°C","s16","10","0","0","0","R"],
	43007 => ["Calculated Supply Temperature S3","","°C","s16","10","0","0","0","R"],
	43008 => ["Calculated Supply Temperature S2","","°C","s16","10","0","0","0","R"],
	43009 => ["Calculated Supply Temperature S1","","°C","s16","10","0","0","0","R"],
	43013 => ["Freeze Protection Status","1 = Freeze protection active","","u8","1","0","0","0","R"],
	43061 => ["t. after start timer","","","u8","1","0","0","0","R"],
	43062 => ["t. after mode change","Time after mode change","","u8","1","0","0","0","R"],
	43064 => ["HMF dT set.","set point delta T for the heat medium flow","","s16","10","0","0","0","R"],
	43065 => ["HMF dT act.","Current value of the delta T for the heat medium flow","","s16","10","0","0","0","R"],
	43081 => ["Tot. op.time add.","Total electric additive operation time","h","s32","10","0","9999999","0","R"],
	43084 => ["Int. el.add. Power","Current power from the internal electrical addition","kW","s16","100","0","0","0","R"],
	43086 => ["Prio","Indicates what heating action (HW/heat/pool) currently prioritised 10=Off 20=Hot Water 30=Heat 40=Pool 41=Pool 2 50=Transfer 60=Cooling","","u8","1","0","0","0","R"],
	43091 => ["Int. el.add. State","State of the internal electrical addition","","u8","1","0","0","0","R"],
	43108 => ["Fan speed current","The current fan speed after scheduling and blocks are considered","%","u8","1","0","0","0","R"],
	43122 => ["Compr. current min.freq.","The current minimum frequency of the compressor","Hz","s16","1","0","0","0","R"],
	43123 => ["Compr. current max.freq.","The current maximum frequency of the compressor","Hz","s16","1","0","0","0","R"],
	43124 => ["Airflow ref.","Reference value for the airflow.","","s16","10","0","0","0","R"],
	43132 => ["Inverter com. timer","This value shows the time since last communication with the inverter","sec","u16","1","0","0","0","R"],
	43133 => ["Inverter drive status","","","u16","1","0","0","0","R"],
	43136 => ["Compr. current freq.","The frequency of the compressor at the moment","Hz","u16","10","0","0","0","R"],
	43137 => ["Inverter alarm code","","","u16","1","0","0","0","R"],
	43138 => ["Inverter fault code","","","u16","1","0","0","0","R"],
	43140 => ["compr. temp.","Current compressor temparture","°C","s16","10","0","0","0","R"],
	43141 => ["compr. in power","The power delivered from the inverter to the compressor","W","u16","1","0","0","0","R"],
	43144 => ["Compr. energy total","Total compressor energy in kWh","kWh","u32","100","0","9999999","0","R"],
	43147 => ["Compr. in current","The current delivered from the inverter to the compressor","A","s16","1","0","0","0","R"],
	43181 => ["Chargepump speed","","","s16","1","0","0","0","R"],
	43182 => ["Compr. freq. setpoint","The targeted compressor frequency","Hz","u16","1","0","0","0","R"],
	43239 => ["Tot. HW op.time add.","Total electric additive operation time in hot water mode","h","s32","10","0","9999999","0","R"],
	43305 => ["Compr. energy HW","Compressor energy during hot water production in kWh","kWh","u32","100","0","9999999","0","R"],
	43375 => ["compr. in power mean","Mean power delivered from the inverter to the compressor. Mean is calculated every 10 seconds.","W","s16","1","0","0","0","R"],
	43382 => ["Inverter mem error code","","","u16","1","0","0","0","R"],
	43416 => ["Compressor starts EB100-EP14","Number of compressorer starts","","s32","1","0","9999999","0","R"],
	43420 => ["Tot. op.time compr. EB100-EP14","Total compressorer operation time","h","s32","1","0","9999999","0","R"],
	43424 => ["Tot. HW op.time compr. EB100-EP14","Total compressorer operation time in hot water mode","h","s32","1","0","9999999","0","R"],
	43427 => ["Compressor State EP14","20 = Stopped, 40 = Starting, 60 = Running, 100 = Stopping","","u8","1","0","0","0","R"],
	43435 => ["Compressor status EP14","Indicates if the compressor is supplied with power 0=Off 1=On","","u8","1","0","0","0","R"],
	43437 => ["HM-pump Status EP14","Status of the circ. pump","","u8","1","0","0","0","R"],
	43514 => ["PCA-Base Relays EP14","Indicates the active relays on the PCA-Base card. The information is binary encoded","","u8","1","0","0","0","R"],
	43516 => ["PCA-Power Relays EP14","Indicates the active relays on the PCA-Power card. The information is binary encoded","","u8","1","0","0","0","R"],
	43542 => ["Calculated supply air temp.","","ºC","s16","10","0","0","0","R"],
	44258 => ["External supply air accessory relays","Indicates the status of the relays on the external supply air accessory. The information is binary encoded. B0: relay K1 (QN40 close signal). B1: relay K2 (QN40 open signal)","","u8","1","0","0","0","R"],
	44267 => ["Calc. Cooling Supply Temperature S4","","°C","s16","10","0","0","0","R"],
	44268 => ["Calc. Cooling Supply Temperature S3","","°C","s16","10","0","0","0","R"],
	44269 => ["Calc. Cooling Supply Temperature S2","","°C","s16","10","0","0","0","R"],
	44270 => ["Calc. Cooling Supply Temperature S1","","°C","s16","10","0","0","0","R"],
	44317 => ["SCA accessory relays","Indicates the status of the relays on the SCA accessory. The information is binary encoded. B0: relay K1 (Solar pump). B1: relay K2 (Solar Cooling Pump) B2: relay K3 (QN28)","","u8","1","0","0","0","R"],
	44331 => ["Software release","","","u8","1","0","0","0","R"],
	45001 => ["Alarm number","The value indicates the most severe current alarm","","s16","1","0","0","0","R"],
	47062 => ["HW charge offset","Offset of HW charge temperature from the stop temperature","°C","s8","10","0","0","0","R/W"],
	47291 => ["Floor drying timer","","hrs","u16","1","0","10000","0","R"],
	47004 => ["Heat curve S4","Heat curve to use see manual for the different curves.","","s8","1","0","15","9","R/W"],
	47005 => ["Heat curve S3","Heat curve to use see manual for the different curves.","","s8","1","0","15","9","R/W"],
	47006 => ["Heat curve S2","Heat curve to use see manual for the different curves.","","s8","1","0","15","9","R/W"],
	47007 => ["Heat curve S1","Heat curve to use see manual for the different curves.","","s8","1","0","15","9","R/W"],
	47008 => ["Offset S4","Offset of the heat curve","","s8","1","-10","10","0","R/W"],
	47009 => ["Offset S3","Offset of the heat curve","","s8","1","-10","10","0","R/W"],
	47010 => ["Offset S2","Offset of the heat curve","","s8","1","-10","10","0","R/W"],
	47011 => ["Offset S1","Offset of the heat curve","","s8","1","-10","10","0","R/W"],
	47012 => ["Min Supply System 4","","°C","s16","10","50","700","200","R/W"],
	47013 => ["Min Supply System 3","","°C","s16","10","50","700","200","R/W"],
	47014 => ["Min Supply System 2","","°C","s16","10","50","700","200","R/W"],
	47015 => ["Min Supply System 1","","°C","s16","10","50","700","200","R/W"],
	47016 => ["Max Supply System 4","","°C","s16","10","50","700","600","R/W"],
	47017 => ["Max Supply System 3","","°C","s16","10","50","700","600","R/W"],
	47018 => ["Max Supply System 2","","°C","s16","10","50","700","600","R/W"],
	47019 => ["Max Supply System 1","","°C","s16","10","50","700","600","R/W"],
	47020 => ["Own Curve P7","User defined curve point","°C","s8","1","0","80","15","R/W"],
	47021 => ["Own Curve P6","User defined curve point","°C","s8","1","0","80","15","R/W"],
	47022 => ["Own Curve P5","User defined curve point","°C","s8","1","0","80","26","R/W"],
	47023 => ["Own Curve P4","User defined curve point","°C","s8","1","0","80","32","R/W"],
	47024 => ["Own Curve P3","User defined curve point","°C","s8","1","0","80","35","R/W"],
	47025 => ["Own Curve P2","User defined curve point","°C","s8","1","0","80","40","R/W"],
	47026 => ["Own Curve P1","User defined curve point","°C","s8","1","0","80","45","R/W"],
	47027 => ["Point offset outdoor temp.","Outdoor temperature point where the heat curve is offset","°C","s8","1","-40","30","0","R/W"],
	47028 => ["Point offset","Amount of offset at the point offset temperature","°C","s8","1","-10","10","0","R/W"],
	47029 => ["External adjustment S4","Change of the offset of the heat curve when closing the external adjustment input","","s8","1","-10","10","0","R/W"],
	47030 => ["External adjustment S3","Change of the offset of the heat curve when closing the external adjustment input","","s8","1","-10","10","0","R/W"],
	47031 => ["External adjustment S2","Change of the offset of the heat curve when closing the external adjustment input","","s8","1","-10","10","0","R/W"],
	47032 => ["External adjustment S1","Change of the offset of the heat curve when closing the external adjustment input","","s8","1","-10","10","0","R/W"],
	47033 => ["External adjustment with room sensor S4","Room temperature setting when closing the external adjustment input","°C","s16","10","50","300","200","R/W"],
	47034 => ["External adjustment with room sensor S3","Room temperature setting when closing the external adjustment input","°C","s16","10","50","300","200","R/W"],
	47035 => ["External adjustment with room sensor S2","Room temperature setting when closing the external adjustment input","°C","s16","10","50","300","200","R/W"],
	47036 => ["External adjustment with room sensor S1","Room temperature setting when closing the external adjustment input","°C","s16","10","50","300","200","R/W"],
	47041 => ["Hot water mode"," 0=Economy 1=Normal 2=Luxury","","s8","1","0","2","1","R/W"],
	47043 => ["Start temperature HW Luxury","Start temperature for heating water","°C","s16","10","50","700","470","R/W"],
	47044 => ["Start temperature HW Normal","Start temperature for heating water","°C","s16","10","50","700","450","R/W"],
	47045 => ["Start temperature HW Economy","Start temperature for heating water","°C","s16","10","50","700","380","R/W"],
	47046 => ["Stop temperature Periodic HW","Temperature where hot water generation will stop","°C","s16","10","550","700","550","R/W"],
	47047 => ["Stop temperature HW Luxury","Temperature where hot water generation will stop","°C","s16","10","50","700","520","R/W"],
	47048 => ["Stop temperature HW Normal","Temperature where hot water generation will stop","°C","s16","10","50","700","500","R/W"],
	47049 => ["Stop temperature HW Economy","Temperature where hot water generation will stop","°C","s16","10","50","700","430","R/W"],
	47050 => ["Periodic HW","Activates the periodic hot water generation","","s8","1","0","1","1","R/W"],
	47051 => ["Periodic HW Interval","Interval between Periodic hot water sessions","days","s8","1","1","90","14","R/W"],
	47054 => ["Run time HWC","Run time for the hot water circulation system","min","s8","1","1","60","3","R/W"],
	47055 => ["Still time HWC","Still time for the hot water circulation system","min","s8","1","0","60","12","R/W"],
	47092 => ["Manual compfreq HW","Should the compressor frequency be manual set in HW?","","u8","1","0","0","0","R/W"],
	47093 => ["Manual compfreq speed HW","Manual compressor frequency in HW?","Hz","u16","1","0","0","0","R/W"],
	47094 => ["Sec per compfreq step","Time between changes of the copmpressor frequency","s","u8","1","0","0","0","R/W"],
	47095 => ["Max compfreq step","Largest allowed change of compressor frequency in normal run","Hz","u8","1","0","0","0","R/W"],
	47096 => ["Manual compfreq Heating","Should the compressor frequency be manual set in Heating?","","u8","1","0","0","0","R/W"],
	47097 => ["Min speed after start","Time with minimum compressor frequency when heating demand occurs","Min","u8","1","0","0","0","R/W"],
	47098 => ["Min speed after HW","Should the compressor frequency be manual set in HW?","Min","u8","1","0","0","0","R/W"],
	47099 => ["GMz","Compressor frequency regulator GMz","","u8","1","0","0","0","R/W"],
	47100 => ["Max diff VBF-BerVBF","Largest allowed difference between Supply and calc supply","°C","u8","10","0","0","0","R/W"],
	47101 => ["Comp freq reg P","Compressor frequency regulator P","","u8","1","0","0","0","R/W"],
	47102 => ["Comp freq max delta F","Maximum change of copmpressor frequency in compressor frequency regulator","Hz","s8","1","0","0","0","R/W"],
	47103 => ["Min comp freq","Minimum allowed compressor frequency","Hz","s16","1","0","0","0","R/W"],
	47104 => ["Max comp freq","Maximum allowed compressor frequency","Hz","s16","1","0","0","0","R/W"],
	47105 => ["Comp freq heating","Compressor frequency used in heating mode","Hz","s16","1","0","0","0","R/W"],
	47131 => ["Language","Display language in the heat pump 0=English 1=Svenska 2=Deutsch 3=Francais 4=Espanol 5=Suomi 6=Lietuviu 7=Cesky 8=Polski 9=Nederlands 10=Norsk 11=Dansk 12=Eesti 13=Latviesu 16=Magyar","","s8","1","0","18","0","R/W"],
	47134 => ["Period HW","","min","u8","1","0","180","20","R/W"],
	47135 => ["Period Heat","","min","u8","1","0","180","20","R/W"],
	47136 => ["Period Pool","","min","u8","1","0","180","20","R/W"],
	47138 => ["Operational mode heat medium pump"," 10=Intermittent 20=Continous 30=Economy 40=Auto","","u8","1","10","40","40","R/W"],
	47206 => ["DM start heating","The value the degree minutes needed to be reached for the pump to start heating","","s16","1","-1000","-30","-60","R/W"],
	47207 => ["DM start cooling","The value the degree minutes needed to be reached for the pump to start cooling","","s16","1","0","0","0","R/W"],
	47208 => ["DM start add.","The value the degree minutes needed to be reached for the pump to start electric addition","","s16","1","0","0","0","R/W"],
	47209 => ["DM between add. steps","The number of degree minutes between start of each electric addition step","","s16","1","0","0","0","R/W"],
	47210 => ["DM start add. with shunt","","","s16","1","-2000","-30","-400","R/W"],
	47212 => ["Max int add. power","","kW","s16","100","0","4500","600","R/W"],
	47214 => ["Fuse","Size of the fuse that the HP is connected to","A","u8","1","1","200","16","R/W"],
	47261 => ["Exhaust Fan speed 4","","%","u8","1","0","100","100","R/W"],
	47262 => ["Exhaust Fan speed 3","","%","u8","1","0","100","80","R/W"],
	47263 => ["Exhaust Fan speed 2","","%","u8","1","0","100","30","R/W"],
	47264 => ["Exhaust Fan speed 1","","%","u8","1","0","100","0","R/W"],
	47265 => ["Exhaust Fan speed normal","","%","u8","1","0","100","65","R/W"],
	47266 => ["Supply Fan speed 4","","%","u8","1","0","100","90","R/W"],
	47267 => ["Supply Fan speed 3","","%","u8","1","0","100","70","R/W"],
	47268 => ["Supply Fan speed 2","","%","u8","1","0","100","25","R/W"],
	47269 => ["Supply Fan speed 1","","%","u8","1","0","100","0","R/W"],
	47270 => ["Supply Fan speed normal","","%","u8","1","0","100","60","R/W"],
	47271 => ["Fan return time 4","Time from a changed fan speed until it returns to normal speed","h","u8","1","1","99","4","R/W"],
	47272 => ["Fan return time 3","Time from a changed fan speed until it returns to normal speed","h","u8","1","1","99","4","R/W"],
	47273 => ["Fan return time 2","Time from a changed fan speed until it returns to normal speed","h","u8","1","1","99","4","R/W"],
	47274 => ["Fan return time 1","Time from a changed fan speed until it returns to normal speed","h","u8","1","1","99","4","R/W"],
	47275 => ["Filter Reminder period","Time between the reminder of filter replacement/cleaning.","Months","u8","1","1","24","3","R/W"],
	47276 => ["Floor drying"," 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47277 => ["Floor drying period 7","Days each period is active","days","u8","1","0","30","2","R/W"],
	47278 => ["Floor drying period 6","Days each period is active","days","u8","1","0","30","2","R/W"],
	47279 => ["Floor drying period 5","Days each period is active","days","u8","1","0","30","2","R/W"],
	47280 => ["Floor drying period 4","Days each period is active","days","u8","1","0","30","3","R/W"],
	47281 => ["Floor drying period 3","Days each period is active","days","u8","1","0","30","2","R/W"],
	47282 => ["Floor drying period 2","Days each period is active","days","u8","1","0","30","2","R/W"],
	47283 => ["Floor drying period 1","Days each period is active","days","u8","1","0","30","2","R/W"],
	47284 => ["Floor drying temp. 7","Supply temperature each period","°C","u8","1","15","70","20","R/W"],
	47285 => ["Floor drying temp. 6","Supply temperature each period","°C","u8","1","15","70","30","R/W"],
	47286 => ["Floor drying temp. 5","Supply temperature each period","°C","u8","1","15","70","40","R/W"],
	47287 => ["Floor drying temp. 4","Supply temperature each period","°C","u8","1","15","70","45","R/W"],
	47288 => ["Floor drying temp. 3","Supply temperature each period","°C","u8","1","15","70","40","R/W"],
	47289 => ["Floor drying temp. 2","Supply temperature each period","°C","u8","1","15","70","30","R/W"],
	47290 => ["Floor drying temp. 1","Supply temperature each period","°C","u8","1","15","70","20","R/W"],
	47294 => ["Use airflow defrost","If reduced airflow should start defrost","","u8","1","0","0","0","R/W"],
	47295 => ["Airflow reduction trig","How much the airflow is allowed to be reduced before a defrost is trigged","%","u8","1","0","0","0","R/W"],
	47296 => ["Airflow defrost done","How much the airflow has to raise before a defrost is ended","%","u8","1","0","0","0","R/W"],
	47297 => ["Initiate inverter","Start initiation process of the inverter","","u8","1","0","0","0","R/W"],
	47298 => ["Force inverter init","Force inverter initiation process of the inverter","","u8","1","0","0","0","R/W"],
	47299 => ["Min time defrost","Minimum duration of the defrost","min","u8","1","0","0","0","R/W"],
	47300 => ["DOT","Dimensioning outdoor temperature","°C","s16","10","-400","200","-180","R/W"],
	47301 => ["delta T at DOT","Delta T (BT12-BT3)at dimensioning outdoor temperature","°C","s16","10","0","250","100","R/W"],
	47302 => ["Climate system 2 accessory","Activates the climate system 2 accessory 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47303 => ["Climate system 3 accessory","Activates the climate system 3 accessory 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47304 => ["Climate system 4 accessory","Activates the climate system 4 accessory 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47305 => ["Climate system 4 mixing valve amp.","Mixing valve amplification for extra climate systems","","s8","10","1","100","10","R/W"],
	47306 => ["Climate system 3 mixing valve amp.","Mixing valve amplification for extra climate systems","","s8","10","1","100","10","R/W"],
	47307 => ["Climate system 2 mixing valve amp.","Mixing valve amplification for extra climate systems","","s8","10","1","100","10","R/W"],
	47308 => ["Climate system 4 shunt wait","Wait time between changes of the shunt in extra climate systems","secs","s16","10","10","300","30","R/W"],
	47309 => ["Climate system 3 shunt wait","Wait time between changes of the shunt in extra climate systems","secs","s16","10","10","300","30","R/W"],
	47310 => ["Climate system 2 shunt wait","Wait time between changes of the shunt in extra climate systems","secs","s16","10","10","300","30","R/W"],
	47317 => ["Shunt controlled add. accessory","Activates the shunt controlled addition accessory 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47318 => ["Shunt controlled add. min. temp.","","°C","s8","1","5","90","55","R/W"],
	47319 => ["Shunt controlled add. min. runtime","","hrs","u8","1","0","48","12","R/W"],
	47320 => ["Shunt controlled add. mixing valve amp.","Mixing valve amplification for shunt controlled add.","","s8","10","1","100","10","R/W"],
	47321 => ["Shunt controlled add. mixing valve wait","Wait time between changes of the shunt in shunt controlled add.","secs","s16","1","10","300","30","R/W"],
	47352 => ["SMS40 accessory","Activates the SMS40 accessory","","u8","1","0","1","0","R/W"],
	47370 => ["Allow Additive Heating","Whether to allow additive heating (only valid for operational mode Manual)","","u8","1","0","1","1","R/W"],
	47371 => ["Allow Heating","Whether to allow heating (only valid for operational mode Manual or Add. heat only)","","u8","1","0","1","1","R/W"],
	47372 => ["Allow Cooling","Whether to allow cooling (only valid for operational mode Manual or Add. heat only)","","u8","1","0","1","1","R/W"],
	47378 => ["Max diff. comp.","","°C","s16","10","10","250","100","R/W"],
	47379 => ["Max diff. add.","","°C","s16","10","10","240","70","R/W"],
	47384 => ["Date format"," 1=DD-MM-YY 2=YY-MM-DD","","u8","1","1","2","1","R/W"],
	47385 => ["Time format"," 12=12 hours 24=24 Hours","","u8","1","12","24","24","R/W"],
	47387 => ["HW production","Activates hot water production where applicable 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47388 => ["Alarm lower room temp.","Lowers the room temperature during red light alarms to notify the occupants of the building that something is the matter 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47389 => ["Alarm lower HW temp.","Lowers the hot water temperature during red light alarms to notify the occupants of the building that something is the matter 0=Off 1=On","","u8","1","0","1","1","R/W"],
	47391 => ["Use room sensor S4","When activated the system uses the room sensor 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47392 => ["Use room sensor S3","When activated the system uses the room sensor 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47393 => ["Use room sensor S2","When activated the system uses the room sensor 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47394 => ["Use room sensor S1","When activated the system uses the room sensor 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47395 => ["Room sensor setpoint S4","Sets the room temperature setpoint for the system","°C","s16","10","50","300","200","R/W"],
	47396 => ["Room sensor setpoint S3","Sets the room temperature setpoint for the system","°C","s16","10","50","300","200","R/W"],
	47397 => ["Room sensor setpoint S2","Sets the room temperature setpoint for the system","°C","s16","10","50","300","200","R/W"],
	47398 => ["Room sensor setpoint S1","Sets the room temperature setpoint for the system","°C","s16","10","50","300","200","R/W"],
	47399 => ["Room sensor factor S4","Setting of how much the difference between set and actual room temperature should affect the supply temperature.","","u8","10","0","60","20","R/W"],
	47400 => ["Room sensor factor S3","Setting of how much the difference between set and actual room temperature should affect the supply temperature.","","u8","10","0","60","20","R/W"],
	47401 => ["Room sensor factor S2","Setting of how much the difference between set and actual room temperature should affect the supply temperature.","","u8","10","0","60","20","R/W"],
	47402 => ["Room sensor factor S1","Setting of how much the difference between set and actual room temperature should affect the supply temperature.","","u8","10","0","60","20","R/W"],
	47415 => ["Speed circ.pump Pool","","%","u8","1","0","100","70","R/W"],
	47417 => ["Speed circ.pump Cooling","","%","u8","1","0","100","70","R/W"],
	47442 => ["preset flow clim. sys.","Preset flow setting for climate system. 0 = manual setting, 1 = radiator, 2 = floor heating, 3 = radiator + floor heating.","","u8","1","0","3","1","R/W"],
	47473 => ["Max time defrost","Maximum duration of the defrost","min","u8","1","0","0","0","R/W"],
	47537 => ["Night cooling","If the fan should have a higher speed when there is a high room temp and a low outdoor temp. 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47538 => ["Start room temp. night cooling","","°C","u8","1","20","30","25","R/W"],
	47539 => ["Night Cooling Min. diff.","Minimum difference between room temp and outdoor temp to start night cooling","°C","u8","1","3","10","6","R/W"],
	47555 => ["DEW accessory","Activates the DEW accessory","","u8","1","0","1","0","R/W"],
	47570 => ["Operational mode","The operational mode of the heat pump 0=Auto 1=Manual 2=Add. heat only","","u8","1","0","0","0","R/W"],
	48134 => ["Operational mode charge pump","","","u8","1","10","20","20","R/W"],
	48158 => ["SAM supply air curve: outdoor temp T3","The supply air curve is defined by 3 supply air temperatures at 3 different outdoor temperatures T1, T2 and T3.","°C","s16","10","-400","200","150","R/W"],
	48159 => ["SAM supply air curve: outdoor temp T2","The supply air curve is defined by 3 supply air temperatures at 3 different outdoor temperatures T1, T2 and T3.","°C","s16","10","-390","190","0","R/W"],
	48160 => ["SAM supply air curve: outdoor temp T1","The supply air curve is defined by 3 supply air temperatures at 3 different outdoor temperatures T1, T2 and T3.","°C","s16","10","-400","200","-150","R/W"],
	48161 => ["SAM supply air curve: supply air temp at T3","The supply air curve is defined by 3 supply air temperatures at 3 different outdoor temperatures T1, T2 and T3.","°C","s16","10","160","520","220","R/W"],
	48162 => ["SAM supply air curve: supply air temp at T2","The supply air curve is defined by 3 supply air temperatures at 3 different outdoor temperatures T1, T2 and T3.","°C","s16","10","160","520","220","R/W"],
	48163 => ["SAM supply air curve: supply air temp at T1","The supply air curve is defined by 3 supply air temperatures at 3 different outdoor temperatures T1, T2 and T3.","°C","s16","10","160","520","220","R/W"],
	48201 => ["SCA accessory","Activates the SCA accessory","","u8","1","0","1","0","R/W"],
	);
	return $register{$input[0]}[$input[1]];
}

1;
=pod
=begin html

<a name="NIBE"></a>
<h3>NIBE</h3>
<ul>
  The NIBE module enables FHEM to communicate to NIBE heat pumps which are compatible to the modbus 40 module.</br>
  You can use for example the USB IR Read and write head from volkszaehler.org project.</br>
  <br><br>
</ul>

=end html
=cut
