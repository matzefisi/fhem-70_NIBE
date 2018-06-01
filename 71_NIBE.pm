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

use Scalar::Util qw(looks_like_number);

sub NIBE_Initialize ($)
{
#(initialisiert das Modul und gibt die Namen der zusätzlichen Funktionen bekannt)

	# Read the parameters into $hash
	my ($hash) = @_;
	
	# Define the functions
	$hash->{DefFn}      = "NIBE_Define";			# Define the device
	$hash->{UndefFn}    = "NIBE_Undef"; 			# Delete the device
  $hash->{SetFn}      = "NIBE_Set";
	$hash->{GetFn}      = "NIBE_Get";				# Manually get data
	$hash->{NotifyFn}   = "NIBE_Notify";
	$hash->{ParseFn}    = "NIBE_Parse";				# Parse function - Only used for two step modules?
	$hash->{Match}      = ".*";						# ???????????????????
	$hash->{AttrList}   = "IODev o_not_notify:1,0 ".
            "ignore:1,0 dummy:1,0 showtime:1,0 ".
            "modbusFile:textField ".
            "nibeFavorites:textField ".
            "$readingFnAttributes";		            # Define the possible Attributes
}

sub NIBE_Define ($)
{
  #(wird beim define aufgerufen)
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  return "wrong syntax: 'define <name> NIBE <devicename>'"
  if(@a < 2);
  
  my $name = $a[0];
  	
  $attr{$name}{"event-min-interval"} = ".*:30";
  
  $modules{NIBE}{defptr}{"default"} = $hash;
  AssignIoPort($hash);

  Log3 $hash, 5, "NIBE: Defined";

  $hash->{NOTIFYDEV} = "global";
  NIBE_LoadRegister($hash) if($init_done);
  
  return undef;
}

sub NIBE_Notify($$)
{
  my ($own_hash, $dev_hash) = @_;
  my $ownName = $own_hash->{NAME}; # own name / hash
 
  return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled
 
  my $devName = $dev_hash->{NAME}; # Device that created the events
  my $events = deviceEvents($dev_hash, 1);

  if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}))
  {
     NIBE_LoadRegister($own_hash);
  }
}

sub NIBE_Undef ($) {
#(wird beim Löschen einer Geräteinstanz aufgerufen - Gegenteil zu define)
    my ($hash, $arg) = @_; 
    # nothing to do
    return undef;
}

sub NIBE_Set ($)
{
# wird beim Befehl set aufgerufen um Daten an das Gerät zu senden
# We need this eventually later when we try to send messages to the heatpump.
# Usecase: Reduce ventilation speed when the wood stove is heating up

  my ( $hash, $name, $cmd, @a ) = @_;

  return "\"set $name\" needs at least one argument" unless(defined($cmd));

  Log3 $name, 5, "$name: called function NIBE_Set()";

  my $usage = "loadModbusFile:noArg register";
  foreach my $fav (split(" ", AttrVal($name, "nibeFavorites", ""))) {
    $usage .= " $fav" if (NIBE_CheckWriteMode($hash, NIBE_RegisterId($hash, $fav), 1));
  }
  
  if ($cmd eq "loadModbusFile") {
    NIBE_LoadRegister($hash);

  } elsif ($cmd eq "register") {
    return "No argument given" unless(defined($a[1]));

    my $register = $a[0];
    $register = NIBE_RegisterId($hash, $register) if ($register !~ m/^\d{5}$/);
    $register = NIBE_CheckWriteMode($hash, $register);

    if (defined($register)) {
      return "$a[1] is not a number" unless looks_like_number($a[1]);
      my $command = NIBE_WriteCommand($hash, $register, $a[1]);
      IOWrite($hash, "write", $command);
      NIBE_Get($hash, $name, $cmd, $register);
    }
    return undef;

  } elsif (defined($a[0]) and my $reg = NIBE_RegisterId($hash, $cmd)) {
    return "$a[0] is not a number" unless looks_like_number($a[0]);
    return "Register $cmd is not adjustable" unless NIBE_CheckWriteMode($hash, $reg);
    my $command = NIBE_WriteCommand($hash, $reg, $a[0]);
    IOWrite($hash, "write", $command);
    NIBE_Get($hash, $name, "register", $reg);
    
  } else {
    return $usage;
  }

	return 0;
}

