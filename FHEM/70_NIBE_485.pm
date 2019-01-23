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

my %last_time = ();

sub NIBE_485_Initialize ($)
{
#(initialisiert das Modul und gibt de Namen der zusätzlichen Funktionen bekannt)

	# Load the DevIo Module of FHEM
	require "$attr{global}{modpath}/FHEM/DevIo.pm";
	
	# Read the parameters into $hash
	my ($hash) = @_;
	
	# Define the functions
	$hash->{ReadFn}     = "NIBE_485_Read";				# Read serial data
	$hash->{ReadyFn}    = "NIBE_485_Ready"; 			# ????
	$hash->{DefFn}      = "NIBE_485_Define";			# Define the device
	$hash->{UndefFn}    = "NIBE_485_Undef"; 			# Delete the device
	$hash->{GetFn}      = "NIBE_485_Get";				# Manually get data
	$hash->{ParseFn}    = "NIBE_485_Parse";				# Parse function - Only used for two step modules?
	$hash->{StateFn}    = "NIBE_485_SetState";			# Only used for setting the state of the module?
	$hash->{WriteFn}    = "NIBE_485_Write";      # Write data from logical module
	# $hash->{Match}      = ".*";						# ???????????????????
	$hash->{AttrList}   = "do_not_notify:1,0 ".
	       "dummy:1,0 disable:0,1 interval";		                # Define the possible Attributes
	$hash->{ShutdownFn} = "NIBE_485_Shutdown";			# ????
}

sub NIBE_485_Define ($)
{
	#(wird beim define aufgerufen)
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	return "wrong syntax: 'define <name> NIBE_485 <devicename>'"
	if(@a < 3);

	DevIo_CloseDev($hash);

	my $name = $a[0];
	my $dev = $a[2];
		
    $hash->{Clients} = ":NIBE:";
    my %matchList = ( "1:NIBE" => ".*" );
    $hash->{MatchList} = \%matchList;

    if($dev =~ m/none/) {
      Log3 $name, 1, "$name device is none, commands will be echoed only";
      $attr{$name}{dummy} = 1;
      $hash->{STATE} = "dummy";
      return undef;
    } elsif ($dev !~ m/@/ && $dev !~ m/:/) {
        # set baudrate to 9600 if not defined
        $dev .= "\@9600";
    }

	$hash->{DeviceName}   = $dev;
	$hash->{helper}{register} = [()];
  $hash->{helper}{register_write} = [()];

	Log3 $hash, 5, "NIBE_485: Defined";

	my $ret = DevIo_OpenDev($hash, 0, "NIBE_485_DoInit");

	return $ret;
}

