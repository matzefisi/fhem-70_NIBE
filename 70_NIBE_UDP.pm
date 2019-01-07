# $Id: 70_NIBE_UDP.pm 001 2018-01-07 12:34:56Z VuffiRaa$
##############################################################################
#
#     70_NIBE_UDP.pm
#     Module to read and write messages to NIBE heat pumps via UDP / NibeGW
#     Supported models: F750, F1245, ....
#
#     Copyright by Ulf von Mersewsky
#     e-mail: umersewsky at gmail.com
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#
# Version: 0.0.1
#
##############################################################################

package main;

use strict;
use warnings;

sub NIBE_UDP_Initialize ($) {
	my ($hash) = @_;
	
	# Define the functions
	$hash->{ReadFn}     = "NIBE_UDP::Read";				# Read serial data
	$hash->{ReadyFn}    = "NIBE_UDP::Ready"; 			# ????
	$hash->{DefFn}      = "NIBE_UDP::Define";			# Define the device
	$hash->{UndefFn}    = "NIBE_UDP::Undef"; 			# Delete the device
	$hash->{GetFn}      = "NIBE_UDP::Get";				# Manually get data
	$hash->{ParseFn}    = "NIBE_UDP::Parse";		  # Parse function - Only used for two step modules?
	$hash->{WriteFn}    = "NIBE_UDP::Write";      # Write data from logical module
	$hash->{AttrList}   = "do_not_notify:1,0 ".
	                      "disable:0,1 interval"; # Define the possible Attributes
	$hash->{ShutdownFn} = "NIBE_UDP::Shutdown";	  # ????
}

package NIBE_UDP;

use strict;
use warnings;
use POSIX;

use GPUtils qw(:all);  # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt

use Socket;

require "DevIo.pm";

## Import der FHEM Funktionen
BEGIN {
    GP_Import(qw(
        AttrVal
        Dispatch
        Log3
        TimeNow
    ))
};

my %last_time = ();


sub Define($) {
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	return "wrong syntax: 'define <name> NIBE_UDP <address> [<port>] [<read_port>] [<write_port>'" if(@a < 3);

	::DevIo_CloseDev($hash);

	my $name = $a[0];
	my $addr = $a[2];
	my $port = defined($a[3]) ? $a[3] : "9999";
	my $rport = defined($a[4]) ? $a[4] : "10000";
	my $wport = defined($a[5]) ? $a[5] : "10001";
		
  $hash->{Clients} = ":NIBE:";
  my %matchList = ( "1:NIBE" => ".*" );
  $hash->{MatchList} = \%matchList;

 	$hash->{DeviceName}   = "$addr:$port";
 	$hash->{ReadCmdPort}  = $rport;
 	$hash->{WriteCmdPort} = $wport;
	$hash->{helper}{register} = [()];
  $hash->{helper}{register_write} = [()];

	Log3($hash, 5, "NIBE_UDP: Defined");

	my $ret = OpenDev($hash, 0);

	return $ret;
}

sub Undef($) {
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};

	delete $hash->{FD};
	$hash->{STATE}='close';

  return if (!$hash->{CD});

  close($hash->{CD});
  delete($hash->{CD});
	Log3($hash, 0, "NIBE_UDP: Undefined");

	return undef;
}

sub Shutdown($) {
  my ($hash) = @_;

  ::DevIo_CloseDev($hash); 

  return undef;
}

sub Ready {
  my ($hash) = @_;
  return OpenDev($hash, 0) if($hash->{STATE} eq "disconnected");
}

sub OpenDev($$) {
  my ($hash, $reopen) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $po;
  my $nextOpenDelay = ($hash->{nextOpenDelay} ? $hash->{nextOpenDelay} : 60);

  # Call initFn
  # if fails: disconnect, schedule the next polltime for reopen
  # if ok: log message, trigger CONNECTED on reopen
  my $doTailWork = sub {
    ::DevIo_setStates($hash, "opened");

    my $hadFD = defined($hash->{FD});
    my $l = $hash->{devioLoglevel}; # Forum #61970
    if($reopen) {
      Log3($name, ($l ? $l:1), "$dev reappeared ($name)");
    } else {
      Log3($name, ($l ? $l:3), "$name device opened") if(!$hash->{DevioText});
    }

    ::DoTrigger($name, "CONNECTED") if($reopen);
    
    return undef;
  };
  
  if($hash->{DevIoJustClosed}) {
    delete $hash->{DevIoJustClosed};
    return undef;
  }

  $hash->{PARTIAL} = "";
  Log3($name, 3, ($hash->{DevioText} ? $hash->{DevioText} : "Opening").
       " $name device $dev") if(!$reopen);

  if($dev =~ m/^(.+):([0-9]+)$/) {       # host:port

    my $addr = $1;
    my $port = $2;

    # This part is called every time the timeout (5sec) is expired _OR_
    # somebody is communicating over another TCP connection. As the connect
    # for non-existent devices has a delay of 3 sec, we are sitting all the
    # time in this connect. NEXT_OPEN tries to avoid this problem.
    if($hash->{NEXT_OPEN} && time() < $hash->{NEXT_OPEN}) {
      return undef;
    }

    delete($::readyfnlist{"$name.$dev"});
    my $timeout = $hash->{TIMEOUT} ? $hash->{TIMEOUT} : 3;

    
    # Do common TCP/IP "afterwork":
    # if connected: set keepalive, fill selectlist, FD, TCPDev.
    # if not: report the error and schedule reconnect
    my $doTcpTail = sub($) {
      my ($conn) = @_;
      if($conn) {
        delete($hash->{NEXT_OPEN});
       } else {
        Log3($name, 1, "$name: Can't connect to $dev: $!") if(!$reopen && $!);
        $::readyfnlist{"$name.$dev"} = $hash;
        ::DevIo_setStates($hash, "disconnected");
        $hash->{NEXT_OPEN} = time() + $nextOpenDelay;
        return 0;
      }

      $hash->{FD} = $conn->fileno();
      $hash->{CD} = $conn;
      $::selectlist{"$name.$dev"} = $hash;
      return 1;
    };

    my $conn = IO::Socket::INET ->new(
        LocalPort => $port,
        Proto => 'udp',
        Blocking => 0,
        Timeout => $timeout);
    return "" if(!&$doTcpTail($conn)); # no callback: no doCb

  }

  return &$doTailWork();
}