sub NIBE_Get ($$@) {
#(wird beim Befehl get aufgerufen um Daten vom Gerät abzufragen)
	my ( $hash, $name, $opt, @args ) = @_;

  Log3 $name, 5, "$name: called function NIBE_Get()";

	
	if ($opt eq "readRegisters") {
    my $readList = "<html>";
    foreach my $reg ( sort(keys %{ $hash->{register} } ) ) {
      my $name = $hash->{register}{$reg}->{name};
      my $description = $hash->{register}{$reg}->{description};
      $readList .= "<b>$reg</b>: $name";
      $readList .= " - <em>$description</em>" if ($description ne "");
      $readList .= "<br>";
    }
	  $readList .= "</html>";
	  return $readList;

  } elsif ($opt eq "writeRegisters") {
    my $writeList = "<html>";
    foreach my $reg ( sort(keys %{ $hash->{register} } ) ) {
      if ($hash->{register}{$reg}->{mode} eq "R/W") {
        my $name = $hash->{register}{$reg}->{name};
        my $description = $hash->{register}{$reg}->{description};
        $writeList .= "<b>$reg</b>: $name";
        $writeList .= " - <em>$description</em>" if ($description ne "");
        $writeList .= "<br>";
      }
    }
    $writeList .= "</html>";
    return $writeList;

  } elsif ($opt eq "register") {
    return "argument is missing" if ( int(@args) < 1 );
    my @registers = ();
    my @commands = ();
    foreach my $arg (@args) {
      if ($arg =~ m/^\d{5}$/) {
        push(@registers, $arg);
        push(@commands, NIBE_ReadCommand($hash, $arg));
      } else {
        my $reg = NIBE_RegisterId($hash, $arg);
        push(@registers, $reg);
        push(@commands, NIBE_ReadCommand($hash, $reg)) if (defined($reg));
      }
    }
	  IOWrite($hash, "read", join(",", @commands)) if (@commands);
	  return join(",", @registers) . " requested, watch readings";

	} elsif (my $reg = NIBE_RegisterId($hash, $opt)) {
    IOWrite($hash, "read", NIBE_ReadCommand($hash, $reg));
    return "$reg requested, watch readings";
	}

	my $usage = "register readRegisters:noArg writeRegisters:noArg";
	foreach my $fav (split(" ", AttrVal($name, "nibeFavorites", ""))) {
	  $usage .= " $fav:noArg";
	}

  return "Unknown argument $opt, choose one of $usage";
}

sub NIBE_ReadCommand($$) {
  my ($hash, $reg) = @_;
  my $name = $hash->{NAME};
  my @a = ();

  push(@a, 'C0');
  push(@a, '69');
  push(@a, '02');
  my $r = sprintf("%04X", $reg);
  if ($r =~ /(.{2})(.{2})/) {
    push(@a, $2);
    push(@a, $1);
  }
  push(@a, NIBE_Checksum(@a));
  
  my $cmd = join('', @a);
  Log3 $name, 4, "$name: Read command: $cmd";
  return $cmd;
}

sub NIBE_WriteCommand($$$) {
  my ($hash, $reg, $value) = @_;
  my $name = $hash->{NAME};
  my $register = $hash->{register}{$reg};
  my @a = ();

  push(@a, 'C0');
  push(@a, '6B');
  push(@a, '06');
  my $r = sprintf("%04X", $reg);
  if ($r =~ /(.{2})(.{2})/) {
    push(@a, $2);
    push(@a, $1);
  }
  my $v = NIBE_HexValue($register->{type}, $value * $register->{factor});
  if ($v =~ /(.{2})(.{2})(.{2})(.{2})/) {
    push(@a, $4);
    push(@a, $3);
    push(@a, $2);
    push(@a, $1);
  }
  push(@a, NIBE_Checksum(@a));

  my $cmd = join('', @a);
  Log3 $name, 4, "$name: Write command: $cmd";
  return $cmd;
}