sub NIBE_485_SetState($$$$) {
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

sub NIBE_485_Clear($) {
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

sub NIBE_485_DoInit($) {
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

	NIBE_485_Clear($hash); 

	return undef; 
}

sub NIBE_485_Undef ($) {
#(wird beim Löschen einer Geräteinstanz aufgerufen - Gegenteil zu define)
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};
	delete $hash->{FD};
	$hash->{STATE}='close';
	$hash->{NIBE}->close() if($hash->{NIBE});
	Log3 $hash, 0, "NIBE_485: Undefined";
	return undef;
}

sub NIBE_485_Shutdown($) {
  my ($hash) = @_;
  DevIo_CloseDev($hash); 
  return undef;
}

sub NIBE_485_Disconnected($) {
  my $hash = shift;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
 	
  return if(!defined($hash->{FD})); # Already deleted
	
  DevIo_CloseDev($hash);
  Log3 $hash, 1, "NIBE_485: $dev disconnected, waiting to reappear";

  $readyfnlist{"$name.$dev"} = $hash; # Start polling
  $hash->{STATE} = "disconnected";
	
  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");
} 

sub NIBE_485_Set ($)
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

sub NIBE_485_Get ($) {
#(wird beim Befehl get aufgerufen um Daten vom Gerät abzufragen)

#Just a short queue to print out the content of the hash.
	my ($hash) = @_;
	my $name = $hash->{NAME};
	while ( my($k,$v) = each %$hash ) {
		if (defined($v)) {
			Log3 $name, 5, "$k => $v";
		}
	}
}

#sub NIBE_485_Attr ($) {
#(wird beim Befehl attr aufgerufen um beispielsweise Werte zu prüfen)
#}

sub NIBE_485_Read ($)
{
#(wird vom globalen select aufgerufen, falls Daten zur Verfuegung stehen)
#$hash->{READINGS}{state}
    my $hash = shift;
    my $name = $hash->{NAME};
    my $buf  = DevIo_SimpleRead($hash);

	if(!defined($buf) || length($buf) == 0) {
		NIBE_485_Disconnected($hash);
		return "";
	}

    Log3 $name, 5, "$name: raw read: " . unpack ('H*', $buf);

    $hash->{helper}{buffer} .= unpack ('H*', $buf);
    while ($hash->{helper}{buffer} =~ m/5c(00|41)(.{2})(.{2})(.{2}).*/) {
        my $sender  = $1; 
        my $address = $2;
        my $command = $3;
        my $length  = hex($4);

        my $offset = index($hash->{helper}{buffer}, "5c$sender");
        if ($offset > 0) {
            # shift buffer till start of first frame
            $hash->{helper}{buffer} = substr($hash->{helper}{buffer}, $offset);
            Log3 $name, 4, "$name: drop $offset characters";
        }

        # check if not enough data yet
        last if (length($hash->{helper}{buffer})/2 < $length + 6);

        if ($sender eq "00" and $address eq "20") {
          if ($command eq "69" and scalar @{$hash->{helper}{register}} > 0) {
  
            my $reg = shift(@{$hash->{helper}{register}});
            DevIo_SimpleWrite($hash, $reg, 1);
            Log3 $name, 5, "$name: raw write: $reg";
            
          } elsif ($command eq "6b" and scalar @{$hash->{helper}{register_write}} > 0) {
  
            my $reg = shift(@{$hash->{helper}{register_write}});
            DevIo_SimpleWrite($hash, $reg, 1);
            Log3 $name, 5, "$name: raw write: $reg";
            
          } else {
            # Send the ACK byte.
    
            # Here we need to implement the CRC check and send a 0x15 if CRC was incorrect.
            # Happens sometimes on my side (Matthias)
  
            DevIo_SimpleWrite($hash, '06', 1);
    
            # Parse
            if ($length > 0) {
                my $last = $last_time{$command};
                $last = 1 if (!defined($last));
                if ($command eq "6a" or time() - $last >= AttrVal($name, "interval", 30)) {
                    $last_time{$command} = time();
                    my $msg = substr($hash->{helper}{buffer}, 0, ($length+6)*2);
                    NIBE_485_Parse($hash, $name, $msg);
                }
            }
          }
        }

        $hash->{helper}{buffer} = substr($hash->{helper}{buffer}, ($length+6)*2);            
    }  
}

sub  NIBE_485_Parse {
#(wird bei zweistufigen Modulen vom Dispatch aufgerufen und muss hier noch beschrieben werden)
    my ($hash, $name, $rmsg) = @_;
  
    $hash->{"${name}_MSGCNT"}++;
    $hash->{"${name}_TIME"} = TimeNow();
    $hash->{RAWMSG} = $rmsg;
  
    my %addvals = (RAWMSG => $rmsg);
    Dispatch($hash, $rmsg, \%addvals);
}

sub NIBE_485_Ready 
{
#(wird unter windows als ReadFn-Erstatz benoetigt bzw. um zu pruefen, ob ein Geraet wieder eingesteckt ist)
  my ($hash) = @_;
  return DevIo_OpenDev($hash, 0, "NIBE_485_DoInit")
	if($hash->{STATE} eq "disconnected");
}

sub NIBE_485_Write($$$) {
  my ( $hash, $opt, $arg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: Request input $opt $arg";

  if ($opt eq "read") {
    foreach my $command (split(",", $arg)) {
      push(@{$hash->{helper}{register}}, $command);
      Log3 $name, 4, "$name: Read command $command";
    }
  } elsif ($opt eq "write") {
    push(@{$hash->{helper}{register_write}}, $arg);
    Log3 $name, 4, "$name: Write command $arg";
  }

  return;
}

#NIBE_485_Notify (falls man benachrichtigt werden will)
#NIBE_485_Rename (falls ein Gerät umbenannt wird)

1;
=pod
=begin html

<a name="NIBE_485"></a>
<h3>NIBE_485</h3>
<ul>
  The NIBE 485 module enables communication between FHEM and NIBE heat pumps.
  The FHEM module simulates a NIBE MODBUS 40 communication module.
  The connection between FHEM and heat pump is implemented by using communication standard RS485.
  For further information how to install connection consult NIBE MODBUS 40 installer manual.
  <br>
  This module is a physical module for direct communication to NIBE heat pumps.
  The description of logical module <a href="#NIBE">NIBE</a>
  contains further information including an example configuration.
  <br><br>
  
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; NIBE_485 &lt;devicename&gt;</code>
    <br><br>
    Devicename has to be <code>none</code> if used by <a href="#FHEM2FHEM">FHEM2FHEM</a> as dummy. 
    <br><br>
  </ul>
  <a name="NIBE_485attr"></a>
  <b>Attributes</b> 
  <ul><b>dummy</b>
    <ul>can be used to define as RAW device using <a href="#FHEM2FHEM">FHEM2FHEM</a></ul>
  </ul>
</ul>

=end html
=begin html_DE

<a name="NIBE_485"></a>
<h3>NIBE_485</h3>
<ul>
  Das NIBE 485 Modul ermöglicht die Kommunikation von FHEM mit einer NIBE Wärmepumpe.
  Dabei wird durch das FHEM Modul ein NIBE MODBUS 40 Gerät simuliert.
  Für die Verbindung zwischen FHEM und der Wärmepumpe wird der Kommunikationsstandard RS485 genutzt.
  Der Anschluß an der Wärmepumpe erfolgt gemäß des Installateurhandbuches des NIBE MODBUS 40.
  <br>
  Das ist ein physisches Modul zur direkten Kommunikation mit einer NIBE Wärmepumpe.
  Weitere Informationen mit Beispielkonfiguration sind beim logischen Modul <a href="#NIBE">NIBE</a> zu finden.
  <br><br>
  
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; NIBE_485 &lt;devicename&gt;</code>
    <br><br>
    Bei Benutzung als <a href="#FHEM2FHEM">FHEM2FHEM</a> Dummy muss als Gerätename <code>none</code> verwendet werden.
    <br><br>
  </ul>
  <a name="NIBE_485attr"></a>
  <b>Attributes</b> 
  <ul><b>dummy</b>
    <ul>kann gesetzt werden, um das Gerät als <a href="#FHEM2FHEM">FHEM2FHEM</a> RAW-Objekt zu benutzen</ul>
  </ul>
</ul>

=end html_DE
=cut