sub Disconnected($) {
  my $hash = shift;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
 	
  return if(!defined($hash->{FD})); # Already deleted
	
  close($hash->{CD});
  delete($hash->{CD});
  ::DevIo_CloseDev($hash);
  Log3($hash, 1, "NIBE_UDP: $dev disconnected, waiting to reappear");

  $::readyfnlist{"$name.$dev"} = $hash; # Start polling
  $hash->{STATE} = "disconnected";
	
  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(0.5);

  ::DoTrigger($name, "DISCONNECTED");
} 

sub Get($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

  #Just a short queue to print out the content of the hash.
	while ( my($k,$v) = each %$hash ) {
    Log3($name, 5, "$k => $v") if (defined($v));
	}
}

sub Read($) {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $buf;
  
  $hash->{CD}->recv($buf, 512);

	if(!defined($buf) || length($buf) == 0) {
		Disconnected($hash);
		return "";
	}

  Log3($name, 5, "$name: raw read: " . unpack ('H*', $buf));

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
      Log3($name, 4, "$name: drop $offset characters");
    }

    # check if not enough data yet
    last if (length($hash->{helper}{buffer})/2 < $length + 6);

    if ($sender eq "00" and $address eq "20") {
      # Parse
      if ($length > 0) {
          my $last = $last_time{$command};
          $last = 1 if (!defined($last));
          if ($command eq "6a" or time() - $last >= AttrVal($name, "interval", 30)) {
              $last_time{$command} = time();
              my $msg = substr($hash->{helper}{buffer}, 0, ($length+6)*2);
              Parse($hash, $name, $msg);
          }
        }
      }

      $hash->{helper}{buffer} = substr($hash->{helper}{buffer}, ($length+6)*2);            
    }  
}

sub  Parse {
  my ($hash, $name, $rmsg) = @_;

  $hash->{"${name}_MSGCNT"}++;
  $hash->{"${name}_TIME"} = TimeNow();
  $hash->{RAWMSG} = $rmsg;

  my %addvals = (RAWMSG => $rmsg);
  Dispatch($hash, $rmsg, \%addvals);
}

sub Write($$$) {
  my ( $hash, $opt, $arg) = @_;
  my $name = $hash->{NAME};
  my $dev  = $hash->{DeviceName};
  my ($host,undef) = split(':', $dev);
  my $port = $opt eq "write" ? $hash->{WriteCmdPort} : $hash->{ReadCmdPort};

  Log3($name, 4, "$name: Request input $opt $arg");

  my $sock = IO::Socket::INET->new(
    PeerAddr => "$host:$port",
    Proto => 'udp',
    Timeout => 3);
  if ($sock) {
    Log3($name, 3, "$name: udp connection to $host:$port opened");
    if ($opt eq "read") {
      foreach my $command (split(",", $arg)) {
        Log3($name, 4, "$name: Read command $command");
        $sock->send($command);
      }
    } elsif ($opt eq "write") {
      push(@{$hash->{helper}{register_write}}, $arg);
      Log3($name, 4, "$name: Write command $arg");
    }
    close($sock);
  } else {
    Log3($name, 1, "$name: Can't connect to udp port $port: $!");
  }

  return;
}

1;
=pod
=begin html

<a name="NIBE_UDP"></a>
<h3>NIBE_UDP</h3>
<ul>
  The NIBE UDP module enables communication between FHEM and NIBE heat pumps.
  The FHEM module simulates a NIBE MODBUS 40 communication module.
  The connection between FHEM and heat pump is established via UDP communication provided by NibeGW.
  For further information how to install connection consult NIBE MODBUS 40 installer manual.
  <br>
  This module is a physical module for communication to NibeGW.
  The description of logical module <a href="#NIBE">NIBE</a>
  contains further information including an example configuration.
  <br><br>
  
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; NIBE_UDP &lt;devicename&gt;</code>
    <br><br>
  </ul>
</ul>

=end html
=begin html_DE

<a name="NIBE_UDP"></a>
<h3>NIBE_UDP</h3>
<ul>
  Das NIBE UDP Modul ermöglicht die Kommunikation von FHEM mit einer NIBE Wärmepumpe.
  Dabei wird durch das FHEM Modul ein NIBE MODBUS 40 Gerät simuliert.
  Für die Verbindung zwischen FHEM und der Wärmepumpe wird NibeGW benutzt. NibeGW liefert und verarbeitet Daten per UDP.
  Der Anschluß an der Wärmepumpe erfolgt gemäß des Installateurhandbuches des NIBE MODBUS 40.
  <br>
  Das ist ein physisches Modul zur Kommunikation mit NibeGW.
  Weitere Informationen mit Beispielkonfiguration sind beim logischen Modul <a href="#NIBE">NIBE</a> zu finden.
  <br><br>
  
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; NIBE_485 &lt;devicename&gt;</code>
    <br><br>
  </ul>
</ul>

=end html_DE
=cut