#sub NIBE_Attr ($) {
#(wird beim Befehl attr aufgerufen um beispielsweise Werte zu prüfen)
#}

sub NIBE_Parse ($$@) {
    my ($iodev, $msg, $srcCmd) = @_;
    my $ioname = $iodev->{NAME};

    if ($msg =~ m/^5c00(.{2})(.{2})(.{2}).*/) {
        my $address = $1;
        my $command = $2;
        my $length  = hex($3);
      
        Log3 $ioname, 5, "$ioname: parse $msg";
    
        my $hash = $modules{NIBE}{defptr}{"default"};
        if(!$hash) {
            Log3 $ioname, 3, "Unknown NIBE device, please define it";
            return "";
        }
        my $name = $hash->{NAME};

        
        # Calculate checksum
        my $checksum=0;
        for (my $j = 2; $j < $length+5; $j++) {
                $checksum = $checksum^hex(substr($msg, $j*2 ,2));
        }
        $checksum = 197 if ($checksum == 92); # 92 = 5c, 197 = c5
        Log3 $name, 5, "$name: Calculated checksum " . sprintf("%x", $checksum);

        # what we got so far
        Log3 $name, 5, "$name: HEAD: ".substr($msg,0,4)." ADDR: ".substr($msg,4,2)
                            ." CMD: ".substr($msg,6,2)." LEN: ".substr($msg,8,2)
                            ." CHK: ".substr($msg,length($msg)-2,2);
    
    
        if ($checksum==hex(substr($msg, length($msg)-2, 2))) {
            Log3 $name, 5, "$name: Checksum OK";

            # used as physical dummy - don't parse
            if (AttrVal($name, "ignore", "0") ne "0") {
                return "";
            }
    
            # Start populate the reading(s)
            readingsBeginUpdate($hash);

            # Check if we got a message with the command 68 
            # In this message we can expect 20 values from the heater which were defined with the help of ModbusManager
            if ($command eq "68") {
                my $j=5;
                while($j < $length+5) {
                  $j = NIBE_ParseRegister($hash, $msg, $j);
                }
            # Check if we got a message with the command 6a - request for single value
            } elsif ($command eq "6a") {
              NIBE_ParseSingleRegister($hash, $msg, 5);
            } elsif ($command eq "6c" and $msg eq "5c00206c01014c") {
              # ignore, seems to be a confirmation of an executed command
            } elsif ($command eq "6d" and substr($msg, 10, 2*$length) =~ m/(.{2})(.{4})(.*)/) {
                my $version = hex($2);
                my $product = pack('H*', $3);
                readingsBulkUpdate($hash, "sw_version", $version)
                        if ($version ne ReadingsVal($name, "sw_version", ""));
                readingsBulkUpdate($hash, "product", $product)
                        if ($product ne ReadingsVal($name, "product", ""));
                $hash->{MODEL} = $product;
            } else {
              Log3 $name, 3, "$name: other message $msg";
            }
            readingsEndUpdate($hash, 1);
            return $name;
        } else {
            Log3 $name, 4, "$name: Checksum not OK";
            Log3 $name, 4, "$name: $msg";
        }
    }
    return "";
}

sub NIBE_ParseRegister($$$) {
  my ($hash, $msg, $j) = @_;
  my $name = $hash->{NAME};

  my $register = "";
  for ( my $i = 2 ; $i > 0 ; $i-- ) {
    my $byte = substr( $msg, $j++ * 2, 2 );
    $register = $byte . $register;

    # remove escaping of 0x5c
    if ( $byte eq "5c" ) {
      $j++ if ( substr( $msg, $j * 2, 2 ) eq "5c" );
    }
  }
  if ( $register ne "" and $register ne "ffff" ) {

    # Getting the register name
    my $regHash = $hash->{register}{ hex($register) };
    my $reading = $regHash->{name};

    # Calculating the actual value
    if ( defined($reading) ) {
      Log3 $name, 5, "$name: Found register $reading";

      my $valuetype = $regHash->{type};
      my $factor    = $regHash->{factor};
      my $value     = "";

      for ( my $i = 2 ; $i > 0 ; $i-- ) {
        my $byte = substr( $msg, $j++ * 2, 2 );
        $value = $byte . $value;

        # remove escaping of 0x5c
        if ( $byte eq "5c" ) {
          $j++ if ( substr( $msg, $j * 2, 2 ) eq "5c" );
        }
      }

      # value type *32 uses next register for full value
      if ( $valuetype =~ m/[su]32/ ) {
        my $next_register = "";
        my $has_escaping  = 0;
        for ( my $i = 2 ; $i > 0 ; $i-- ) {
          my $byte = substr( $msg, $j++ * 2, 2 );
          $next_register = $byte . $next_register;

          # remove escaping of 0x5c
          if ( $byte eq "5c" ) {
            $j++ if ( substr( $msg, $j * 2, 2 ) eq "5c" );
            $has_escaping++;
          }
        }

        if ( $next_register ne ""
          and hex($next_register) - hex($register) == 1 )
        {
          for ( my $i = 2 ; $i > 0 ; $i-- ) {
            my $byte = substr( $msg, $j++ * 2, 2 );
            $value = $byte . $value;

            # remove escaping of 0x5c
            if ( $byte eq "5c" ) {
              $j++ if ( substr( $msg, $j * 2, 2 ) eq "5c" );
            }
          }

        }
        else {
          # revert parsing of next_register
          $j -= 2;
          $j-- if ($has_escaping);
        }
      }

      if ( $valuetype =~ m/^s/ and $value =~ m/^80+$/ ) {
        Log3 $name, 3, "$name: Skip initial value of register $reading";
      }
      elsif ( $value ne "" ) {
        my $reading_value =
          NIBE_NormalizedValue( $valuetype, $value ) / $factor;
        Log3 $name, 5, "$name: Value $value normalized $reading_value";
        readingsBulkUpdate( $hash, $reading, $reading_value )
          if ( $reading_value ne ReadingsVal( $name, $reading, "" ) );
        NIBE_CheckSetState( $hash, hex($register), $reading_value );
      }
    }
    else {
      Log3 $name, 3, "$name: Register " . hex($register) . " not defined";
      Log3 $name, 4, "$name: $msg";
    }
  }
  else {
    # skip value 0000 of register ffff
    $j += 2;
  }
  
  return $j;
}

sub NIBE_ParseSingleRegister($$$) {
  my ($hash, $msg, $j) = @_;
  my $name = $hash->{NAME};

  my $register = "";
  for ( my $i = 2 ; $i > 0 ; $i-- ) {
    my $byte = substr( $msg, $j++ * 2, 2 );
    $register = $byte . $register;

    # remove escaping of 0x5c
    if ( $byte eq "5c" ) {
      $j++ if ( substr( $msg, $j * 2, 2 ) eq "5c" );
    }
  }
  if ( $register ne "" and $register ne "ffff" ) {

    # Getting the register name
    my $regHash = $hash->{register}{ hex($register) };
    my $reading = $regHash->{name};

    # Calculating the actual value
    if ( defined($reading) ) {
      Log3 $name, 5, "$name: Found register $reading";

      my $valuetype = $regHash->{type};
      my $factor    = $regHash->{factor};
      my $value     = "";

      for ( my $i = 2 ; $i > 0 ; $i-- ) {
        my $byte = substr( $msg, $j++ * 2, 2 );
        $value = $byte . $value;

        # remove escaping of 0x5c
        if ( $byte eq "5c" ) {
          $j++ if ( substr( $msg, $j * 2, 2 ) eq "5c" );
        }
      }

      # value type *32
      if ( $valuetype =~ m/[su]32/ ) {
        for ( my $i = 2 ; $i > 0 ; $i-- ) {
          my $byte = substr( $msg, $j++ * 2, 2 );
          $value = $byte . $value;

          # remove escaping of 0x5c
          if ( $byte eq "5c" ) {
            $j++ if ( substr( $msg, $j * 2, 2 ) eq "5c" );
          }
        }
      }

      if ( $valuetype =~ m/^s/ and $value =~ m/^80+$/ ) {
        Log3 $name, 3, "$name: Skip initial value of register $reading";
      }
      elsif ( $value ne "" ) {
        my $reading_value =
          NIBE_NormalizedValue( $valuetype, $value ) / $factor;
        Log3 $name, 5, "$name: Value $value normalized $reading_value";
        readingsBulkUpdate( $hash, $reading, $reading_value )
          if ( $reading_value ne ReadingsVal( $name, $reading, "" ) );
        NIBE_CheckSetState( $hash, hex($register), $reading_value );
      }
    }
    else {
      Log3 $name, 3, "$name: Register " . hex($register) . " not defined";
      Log3 $name, 4, "$name: $msg";
    }
  }
}

sub NIBE_NormalizedValue($$) {
	# Helper for normalizing the value
	# s8, s16, s32, u8, u16, u32
	my ($type, $value) = @_;

	if ($type eq "s8") {
    return 0 if $value !~ /^(00)?[0-9A-Fa-f]{1,2}$/;
		my $num = hex($value);
		return $num >> 7 ? $num - 2 ** 8 : $num;

	} elsif ($type eq "s16") {
		return 0 if $value !~ /^[0-9A-Fa-f]{1,4}$/;
		my $num = hex($value);
		return $num >> 15 ? $num - 2 ** 16 : $num;

	}	elsif ($type eq "s32") {
		return 0 if $value !~ /^[0-9A-Fa-f]{1,8}$/;
		my $num = hex($value);
		return $num >> 31 ? $num - 2 ** 32 : $num;

	}	else {
		# Lazy replacement for u8 -> u32
		return hex($value);
	}
}

sub NIBE_HexValue($$) {
  # Helper for calculate hexadecimal value
  # s8, s16, s32, u8, u16, u32
  my ($type, $value) = @_;

  my $num = $value;
  if ($value < 0) {
    $num = $value + (1 << 8)  if ($type eq "s8");
    $num = $value + (1 << 16) if ($type eq "s16");
    $num = $value + (1 << 32) if ($type eq "s32");
  } 
  return sprintf("%08X", $num);
}

sub NIBE_Checksum(@) {
  my @a = @_;

  my $c = pack( 'h*', '00' );
  foreach my $h (@a) {
    $c ^= pack( 'h*', $h );
  }
  my $checksum = unpack( 'h*', $c );
  $checksum = 'c5' if ( $checksum eq '5c' );

  return $checksum;
}

sub NIBE_CheckSetState($$$) {
    my ($hash, $register, $value) = @_;
    my $name = $hash->{NAME};

    # status binary code
    # 2⁰ - compressor
    # 2¹ - circulation pump
    # 2² - brine pump
    # 2³ - shuttle valve, climate system/water heater
    my %status = (
        2  => "standby",
        6  => "start/stop heating",
        7  => "heating operation",
        8  => "hot water standby",
        10 => "heat transfer",
        14 => "start/stop hot water",
        15 => "hot water regeneration",
    );

    # PCA-Base_Relays
    if ($register eq "43513" or $register eq "43514") {
        my $state = $status{$value};
        $state = $value if (!defined($state));
        readingsBulkUpdate($hash, "state", $state)
                if ($state ne ReadingsVal($name, "state", ""));
    }
}

sub NIBE_CheckWriteMode($$;$) {
  my ($hash, $register, $silent) = @_;
  my $name = $hash->{NAME};
  
  return undef if (!defined($hash->{register}));

  my $reg = $hash->{register}{$register};
  if (defined($reg)) {
    return $register if ($reg->{mode} eq "R/W");
    Log3 $name, 3, "$name: Register $register is not adjustable" unless $silent;
  } else {
    Log3 $name, 3, "$name: Register $register not found";
  }
  return undef;
}

sub NIBE_RegisterId($$) {
  my ($hash, $register) = @_;
  my $name = $hash->{NAME};
  
  return undef if ($register eq "?" or !defined($hash->{register}));

  keys %{$hash->{register}}; #reset iterator used by each
  while (my ($key, $value) = each (%{$hash->{register}})) {
    return $key if ($value->{name} eq $register);
  }
  
  Log3 $name, 3, "$name: Register $register not found";
  return undef;
}

sub NIBE_LoadRegister($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  return undef if (AttrNum($name, "ignore", 0) == 1);

  my $file = AttrVal($name, "modbusFile", "");
  $file = $attr{global}{modpath} . "/export.csv" if ($file eq "");

  Log3 $name, 4, "$name: Load modbus file $file";
  my ($err, @register) = FileRead("$file");
  if ($err) {
    Log3 $name, 2, "$name: Load modbus file failed: $err";
    return undef;
  }
  
  # remove header lines
  shift(@register) for(1..5);
  
  # empty register hash
  $hash->{register} = ();

  foreach my $line (@register) {
    my @field = split(';', $line);
    my $offset = 0;
    my $name;
    my $description;
    if ($field[0] =~ /^"(.*)"$/) {
      $name = $1;
    } elsif ($field[0] =~ /^"(.*)$/) {
      $offset++;
      $name = $1;
      while ($field[$offset] !~ /^(.*)"$/) {
        $offset++;
        $name .= ";$1";
      }
      if ($field[$offset] =~ /^(.*)"$/) {
        $name .= ";$1";
      }
    }
    if ($field[1+$offset] =~ /^"(.*)"$/) {
      $description = $1;
    } elsif ($field[1+$offset] =~ /^"(.*)$/) {
      $offset++;
      $description = $1;
      while ($field[1+$offset] !~ /^(.*)"$/) {
        $offset++;
        $description .= ";$1";
      }
      if ($field[1+$offset] =~ /^(.*)"$/) {
        $description .= ";$1";
      }
    }
    $hash->{register}{$field[2+$offset]}{name}        = makeReadingName($name);
    $hash->{register}{$field[2+$offset]}{description} = $description;
    $hash->{register}{$field[2+$offset]}{type}        = $field[4+$offset];
    $hash->{register}{$field[2+$offset]}{factor}      = $field[5+$offset];
    $hash->{register}{$field[2+$offset]}{mode}        = $field[9+$offset];
  }
  
  Log3 $name, 4, "$name: Loaded register ".scalar(@register);
}

1;
=pod
=begin html

<a name="NIBE"></a>
<h3>NIBE</h3>
<ul>
  Support for NIBE head pumps via <a href="NIBE_485">NIBE_485</a>.
  <br><br>
  example configuration:
  <ul>
  <h4>Prerequisite</h4>

    <h5>Export from NIBE ModbusManager</h5>
    <ul>
      <li>Select model in menu Models</li>
      <li>Goto File / Export to file</li>
      <li>Put the file into the directory defined in device "global" attribute "modpath"
          or use attribute "modbusFile" in the logical module at Fhem master</li>
    </ul>

  <h4>FHEM remote (connected to NIBE heat pump)</h4>

    <h5>physical module</h5>
    <code>define NibeWP NIBE_485 /dev/ttyAMA0</code>

    <h5>logical module</h5>
    <code>define Nibe NIBE<br>
    attr Nibe ignore 1</code>

  <h4>Fhem master</h4>

    <h5>physical module (dummy for FHEM2FHEM)</h5>
    <code>define NibeWP NIBE_485 none<br>
    attr NibeWP dummy 1</code>

    <h5>FHEM2FHEM</h5>
    <code>define Fhem_on_RPi FHEM2FHEM 192.168.2.47 RAW:NibeWP</code>

    <h5>logical module</h5>
    <code>define Nibe NIBE</code>
  </ul>
  <br><br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; NIBE</code>
    <br><br>
  </ul>
  <a name="NIBEget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;option&gt;</code>
    <br><br>
    See <a href="http://fhem.de/commandref.html#get">commandref#get</a> for more info about 
    the get command.
    <br><br>
    Options:
    <ul>
      <li><i>register</i> &lt;Id/Reading&gt;<br>
          Requests a register value from the heat pump. The register could be addressed by its <em>Id</em> or <em>Reading</em>.
      </li>
      <li><i>readRegister</i><br>
          The list of all loaded register information.
      </li>
      <li><i>writeRegister</i><br>
          The list of all loaded register information which support write access.
      </li>
    </ul>
  </ul>
  <a name="NIBEset"></a>
  <b>Set</b> 
  <ul>
    <code>set &lt;name&gt; &lt;option&gt; &lt;value&gt;</code>
    <br><br>
    You can <i>set</i> any value to any of the following options.
    See <a href="http://fhem.de/commandref.html#set">commandref#set</a> 
    for more info about the set command.
    <br><br>
    Options:
    <ul>
      <li><i>loadModbusFile</i><br>
          Loads register information from file, see attribute <a href=#NIBEmodbusFile>modbusFile</a>.
      </li>
    </ul>
  </ul>
  <a name="NIBEattr"></a>
  <b>Attributes</b>
  <ul>
    <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
    <br><br>
    See <a href="http://fhem.de/commandref.html#attr">commandref#attr</a> for more info about 
    the attr command.
    <br><br>
    Attributes:
    <ul>
      <li><i>ignore</i> 0|1<br>
          The parsing of messages from NIBE heat pump is time critical.
          By using this attribute parsing of messages can be omitted.
          It should be used on a remote FHEM installation.
      </li>
      <li><a name="NIBEmodbusFile"></a><i>modbusFile</i> &lt;file&gt;<br>
          The absolute path to file containing register mapping exported from Nibe Modbus Manager.
          Without this attribute the module looks for file <code>export.cvs</code> in the directory
          defined by device <code>global</code> attribute <code>modpath</code>.
      </li>
    </ul>
  </ul>
</ul>

=end html
=begin html_DE

<a name="NIBE"></a>
<h3>NIBE</h3>
<ul>
  Unterstützung von NIBE Wärmepumpen via <a href="NIBE_485">NIBE_485</a>.
  <br><br>
  Beispielkonfiguration:
  <ul>
  <h4>entferntes FHEM (verbunden mit einer NIBE Wärmepumpe)</h4>

    <h5>physische Modul</h5>
    <code>define NibeWP NIBE_485 /dev/ttyAMA0</code>

    <h5>logisches Modul</h5>
    <code>define Nibe NIBE<br>
    attr Nibe ignore 1</code>

  <h4>FHEM Master</h4>

    <h5>physisches Modul (Dummy für FHEM2FHEM)</h5>
    <code>define NibeWP NIBE_485 none<br>
    attr NibeWP dummy 1</code>

    <h5>FHEM2FHEM</h5>
    <code>define Fhem_on_RPi FHEM2FHEM 192.168.2.47 RAW:NibeWP</code>

    <h5>logisches Modul</h5>
    <code>define Nibe NIBE</code>
  </ul>
  <br><br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; NIBE</code>
    <br><br>
  </ul>
  <a name="NIBEattr"></a>
  <b>Attributes</b> 
  <ul><b>ignore</b>
    <ul>
      Die Verarbeitung der Nachrichten von der NIBE Wärmepumpe ist zeitkritisch.
      Daher kann über dieses Attrbiute das Parsen der Nachrichten unterdrückt werden.
      Es sollte auf einer entfernten FHEM Installation verwendet werden.
    </ul>
  </ul>
</ul>

=end html_DE
=cut
