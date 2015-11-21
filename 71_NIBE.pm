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

sub NIBE_Initialize ($)
{
#(initialisiert das Modul und gibt de Namen der zusätzlichen Funktionen bekannt)

	# Read the parameters into $hash
	my ($hash) = @_;
	
	# Define the functions
	$hash->{DefFn}      = "NIBE_Define";			# Define the device
	$hash->{UndefFn}    = "NIBE_Undef"; 			# Delete the device
    $hash->{SetFn}      = "NIBE_Set";
	$hash->{GetFn}      = "NIBE_Get";				# Manually get data
	$hash->{ParseFn}    = "NIBE_Parse";				# Parse function - Only used for two step modules?
	$hash->{Match}      = ".*";						# ???????????????????
	$hash->{AttrList}   = "IODev o_not_notify:1,0 ".
            "ignore:1,0 dummy:1,0 showtime:1,0 ".
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

	return undef;
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
    
        # what we got so far
        Log3 $name, 5, "$name: HEAD: ".substr($msg,0,4)." ADDR: ".substr($msg,4,2)
                            ." CMD: ".substr($msg,6,2)." LEN: ".substr($msg,8,2)
                            ." CHK: ".substr($msg,length($msg)-2,2);
    
    
        if ($checksum==hex(substr($msg, length($msg)-2, 2))) {
            Log3 $name, 5, "$name: Checksum OK";
    
            # Check if we got a message with the command 68 
            # In this message we can expect 20 values from the heater which were defined with the help of ModbusManager
            if ($command eq "68" and AttrVal($name, "ignore", "0") eq "0") {
                # Populate the reading(s)
                readingsBeginUpdate($hash);
    
                my $j=5;
                while($j < $length) {
                    if (substr($msg,$j*2,4) =~ m/(.{2})(.{2})/) {
                        my $register = $2.$1;
                        $j += 2;
      
                        if ($register ne "ffff") {    
                            # Getting the register name
                            my $reading = return_register(hex($register), 0);
                        
                            # Calculating the actual value
                            if (defined($reading)) {
                                my $valuetype = return_register( hex($register),3);
                                my $factor    = return_register( hex($register),4);
                                my $value     = "";
                                if ($valuetype =~ m/[su](\d*)/) {
                                    my $bytes = $1/8;
                                    for (my $i = 0; $i < $bytes; $i++) {
                                        my $byte = substr($msg, $j++*2, 2);
                                        $value = $byte . $value;
                                        # remove escaping of 0x5c
                                        if ($byte eq "5c") {
                                            $j++ if (substr($msg, $j*2, 2) eq "5c");
                                        }
                                    }
                                } else {
                                    Log3 $name, 3, "$name: Unsupported value size $valuetype";
                                }
                                if ($value ne "") {
                                    my $reading_value = return_normalizedvalue($valuetype,$value)/$factor;
                                    readingsBulkUpdate($hash, $reading, $reading_value)
                                            if ($reading_value ne ReadingsVal($name, $reading, ""));
                                }
                            } else {
                                Log3 $name, 3, "$name: Register ".hex($register)." not defined";
                                Log3 $name, 4, "$name: $msg";
                            }
                        } else {
                          # skip value 0000 of register ffff
                          $j += 2;
                        }
                    }
                }
                readingsEndUpdate($hash, 1);
                return $name;
            }
        } else {
            Log3 $name, 4, "$name: Checksum not OK";
            Log3 $name, 4, "$name: $msg";
        }
    }
    return "";
}

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
	40004 => ["BT1_Outdoor_temp","Outdoor temperature","°C","s16","10","0","0","0","R"],
	40005 => ["EB23-BT2_Supply_temp_S4","Supply temperature for system 4","°C","s16","10","0","0","0","R"],
	40006 => ["EB22-BT2_Supply_temp_S3","Supply temperature for system 3","°C","s16","10","0","0","0","R"],
	40007 => ["EB21-BT2_Supply_temp_S2","Supply temperature for system 2","°C","s16","10","0","0","0","R"],
	40008 => ["BT2_Supply_temp_S1","Supply temperature for system 1","°C","s16","10","0","0","0","R"],
	40011 => ["EB100-EP15-BT3_Return_temp","","°C","s16","10","0","0","0","R"],
	40012 => ["EB100-EP14-BT3_Return_temp","Return temperature","°C","s16","10","0","0","0","R"],
	40013 => ["BT7_Hot_Water_top","","°C","s16","10","0","0","0","R"],
	40014 => ["BT6_Hot_Water_load","","°C","s16","10","0","0","0","R"],
	40015 => ["EB100-EP14-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	40016 => ["EB100-EP14-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	40017 => ["EB100-EP14-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	40018 => ["EB100-EP14-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	40019 => ["EB100-EP14-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	40020 => ["EB100-BT16_Evaporator_temp","","°C","s16","10","0","0","0","R"],
	40022 => ["EB100-EP14-BT17_Suction","","°C","s16","10","0","0","0","R"],
	40023 => ["EB100-BT18_Compressor_temp.","Valid only for F3/470","°C","s16","10","0","0","0","R"],
	40024 => ["EB100-BT19_Addition_temp.","Valid only for F3/470","°C","s16","10","0","0","0","R"],
	40025 => ["EB100-BT20_Exhaust_air_temp.","","°C","s16","10","0","0","0","R"],
	40026 => ["EB100-BT21_Vented_air_temp.","","°C","s16","10","0","0","0","R"],
	40028 => ["AZ1-BT26_Temp_Collector_in_FLM_1","Connected to the FLM module","°C","s16","10","0","0","0","R"],
	40029 => ["AZ1-BT27_Temp_Collector_out_FLM_1","Connected to the FLM module","°C","s16","10","0","0","0","R"],
	40030 => ["EB23-BT50_Room_Temp_S4","","°C","s16","10","0","0","0","R"],
	40031 => ["EB22-BT50_Room_Temp_S3","","°C","s16","10","0","0","0","R"],
	40032 => ["EB21-BT50_Room_Temp_S2","","°C","s16","10","0","0","0","R"],
	40033 => ["BT50_Room_Temp_S1","","°C","s16","10","0","0","0","R"],
	40042 => ["CL11-BT51_Pool_1_Temp","","°C","s16","10","0","0","0","R"],
	40043 => ["EP8-BT53_Solar_Panel_Temp","","°C","s16","10","0","0","0","R"],
	40044 => ["EP8-BT54_Solar_Load_Temp","","°C","s16","10","0","0","0","R"],
	40045 => ["EQ1-BT64_PCS4_Supply_Temp","PCS4 Only","°C","s16","10","0","0","0","R"],
	40046 => ["EQ1-BT65_PCS4_Return_Temp","PCS4 Only","°C","s16","10","0","0","0","R"],
	40047 => ["EB100-BT61_Supply_Radiator_Temp","","°C","s16","10","0","0","0","R"],
	40048 => ["EB100-BT62_Return_Radiator_Temp","","°C","s16","10","0","0","0","R"],
	40050 => ["EB100-BS1_Air_flow","","","s16","10","0","0","0","R"],
	40051 => ["EB100-BS1_Air_flow_unfiltered","Unfiltered air flow value","","s16","100","0","0","0","R"],
	40054 => ["EB100-FD1_Temperature_limiter","","","s16","1","0","0","0","R"],
	40067 => ["BT1_Average","EB100-BT1 Outdoor temperature average","°C","s16","10","0","0","0","R"],
	40070 => ["EM1-BT52_Boiler_temperature","Temperature of Boiler","°C","s16","10","0","0","0","R"],
	40071 => ["BT25_external_supply_temp","","°C","s16","10","0","0","0","R"],
	40072 => ["BF1_Flow","Current flow","l/m","s16","10","0","0","0","R"],
	40074 => ["EB100-FR1_Anode_Status","","","s16","1","0","0","0","R"],
	40075 => ["EB100-BT22_Supply_air_temp.","","°C","s16","10","0","0","0","R"],
	40076 => ["EP8-BT55_Solar_Tank_Top_Temp","","°C","s16","10","0","0","0","R"],
	40077 => ["BT6_external_water_heater_load_temp.","This includes DEW and SCA accessory","°C","s16","10","0","0","0","R"],
	40078 => ["BT7_external_water_heater_top_temp.","This includes DEW and SCA accessory","°C","s16","10","0","0","0","R"],
	40079 => ["EB100-BE3_Current_Phase_3","","A","s32","10","0","0","0","R"],
	40081 => ["EB100-BE2_Current_Phase_2","","A","s32","10","0","0","0","R"],
	40083 => ["EB100-BE1_Current_Phase_1","","A","s32","10","0","0","0","R"],
	40085 => ["EB100-EP15-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	40086 => ["EB100-EP15-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	40087 => ["EB100-EP15-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	40088 => ["EB100-EP15-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	40089 => ["EB100-EP15-BT17_Suction","","°C","s16","10","0","0","0","R"],
	40100 => ["EB100-EP15-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	40106 => ["CL11-BT51_Pool_2_Temp","","°C","s16","10","0","0","0","R"],
	40107 => ["EB100-BT20_Exhaust_air_temp.","","°C","s16","10","0","0","0","R"],
	40108 => ["EB100-BT20_Exhaust_air_temp.","","°C","s16","10","0","0","0","R"],
	40109 => ["EB100-BT20_Exhaust_air_temp.","","°C","s16","10","0","0","0","R"],
	40110 => ["EB100-BT21_Vented_air_temp.","","°C","s16","10","0","0","0","R"],
	40111 => ["EB100-BT21_Vented_air_temp.","","°C","s16","10","0","0","0","R"],
	40112 => ["EB100-BT21_Vented_air_temp.","","°C","s16","10","0","0","0","R"],
	40113 => ["AZ1-BT26_Temp_Collector_in_FLM_4","Connected to the FLM module","°C","s16","10","0","0","0","R"],
	40114 => ["AZ1-BT26_Temp_Collector_in_FLM_3","Connected to the FLM module","°C","s16","10","0","0","0","R"],
	40115 => ["AZ1-BT26_Temp_Collector_in_FLM_2","Connected to the FLM module","°C","s16","10","0","0","0","R"],
	40116 => ["AZ1-BT27_Temp_Collector_out_FLM_4","Connected to the FLM module","°C","s16","10","0","0","0","R"],
	40117 => ["AZ1-BT27_Temp_Collector_out_FLM_3","Connected to the FLM module","°C","s16","10","0","0","0","R"],
	40118 => ["AZ1-BT27_Temp_Collector_out_FLM_2","Connected to the FLM module","°C","s16","10","0","0","0","R"],
	40121 => ["BT63_Add_Supply_Temp","","ºC","s16","10","0","0","0","R"],
	40122 => ["DEH-BT6_external_water_heater_load_temp.","","°C","s16","10","0","0","0","R"],
	40127 => ["EB23-BT3_Return_temp_S4","Return temperature for system 4","°C","s16","10","0","0","0","R"],
	40128 => ["EB22-BT3_Return_temp_S3","Return temperature for system 3","°C","s16","10","0","0","0","R"],
	40129 => ["EB21-BT3_Return_temp_S2","Return temperature for system 2","°C","s16","10","0","0","0","R"],
	40131 => ["EB100-EP15-BP8_Pressure_Transmitter","Temperture reported by the pressure transmitter","°C","s16","10","0","0","0","R"],
	40132 => ["EB100-EP14-BP8_Pressure_Transmitter","Temperture reported by the pressure transmitter","°C","s16","10","0","0","0","R"],
	40141 => ["AZ2-BT22_Supply_air_temp._SAM","","ºC","s16","10","0","0","0","R"],
	40142 => ["AZ2-BT23_Outdoor_temp._SAM","","ºC","s16","10","0","0","0","R"],
	40143 => ["AZ2-BT68_Flow_temp._SAM","Heat medium flow temperature to SAM module","°C","s16","10","0","0","0","R"],
	40144 => ["AZ2-BT69_Return_temp._SAM","Heat medium return temperature from SAM module","°C","s16","10","0","0","0","R"],
	40145 => ["EB100-EP15-BT29","Compressor oil temperature","°C","s16","10","0","0","0","R"],
	40146 => ["EB100-EP14-BT29","Compressor oil temperature","°C","s16","10","0","0","0","R"],
	40147 => ["BT70_HW_supply_temp.","Hot water supply temperature","°C","s16","10","0","0","0","R"],
	40152 => ["BT71_Ext._Return_temp","","°C","s16","10","0","0","0","R"],
	40154 => ["EP8-BT51_Solar_pool_Temp","","°C","s16","10","0","0","0","R"],
	40155 => ["EQ1-BT57_Collector_temp.","External collector temperature for ACS","°C","s16","10","0","0","0","R"],
	40156 => ["EQ1-BT75_Heatdump_temp.","Heating medium dump temperature for ACS","°C","s16","10","0","0","0","R"],
	40157 => ["EP30-BT53_Solar_Panel_Temp","","°C","s16","10","0","0","0","R"],
	40158 => ["EP30-BT54_Solar_Load_Temp","","°C","s16","10","0","0","0","R"],
	43001 => ["Software_version","","","u16","1","0","0","0","R"],
	43005 => ["Degree_Minutes","","","s16","10","-30000","30000","0","R/W"],
	43006 => ["Calculated_Supply_Temperature_S4","","°C","s16","10","0","0","0","R"],
	43007 => ["Calculated_Supply_Temperature_S3","","°C","s16","10","0","0","0","R"],
	43008 => ["Calculated_Supply_Temperature_S2","","°C","s16","10","0","0","0","R"],
	43009 => ["Calculated_Supply_Temperature_S1","","°C","s16","10","0","0","0","R"],
	43013 => ["Freeze_Protection_Status","1 = Freeze protection active","","u8","1","0","0","0","R"],
	43024 => ["Status_Cooling"," 0=Off 1=On","","u8","1","0","0","0","R"],
	43061 => ["t._after_start_timer","","","u8","1","0","0","0","R"],
	43062 => ["t._after_mode_change","Time after mode change","","u8","1","0","0","0","R"],
	43064 => ["HMF_dT_set.","set point delta T for the heat medium flow","","s16","10","0","0","0","R"],
	43065 => ["HMF_dT_act.","Current value of the delta T for the heat medium flow","","s16","10","0","0","0","R"],
	43081 => ["Tot._op.time_add.","Total electric additive operation time","h","s32","10","0","9999999","0","R"],
	43084 => ["Int._el.add._Power","Current power from the internal electrical addition","kW","s16","100","0","0","0","R"],
	43086 => ["Prio","Indicates what heating action (HW/heat/pool) currently prioritised 10=Off 20=Hot Water 30=Heat 40=Pool 41=Pool 2 50=Transfer 60=Cooling","","u8","1","0","0","0","R"],
	43091 => ["Int._el.add._State","State of the internal electrical addition","","u8","1","0","0","0","R"],
	43103 => ["HPAC_state","State of the HPAC cooling accessory.","","u8","1","0","0","0","R"],
	43105 => ["Status_FJVM","The state of the FJVM accessory","","u8","1","0","0","0","R"],
	43108 => ["Fan_speed_current","The current fan speed after scheduling and blocks are considered","%","u8","1","0","0","0","R"],
	43122 => ["Compr._current_min.freq.","The current minimum frequency of the compressor","Hz","s16","1","0","0","0","R"],
	43123 => ["Compr._current_max.freq.","The current maximum frequency of the compressor","Hz","s16","1","0","0","0","R"],
	43124 => ["Airflow_ref.","Reference value for the airflow.","","s16","10","0","0","0","R"],
	43132 => ["Inverter_com._timer","This value shows the time since last communication with the inverter","sec","u16","1","0","0","0","R"],
	43133 => ["Inverter_drive_status","","","u16","1","0","0","0","R"],
	43136 => ["Compr._current_freq.","The frequency of the compressor at the moment","Hz","u16","10","0","0","0","R"],
	43137 => ["Inverter_alarm_code","","","u16","1","0","0","0","R"],
	43138 => ["Inverter_fault_code","","","u16","1","0","0","0","R"],
	43140 => ["compr._temp.","Current compressor temparture","°C","s16","10","0","0","0","R"],
	43141 => ["compr._in_power","The power delivered from the inverter to the compressor","W","u16","1","0","0","0","R"],
	43144 => ["Compr._energy_total","Total compressor energy in kWh","kWh","u32","100","0","9999999","0","R"],
	43147 => ["Compr._in_current","The current delivered from the inverter to the compressor","A","s16","1","0","0","0","R"],
	43181 => ["Chargepump_speed","","","s16","1","0","0","0","R"],
	43182 => ["Compr._freq._setpoint","The targeted compressor frequency","Hz","u16","1","0","0","0","R"],
	43230 => ["Accumulated_energy","","kWh","u32","10","0","9999999","0","R"],
	43239 => ["Tot._HW_op.time_add.","Total electric additive operation time in hot water mode","h","s32","10","0","9999999","0","R"],
	43305 => ["Compr._energy_HW","Compressor energy during hot water production in kWh","kWh","u32","100","0","9999999","0","R"],
	43375 => ["compr._in_power_mean","Mean power delivered from the inverter to the compressor. Mean is calculated every 10 seconds.","W","s16","1","0","0","0","R"],
	43382 => ["Inverter_mem_error_code","","","u16","1","0","0","0","R"],
	43383 => ["FJVM_Relays","Indicates the active relays on the FJVM accessory. The information is binary encoded","","u8","1","0","0","0","R"],
	43395 => ["HPAC_Relays","Indicates the active relays on the HPAC accessory. The information is binary encoded","","u8","1","0","0","0","R"],
	43414 => ["Compressor_starts_EB100-EP15","Number of compressorer starts","","s32","1","0","0","0","R"],
	43416 => ["Compressor_starts_EB100-EP14","Number of compressorer starts","","s32","1","0","9999999","0","R"],
	43418 => ["Tot._op.time_compr._EB100-EP15","Total compressorer operation time","h","s32","1","0","0","0","R"],
	43420 => ["Tot._op.time_compr._EB100-EP14","Total compressorer operation time","h","s32","1","0","9999999","0","R"],
	43422 => ["Tot._HW_op.time_compr._EB100-EP15","Total compressorer operation time in hot water mode","h","s32","1","0","0","0","R"],
	43424 => ["Tot._HW_op.time_compr._EB100-EP14","Total compressorer operation time in hot water mode","h","s32","1","0","9999999","0","R"],
	43426 => ["Compressor_State_EP15","20 = Stopped, 40 = Starting, 60 = Running, 100 = Stopping","","u8","1","0","0","0","R"],
	43427 => ["Compressor_State_EP14","20 = Stopped, 40 = Starting, 60 = Running, 100 = Stopping","","u8","1","0","0","0","R"],
	43434 => ["Compressor_status_EP15","Indicates if the compressor is supplied with power 0=Off 1=On","","u8","1","0","0","0","R"],
	43435 => ["Compressor_status_EP14","Indicates if the compressor is supplied with power 0=Off 1=On","","u8","1","0","0","0","R"],
	43436 => ["HM-pump_Status_EP15","Status of the circ. pump","","u8","1","0","0","0","R"],
	43437 => ["HM-pump_Status_EP14","Status of the circ. pump","","u8","1","0","0","0","R"],
	43438 => ["Brinepump_Status_EP15","Status of the Brine pump","","u8","1","0","0","0","R"],
	43439 => ["Brinepump_Status_EP14","Status of the Brine pump","","u8","1","0","0","0","R"],
	43459 => ["Ceded_OU_effect","","kW","u16","10","0","0","0","R"],
	43460 => ["State_DEH","The state of the DEH accessory","","u8","1","0","0","0","R"],
	43490 => ["Steps_ext._add.","Number of steps active external addition","","u8","1","0","0","0","R"],
	43513 => ["PCA-Base_Relays_EP15","Indicates the active relays on the PCA-Base card. The information is binary encoded","","u8","1","0","0","0","R"],
	43514 => ["PCA-Base_Relays_EP14","Indicates the active relays on the PCA-Base card. The information is binary encoded","","u8","1","0","0","0","R"],
	43516 => ["PCA-Power_Relays_EP14","Indicates the active relays on the PCA-Power card. The information is binary encoded","","u8","1","0","0","0","R"],
	43542 => ["Calculated_supply_air_temp.","","ºC","s16","10","0","0","0","R"],
	43600 => ["EB108-EP15-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	43601 => ["EB108-EP15-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	43602 => ["EB108-EP15-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	43603 => ["EB108-EP15-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	43604 => ["EB108-EP15-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	43605 => ["EB108-EP15-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	43606 => ["EB108-EP15-BT17_Suction","","°C","s16","10","0","0","0","R"],
	43607 => ["EB108-EP15-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	43608 => ["EB108-EP15-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	43609 => ["EB108-EP15_Compressor_State","","","u8","1","0","0","0","R"],
	43610 => ["EB108-EP15_Compr._time_to_start","","","u8","1","0","0","0","R"],
	43611 => ["EB108-EP15_Relay_status","","","u16","1","0","0","0","R"],
	43612 => ["EB108-EP15_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	43613 => ["EB108-EP15_Brine_pump_status","","","u8","1","0","0","0","R"],
	43614 => ["EB108-EP15_Compressor_starts","","","u32","1","0","0","0","R"],
	43616 => ["EB108-EP15_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	43618 => ["EB108-EP15_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	43620 => ["EB108-EP15_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	43621 => ["EB108-EP14-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	43622 => ["EB108-EP14-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	43623 => ["EB108-EP14-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	43624 => ["EB108-EP14-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	43625 => ["EB108-EP14-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	43626 => ["EB108-EP14-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	43627 => ["EB108-EP14-BT17_Suction","","°C","s16","10","0","0","0","R"],
	43628 => ["EB108-EP14-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	43629 => ["EB108-EP14-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	43630 => ["EB108-EP14_Compressor_State","","","u8","1","0","0","0","R"],
	43631 => ["EB108-EP14_Compr._time_to_start","","","u8","1","0","0","0","R"],
	43632 => ["EB108-EP14_Relay_status","","","u16","1","0","0","0","R"],
	43633 => ["EB108-EP14_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	43634 => ["EB108-EP14_Brine_pump_status","","","u8","1","0","0","0","R"],
	43635 => ["EB108-EP14_Compressor_starts","","","u32","1","0","0","0","R"],
	43637 => ["EB108-EP14_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	43639 => ["EB108-EP14_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	43641 => ["EB108-EP14_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	43662 => ["EB107-EP15-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	43663 => ["EB107-EP15-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	43664 => ["EB107-EP15-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	43665 => ["EB107-EP15-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	43666 => ["EB107-EP15-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	43667 => ["EB107-EP15-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	43668 => ["EB107-EP15-BT17_Suction","","°C","s16","10","0","0","0","R"],
	43669 => ["EB107-EP15-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	43670 => ["EB107-EP15-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	43671 => ["EB107-EP15_Compressor_State","","","u8","1","0","0","0","R"],
	43672 => ["EB107-EP15_Compr._time_to_start","","","u8","1","0","0","0","R"],
	43673 => ["EB107-EP15_Relay_status","","","u16","1","0","0","0","R"],
	43674 => ["EB107-EP15_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	43675 => ["EB107-EP15_Brine_pump_status","","","u8","1","0","0","0","R"],
	43676 => ["EB107-EP15_Compressor_starts","","","u32","1","0","0","0","R"],
	43678 => ["EB107-EP15_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	43680 => ["EB107-EP15_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	43682 => ["EB107-EP15_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	43683 => ["EB107-EP14-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	43684 => ["EB107-EP14-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	43685 => ["EB107-EP14-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	43686 => ["EB107-EP14-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	43687 => ["EB107-EP14-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	43688 => ["EB107-EP14-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	43689 => ["EB107-EP14-BT17_Suction","","°C","s16","10","0","0","0","R"],
	43690 => ["EB107-EP14-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	43691 => ["EB107-EP14-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	43692 => ["EB107-EP14_Compressor_State","","","u8","1","0","0","0","R"],
	43693 => ["EB107-EP14_Compr._time_to_start","","","u8","1","0","0","0","R"],
	43694 => ["EB107-EP14_Relay_status","","","u16","1","0","0","0","R"],
	43695 => ["EB107-EP14_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	43696 => ["EB107-EP14_Brine_pump_status","","","u8","1","0","0","0","R"],
	43697 => ["EB107-EP14_Compressor_starts","","","u32","1","0","0","0","R"],
	43699 => ["EB107-EP14_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	43701 => ["EB107-EP14_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	43703 => ["EB107-EP14_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	43724 => ["EB106-EP15-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	43725 => ["EB106-EP15-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	43726 => ["EB106-EP15-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	43727 => ["EB106-EP15-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	43728 => ["EB106-EP15-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	43729 => ["EB106-EP15-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	43730 => ["EB106-EP15-BT17_Suction","","°C","s16","10","0","0","0","R"],
	43731 => ["EB106-EP15-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	43732 => ["EB106-EP15-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	43733 => ["EB106-EP15_Compressor_State","","","u8","1","0","0","0","R"],
	43734 => ["EB106-EP15_Compr._time_to_start","","","u8","1","0","0","0","R"],
	43735 => ["EB106-EP15_Relay_status","","","u16","1","0","0","0","R"],
	43736 => ["EB106-EP15_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	43737 => ["EB106-EP15_Brine_pump_status","","","u8","1","0","0","0","R"],
	43738 => ["EB106-EP15_Compressor_starts","","","u32","1","0","0","0","R"],
	43740 => ["EB106-EP15_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	43742 => ["EB106-EP15_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	43744 => ["EB106-EP15_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	43745 => ["EB106-EP14-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	43746 => ["EB106-EP14-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	43747 => ["EB106-EP14-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	43748 => ["EB106-EP14-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	43749 => ["EB106-EP14-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	43750 => ["EB106-EP14-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	43751 => ["EB106-EP14-BT17_Suction","","°C","s16","10","0","0","0","R"],
	43752 => ["EB106-EP14-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	43753 => ["EB106-EP14-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	43754 => ["EB106-EP14_Compressor_State","","","u8","1","0","0","0","R"],
	43755 => ["EB106-EP14_Compr._time_to_start","","","u8","1","0","0","0","R"],
	43756 => ["EB106-EP14_Relay_status","","","u16","1","0","0","0","R"],
	43757 => ["EB106-EP14_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	43758 => ["EB106-EP14_Brine_pump_status","","","u8","1","0","0","0","R"],
	43759 => ["EB106-EP14_Compressor_starts","","","u32","1","0","0","0","R"],
	43761 => ["EB106-EP14_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	43763 => ["EB106-EP14_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	43765 => ["EB106-EP14_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	43786 => ["EB105-EP15-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	43787 => ["EB105-EP15-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	43788 => ["EB105-EP15-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	43789 => ["EB105-EP15-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	43790 => ["EB105-EP15-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	43791 => ["EB105-EP15-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	43792 => ["EB105-EP15-BT17_Suction","","°C","s16","10","0","0","0","R"],
	43793 => ["EB105-EP15-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	43794 => ["EB105-EP15-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	43795 => ["EB105-EP15_Compressor_State","","","u8","1","0","0","0","R"],
	43796 => ["EB105-EP15_Compr._time_to_start","","","u8","1","0","0","0","R"],
	43797 => ["EB105-EP15_Relay_status","","","u16","1","0","0","0","R"],
	43798 => ["EB105-EP15_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	43799 => ["EB105-EP15_Brine_pump_status","","","u8","1","0","0","0","R"],
	43800 => ["EB105-EP15_Compressor_starts","","","u32","1","0","0","0","R"],
	43802 => ["EB105-EP15_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	43804 => ["EB105-EP15_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	43806 => ["EB105-EP15_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	43807 => ["EB105-EP14-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	43808 => ["EB105-EP14-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	43809 => ["EB105-EP14-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	43810 => ["EB105-EP14-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	43811 => ["EB105-EP14-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	43812 => ["EB105-EP14-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	43813 => ["EB105-EP14-BT17_Suction","","°C","s16","10","0","0","0","R"],
	43814 => ["EB105-EP14-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	43815 => ["EB105-EP14-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	43816 => ["EB105-EP14_Compressor_State","","","u8","1","0","0","0","R"],
	43817 => ["EB105-EP14_Compr._time_to_start","","","u8","1","0","0","0","R"],
	43818 => ["EB105-EP14_Relay_status","","","u16","1","0","0","0","R"],
	43819 => ["EB105-EP14_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	43820 => ["EB105-EP14_Brine_pump_status","","","u8","1","0","0","0","R"],
	43821 => ["EB105-EP14_Compressor_starts","","","u32","1","0","0","0","R"],
	43823 => ["EB105-EP14_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	43825 => ["EB105-EP14_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	43827 => ["EB105-EP14_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	43848 => ["EB104-EP15-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	43849 => ["EB104-EP15-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	43850 => ["EB104-EP15-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	43851 => ["EB104-EP15-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	43852 => ["EB104-EP15-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	43853 => ["EB104-EP15-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	43854 => ["EB104-EP15-BT17_Suction","","°C","s16","10","0","0","0","R"],
	43855 => ["EB104-EP15-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	43856 => ["EB104-EP15-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	43857 => ["EB104-EP15_Compressor_State","","","u8","1","0","0","0","R"],
	43858 => ["EB104-EP15_Compr._time_to_start","","","u8","1","0","0","0","R"],
	43859 => ["EB104-EP15_Relay_status","","","u16","1","0","0","0","R"],
	43860 => ["EB104-EP15_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	43861 => ["EB104-EP15_Brine_pump_status","","","u8","1","0","0","0","R"],
	43862 => ["EB104-EP15_Compressor_starts","","","u32","1","0","0","0","R"],
	43864 => ["EB104-EP15_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	43866 => ["EB104-EP15_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	43868 => ["EB104-EP15_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	43869 => ["EB104-EP14-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	43870 => ["EB104-EP14-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	43871 => ["EB104-EP14-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	43872 => ["EB104-EP14-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	43873 => ["EB104-EP14-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	43874 => ["EB104-EP14-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	43875 => ["EB104-EP14-BT17_Suction","","°C","s16","10","0","0","0","R"],
	43876 => ["EB104-EP14-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	43877 => ["EB104-EP14-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	43878 => ["EB104-EP14_Compressor_State","","","u8","1","0","0","0","R"],
	43879 => ["EB104-EP14_Compr._time_to_start","","","u8","1","0","0","0","R"],
	43880 => ["EB104-EP14_Relay_status","","","u16","1","0","0","0","R"],
	43881 => ["EB104-EP14_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	43882 => ["EB104-EP14_Brine_pump_status","","","u8","1","0","0","0","R"],
	43883 => ["EB104-EP14_Compressor_starts","","","u32","1","0","0","0","R"],
	43885 => ["EB104-EP14_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	43887 => ["EB104-EP14_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	43889 => ["EB104-EP14_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	43910 => ["EB103-EP15-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	43911 => ["EB103-EP15-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	43912 => ["EB103-EP15-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	43913 => ["EB103-EP15-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	43914 => ["EB103-EP15-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	43915 => ["EB103-EP15-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	43916 => ["EB103-EP15-BT17_Suction","","°C","s16","10","0","0","0","R"],
	43917 => ["EB103-EP15-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	43918 => ["EB103-EP15-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	43919 => ["EB103-EP15_Compressor_State","","","u8","1","0","0","0","R"],
	43920 => ["EB103-EP15_Compr._time_to_start","","","u8","1","0","0","0","R"],
	43921 => ["EB103-EP15_Relay_status","","","u16","1","0","0","0","R"],
	43922 => ["EB103-EP15_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	43923 => ["EB103-EP15_Brine_pump_status","","","u8","1","0","0","0","R"],
	43924 => ["EB103-EP15_Compressor_starts","","","u32","1","0","0","0","R"],
	43926 => ["EB103-EP15_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	43928 => ["EB103-EP15_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	43930 => ["EB103-EP15_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	43931 => ["EB103-EP14-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	43932 => ["EB103-EP14-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	43933 => ["EB103-EP14-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	43934 => ["EB103-EP14-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	43935 => ["EB103-EP14-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	43936 => ["EB103-EP14-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	43937 => ["EB103-EP14-BT17_Suction","","°C","s16","10","0","0","0","R"],
	43938 => ["EB103-EP14-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	43939 => ["EB103-EP14-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	43940 => ["EB103-EP14_Compressor_State","","","u8","1","0","0","0","R"],
	43941 => ["EB103-EP14_Compr._time_to_start","","","u8","1","0","0","0","R"],
	43942 => ["EB103-EP14_Relay_status","","","u16","1","0","0","0","R"],
	43943 => ["EB103-EP14_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	43944 => ["EB103-EP14_Brine_pump_status","","","u8","1","0","0","0","R"],
	43945 => ["EB103-EP14_Compressor_starts","","","u32","1","0","0","0","R"],
	43947 => ["EB103-EP14_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	43949 => ["EB103-EP14_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	43951 => ["EB103-EP14_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	43972 => ["EB102-EP15-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	43973 => ["EB102-EP15-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	43974 => ["EB102-EP15-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	43975 => ["EB102-EP15-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	43976 => ["EB102-EP15-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	43977 => ["EB102-EP15-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	43978 => ["EB102-EP15-BT17_Suction","","°C","s16","10","0","0","0","R"],
	43979 => ["EB102-EP15-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	43980 => ["EB102-EP15-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	43981 => ["EB102-EP15_Compressor_State","","","u8","1","0","0","0","R"],
	43982 => ["EB102-EP15_Compr._time_to_start","","","u8","1","0","0","0","R"],
	43983 => ["EB102-EP15_Relay_status","","","u16","1","0","0","0","R"],
	43984 => ["EB102-EP15_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	43985 => ["EB102-EP15_Brine_pump_status","","","u8","1","0","0","0","R"],
	43986 => ["EB102-EP15_Compressor_starts","","","u32","1","0","0","0","R"],
	43988 => ["EB102-EP15_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	43990 => ["EB102-EP15_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	43992 => ["EB102-EP15_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	43993 => ["EB102-EP14-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	43994 => ["EB102-EP14-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	43995 => ["EB102-EP14-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	43996 => ["EB102-EP14-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	43997 => ["EB102-EP14-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	43998 => ["EB102-EP14-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	43999 => ["EB102-EP14-BT17_Suction","","°C","s16","10","0","0","0","R"],
	44000 => ["EB102-EP14-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	44001 => ["EB102-EP14-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	44002 => ["EB102-EP14_Compressor_State","","","u8","1","0","0","0","R"],
	44003 => ["EB102-EP14_Compr._time_to_start","","","u8","1","0","0","0","R"],
	44004 => ["EB102-EP14_Relay_status","","","u16","1","0","0","0","R"],
	44005 => ["EB102-EP14_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	44006 => ["EB102-EP14_Brine_pump_status","","","u8","1","0","0","0","R"],
	44007 => ["EB102-EP14_Compressor_starts","","","u32","1","0","0","0","R"],
	44009 => ["EB102-EP14_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	44011 => ["EB102-EP14_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	44013 => ["EB102-EP14_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	44034 => ["EB101-EP15-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	44035 => ["EB101-EP15-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	44036 => ["EB101-EP15-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	44037 => ["EB101-EP15-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	44038 => ["EB101-EP15-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	44039 => ["EB101-EP15-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	44040 => ["EB101-EP15-BT17_Suction","","°C","s16","10","0","0","0","R"],
	44041 => ["EB101-EP15-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	44042 => ["EB101-EP15-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	44043 => ["EB101-EP15_Compressor_State","","","u8","1","0","0","0","R"],
	44044 => ["EB101-EP15_Compr._time_to_start","","","u8","1","0","0","0","R"],
	44045 => ["EB101-EP15_Relay_status","","","u16","1","0","0","0","R"],
	44046 => ["EB101-EP15_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	44047 => ["EB101-EP15_Brine_pump_status","","","u8","1","0","0","0","R"],
	44048 => ["EB101-EP15_Compressor_starts","","","u32","1","0","0","0","R"],
	44050 => ["EB101-EP15_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	44052 => ["EB101-EP15_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	44054 => ["EB101-EP15_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	44055 => ["EB101-EP14-BT3_Return_temp.","Return temperature","°C","s16","10","0","0","0","R"],
	44056 => ["EB101-EP14-BT10_Brine_in_temp","","°C","s16","10","0","0","0","R"],
	44057 => ["EB101-EP14-BT11_Brine_out_temp","","°C","s16","10","0","0","0","R"],
	44058 => ["EB101-EP14-BT12_Cond._out","","°C","s16","10","0","0","0","R"],
	44059 => ["EB101-EP14-BT14_Hot_gas_temp","","°C","s16","10","0","0","0","R"],
	44060 => ["EB101-EP14-BT15_Liquid_line","","°C","s16","10","0","0","0","R"],
	44061 => ["EB101-EP14-BT17_Suction","","°C","s16","10","0","0","0","R"],
	44062 => ["EB101-EP14-BT29_Compr._Oil._temp.","","°C","s16","10","0","0","0","R"],
	44063 => ["EB101-EP14-BP8_Pressure_transmitter","","°C","s16","10","0","0","0","R"],
	44064 => ["EB101-EP14_Compressor_State","","","u8","1","0","0","0","R"],
	44065 => ["EB101-EP14_Compr._time_to_start","","","u8","1","0","0","0","R"],
	44066 => ["EB101-EP14_Relay_status","","","u16","1","0","0","0","R"],
	44067 => ["EB101-EP14_Heat_med._pump_status","","","u8","1","0","0","0","R"],
	44068 => ["EB101-EP14_Brine_pump_status","","","u8","1","0","0","0","R"],
	44069 => ["EB101-EP14_Compressor_starts","","","u32","1","0","0","0","R"],
	44071 => ["EB101-EP14_Tot._op.time_compr","","h","u32","1","0","0","0","R"],
	44073 => ["EB101-EP14_Tot._HW_op.time_compr","","h","u32","1","0","0","0","R"],
	44075 => ["EB101-EP14_Alarm_number","The value indicates the most severe current alarm","","u16","1","0","0","0","R"],
	44138 => ["EB108-EP15_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44139 => ["EB108-EP14_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44151 => ["EB107-EP15_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44152 => ["EB107-EP14_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44164 => ["EB106-EP15_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44165 => ["EB106-EP14_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44177 => ["EB105-EP15_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44178 => ["EB105-EP14_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44190 => ["EB104-EP15_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44191 => ["EB104-EP14_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44203 => ["EB103-EP15_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44204 => ["EB103-EP14_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44216 => ["EB102-EP15_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44217 => ["EB102-EP14_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44229 => ["EB101-EP15_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44230 => ["EB101-EP14_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44242 => ["EB100-EP15_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44243 => ["EB100-EP14_Prio","Indicates what need is assigned to the compressor module, 0 = Off, 1 = Heat, 2 = Hot water, 3 = Pool 1, 4 = Pool2","","u8","1","0","0","0","R"],
	44258 => ["External_supply_air_accessory_relays","Indicates the status of the relays on the external supply air accessory. The information is binary encoded. B0: relay K1 (QN40 close signal). B1: relay K2 (QN40 open signal)","","u8","1","0","0","0","R"],
	44266 => ["Cool_Degree_Minutes","","","s16","10","-30000","30000","0","R/W"],
	44267 => ["Calc._Cooling_Supply_Temperature_S4","","°C","s16","10","0","0","0","R"],
	44268 => ["Calc._Cooling_Supply_Temperature_S3","","°C","s16","10","0","0","0","R"],
	44269 => ["Calc._Cooling_Supply_Temperature_S2","","°C","s16","10","0","0","0","R"],
	44270 => ["Calc._Cooling_Supply_Temperature_S1","","°C","s16","10","0","0","0","R"],
	44276 => ["State_ACS","The state of the ACS accessory","","u8","1","0","0","0","R"],
	44277 => ["State_ACS_heatdump","The state of the heatdump in the ACS accessory","","u8","1","0","0","0","R"],
	44278 => ["State_ACS_cooldump","The state of the cooldump in the ACS accessory","","u8","1","0","0","0","R"],
	44282 => ["Used_cprs._HW","The number of compressors that's currently producing hot water","","u8","1","0","0","0","R"],
	44283 => ["Used_cprs._heat","The number of compressors that's currently producing heating","","u8","1","0","0","0","R"],
	44284 => ["Used_cprs._pool_1","The number of compressors that's currently producing poolheating for pool 1","","u8","1","0","0","0","R"],
	44285 => ["Used_cprs._pool_2","The number of compressors that's currently producing poolheating for pool 2","","u8","1","0","0","0","R"],
	44298 => ["Accumulated_energy,_parts","","kWh","u32","10","0","9999999","0","R"],
	44300 => ["Accumulated_energy,_parts","","kWh","u32","10","0","9999999","0","R"],
	44302 => ["Accumulated_energy,_parts","","kWh","u32","10","0","9999999","0","R"],
	44304 => ["Accumulated_energy,_parts","","kWh","u32","10","0","9999999","0","R"],
	44306 => ["Accumulated_energy,_parts","","kWh","u32","10","0","9999999","0","R"],
	44308 => ["Accumulated_energy,_parts","","kWh","u32","10","0","9999999","0","R"],
	44316 => ["calc._ou_compressor_freq","Calculated compressor frequency","Hz","u8","1","0","0","0","R"],
	44317 => ["SCA_accessory_relays","Indicates the status of the relays on the SCA accessory. The information is binary encoded. B0: relay K1 (Solar pump). B1: relay K2 (Solar Cooling Pump) B2: relay K3 (QN28)","","u8","1","0","0","0","R"],
	44320 => ["Used_cprs._cool","The number of compressors that's currently producing active cooling","","u8","1","0","0","0","R"],
	44322 => ["Speed_ext_cooling_pump_GP15","","%","s8","1","0","0","0","R"],
	44323 => ["Cooling_pump_manual_speed","Cooling pump speed if manual","%","s8","1","0","100","70","R/W"],
	44331 => ["Software_release","","","u8","1","0","0","0","R"],
	44362 => ["EB101-EP14-BT28_Outdoor_temp","","°C","s16","10","0","0","0","R"],
	44363 => ["EB101-EP14-BT16_Evaporator","","°C","s16","10","0","0","0","R"],
	45001 => ["Alarm_number","The value indicates the most severe current alarm","","s16","1","0","0","0","R"],
	47004 => ["Heat_curve_S4","Heat curve to use see manual for the different curves.","","s8","1","0","15","9","R/W"],
	47005 => ["Heat_curve_S3","Heat curve to use see manual for the different curves.","","s8","1","0","15","9","R/W"],
	47006 => ["Heat_curve_S2","Heat curve to use see manual for the different curves.","","s8","1","0","15","9","R/W"],
	47007 => ["Heat_curve_S1","Heat curve to use see manual for the different curves.","","s8","1","0","15","9","R/W"],
	47008 => ["Offset_S4","Offset of the heat curve","","s8","1","-10","10","0","R/W"],
	47009 => ["Offset_S3","Offset of the heat curve","","s8","1","-10","10","0","R/W"],
	47010 => ["Offset_S2","Offset of the heat curve","","s8","1","-10","10","0","R/W"],
	47011 => ["Offset_S1","Offset of the heat curve","","s8","1","-10","10","0","R/W"],
	47012 => ["Min_Supply_System_4","","°C","s16","10","50","700","200","R/W"],
	47013 => ["Min_Supply_System_3","","°C","s16","10","50","700","200","R/W"],
	47014 => ["Min_Supply_System_2","","°C","s16","10","50","700","200","R/W"],
	47015 => ["Min_Supply_System_1","","°C","s16","10","50","700","200","R/W"],
	47016 => ["Max_Supply_System_4","","°C","s16","10","50","700","600","R/W"],
	47017 => ["Max_Supply_System_3","","°C","s16","10","50","700","600","R/W"],
	47018 => ["Max_Supply_System_2","","°C","s16","10","50","700","600","R/W"],
	47019 => ["Max_Supply_System_1","","°C","s16","10","50","700","600","R/W"],
	47020 => ["Own_Curve_P7","User defined curve point","°C","s8","1","0","80","15","R/W"],
	47021 => ["Own_Curve_P6","User defined curve point","°C","s8","1","0","80","15","R/W"],
	47022 => ["Own_Curve_P5","User defined curve point","°C","s8","1","0","80","26","R/W"],
	47023 => ["Own_Curve_P4","User defined curve point","°C","s8","1","0","80","32","R/W"],
	47024 => ["Own_Curve_P3","User defined curve point","°C","s8","1","0","80","35","R/W"],
	47025 => ["Own_Curve_P2","User defined curve point","°C","s8","1","0","80","40","R/W"],
	47026 => ["Own_Curve_P1","User defined curve point","°C","s8","1","0","80","45","R/W"],
	47027 => ["Point_offset_outdoor_temp.","Outdoor temperature point where the heat curve is offset","°C","s8","1","-40","30","0","R/W"],
	47028 => ["Point_offset","Amount of offset at the point offset temperature","°C","s8","1","-10","10","0","R/W"],
	47029 => ["External_adjustment_S4","Change of the offset of the heat curve when closing the external adjustment input","","s8","1","-10","10","0","R/W"],
	47030 => ["External_adjustment_S3","Change of the offset of the heat curve when closing the external adjustment input","","s8","1","-10","10","0","R/W"],
	47031 => ["External_adjustment_S2","Change of the offset of the heat curve when closing the external adjustment input","","s8","1","-10","10","0","R/W"],
	47032 => ["External_adjustment_S1","Change of the offset of the heat curve when closing the external adjustment input","","s8","1","-10","10","0","R/W"],
	47033 => ["External_adjustment_with_room_sensor_S4","Room temperature setting when closing the external adjustment input","°C","s16","10","50","300","200","R/W"],
	47034 => ["External_adjustment_with_room_sensor_S3","Room temperature setting when closing the external adjustment input","°C","s16","10","50","300","200","R/W"],
	47035 => ["External_adjustment_with_room_sensor_S2","Room temperature setting when closing the external adjustment input","°C","s16","10","50","300","200","R/W"],
	47036 => ["External_adjustment_with_room_sensor_S1","Room temperature setting when closing the external adjustment input","°C","s16","10","50","300","200","R/W"],
	47041 => ["Hot_water_mode"," 0=Economy 1=Normal 2=Luxury","","s8","1","0","2","1","R/W"],
	47043 => ["Start_temperature_HW_Luxury","Start temperature for heating water","°C","s16","10","50","700","470","R/W"],
	47044 => ["Start_temperature_HW_Normal","Start temperature for heating water","°C","s16","10","50","700","450","R/W"],
	47045 => ["Start_temperature_HW_Economy","Start temperature for heating water","°C","s16","10","50","700","380","R/W"],
	47046 => ["Stop_temperature_Periodic_HW","Temperature where hot water generation will stop","°C","s16","10","550","700","550","R/W"],
	47047 => ["Stop_temperature_HW_Luxury","Temperature where hot water generation will stop","°C","s16","10","50","700","520","R/W"],
	47048 => ["Stop_temperature_HW_Normal","Temperature where hot water generation will stop","°C","s16","10","50","700","500","R/W"],
	47049 => ["Stop_temperature_HW_Economy","Temperature where hot water generation will stop","°C","s16","10","50","700","430","R/W"],
	47050 => ["Periodic_HW","Activates the periodic hot water generation","","s8","1","0","1","1","R/W"],
	47051 => ["Periodic_HW_Interval","Interval between Periodic hot water sessions","days","s8","1","1","90","14","R/W"],
	47054 => ["Run_time_HWC","Run time for the hot water circulation system","min","s8","1","1","60","3","R/W"],
	47055 => ["Still_time_HWC","Still time for the hot water circulation system","min","s8","1","0","60","12","R/W"],
	47062 => ["HW_charge_offset","Offset of HW charge temperature from the stop temperature","°C","s8","10","0","0","0","R/W"],
	47092 => ["Manual_compfreq_HW","Should the compressor frequency be manual set in HW?","","u8","1","0","0","0","R/W"],
	47093 => ["Manual_compfreq_speed_HW","Manual compressor frequency in HW?","Hz","u16","1","0","0","0","R/W"],
	47094 => ["Sec_per_compfreq_step","Time between changes of the copmpressor frequency","s","u8","1","0","0","0","R/W"],
	47095 => ["Max_compfreq_step","Largest allowed change of compressor frequency in normal run","Hz","u8","1","0","0","0","R/W"],
	47096 => ["Manual_compfreq_Heating","Should the compressor frequency be manual set in Heating?","","u8","1","0","0","0","R/W"],
	47097 => ["Min_speed_after_start","Time with minimum compressor frequency when heating demand occurs","Min","u8","1","0","0","0","R/W"],
	47098 => ["Min_speed_after_HW","Should the compressor frequency be manual set in HW?","Min","u8","1","0","0","0","R/W"],
	47099 => ["GMz","Compressor frequency regulator GMz","","u8","1","0","0","0","R/W"],
	47100 => ["Max_diff_VBF-BerVBF","Largest allowed difference between Supply and calc supply","°C","u8","10","0","0","0","R/W"],
	47101 => ["Comp_freq_reg_P","Compressor frequency regulator P","","u8","1","0","0","0","R/W"],
	47102 => ["Comp_freq_max_delta_F","Maximum change of copmpressor frequency in compressor frequency regulator","Hz","s8","1","0","0","0","R/W"],
	47103 => ["Min_comp_freq","Minimum allowed compressor frequency","Hz","s16","1","0","0","0","R/W"],
	47104 => ["Max_comp_freq","Maximum allowed compressor frequency","Hz","s16","1","0","0","0","R/W"],
	47105 => ["Comp_freq_heating","Compressor frequency used in heating mode","Hz","s16","1","0","0","0","R/W"],
	47131 => ["Language","Display language in the heat pump 0=English 1=Svenska 2=Deutsch 3=Francais 4=Espanol 5=Suomi 6=Lietuviu 7=Cesky 8=Polski 9=Nederlands 10=Norsk 11=Dansk 12=Eesti 13=Latviesu 16=Magyar","","s8","1","0","18","0","R/W"],
	47134 => ["Period_HW","","min","u8","1","0","180","20","R/W"],
	47135 => ["Period_Heat","","min","u8","1","0","180","20","R/W"],
	47136 => ["Period_Pool","","min","u8","1","0","180","20","R/W"],
	47138 => ["Operational_mode_heat_medium_pump"," 10=Intermittent 20=Continous 30=Economy 40=Auto","","u8","1","10","40","40","R/W"],
	47139 => ["Operational_mode_brine_medium_pump"," 10=Intermittent 20=Continuous 30=Economy 40=Auto","","u8","1","10","30","10","R/W"],
	47206 => ["DM_start_heating","The value the degree minutes needed to be reached for the pump to start heating","","s16","1","-1000","-30","-60","R/W"],
	47207 => ["DM_start_cooling","The value the degree minutes needed to be reached for the pump to start cooling","","s16","1","0","0","0","R/W"],
	47208 => ["DM_start_add.","The value the degree minutes needed to be reached for the pump to start electric addition","","s16","1","0","0","0","R/W"],
	47209 => ["DM_between_add._steps","The number of degree minutes between start of each electric addition step","","s16","1","0","0","0","R/W"],
	47210 => ["DM_start_add._with_shunt","","","s16","1","-2000","-30","-400","R/W"],
	47212 => ["Max_int_add._power","","kW","s16","100","0","4500","600","R/W"],
	47214 => ["Fuse","Size of the fuse that the HP is connected to","A","u8","1","1","200","16","R/W"],
	47261 => ["Exhaust_Fan_speed_4","","%","u8","1","0","100","100","R/W"],
	47262 => ["Exhaust_Fan_speed_3","","%","u8","1","0","100","80","R/W"],
	47263 => ["Exhaust_Fan_speed_2","","%","u8","1","0","100","30","R/W"],
	47264 => ["Exhaust_Fan_speed_1","","%","u8","1","0","100","0","R/W"],
	47265 => ["Exhaust_Fan_speed_normal","","%","u8","1","0","100","65","R/W"],
	47266 => ["Supply_Fan_speed_4","","%","u8","1","0","100","90","R/W"],
	47267 => ["Supply_Fan_speed_3","","%","u8","1","0","100","70","R/W"],
	47268 => ["Supply_Fan_speed_2","","%","u8","1","0","100","25","R/W"],
	47269 => ["Supply_Fan_speed_1","","%","u8","1","0","100","0","R/W"],
	47270 => ["Supply_Fan_speed_normal","","%","u8","1","0","100","60","R/W"],
	47271 => ["Fan_return_time_4","Time from a changed fan speed until it returns to normal speed","h","u8","1","1","99","4","R/W"],
	47272 => ["Fan_return_time_3","Time from a changed fan speed until it returns to normal speed","h","u8","1","1","99","4","R/W"],
	47273 => ["Fan_return_time_2","Time from a changed fan speed until it returns to normal speed","h","u8","1","1","99","4","R/W"],
	47274 => ["Fan_return_time_1","Time from a changed fan speed until it returns to normal speed","h","u8","1","1","99","4","R/W"],
	47275 => ["Filter_Reminder_period","Time between the reminder of filter replacement/cleaning.","Months","u8","1","1","24","3","R/W"],
	47276 => ["Floor_drying"," 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47277 => ["Floor_drying_period_7","Days each period is active","days","u8","1","0","30","2","R/W"],
	47278 => ["Floor_drying_period_6","Days each period is active","days","u8","1","0","30","2","R/W"],
	47279 => ["Floor_drying_period_5","Days each period is active","days","u8","1","0","30","2","R/W"],
	47280 => ["Floor_drying_period_4","Days each period is active","days","u8","1","0","30","3","R/W"],
	47281 => ["Floor_drying_period_3","Days each period is active","days","u8","1","0","30","2","R/W"],
	47282 => ["Floor_drying_period_2","Days each period is active","days","u8","1","0","30","2","R/W"],
	47283 => ["Floor_drying_period_1","Days each period is active","days","u8","1","0","30","2","R/W"],
	47284 => ["Floor_drying_temp._7","Supply temperature each period","°C","u8","1","15","70","20","R/W"],
	47285 => ["Floor_drying_temp._6","Supply temperature each period","°C","u8","1","15","70","30","R/W"],
	47286 => ["Floor_drying_temp._5","Supply temperature each period","°C","u8","1","15","70","40","R/W"],
	47287 => ["Floor_drying_temp._4","Supply temperature each period","°C","u8","1","15","70","45","R/W"],
	47288 => ["Floor_drying_temp._3","Supply temperature each period","°C","u8","1","15","70","40","R/W"],
	47289 => ["Floor_drying_temp._2","Supply temperature each period","°C","u8","1","15","70","30","R/W"],
	47290 => ["Floor_drying_temp._1","Supply temperature each period","°C","u8","1","15","70","20","R/W"],
	47291 => ["Floor_drying_timer","","hrs","u16","1","0","10000","0","R"],
	47292 => ["Trend_temperature","Above the set outdoor temperature the addition activation time is limited to give the compressor more time to raise the hot water temperature.","°C","s16","10","0","200","70","R/W"],
	47293 => ["Transfer_time_HW-Heat","Time between hot water and heating operating mode","mins","s8","1","1","60","15","R/W"],
	47294 => ["Use_airflow_defrost","If reduced airflow should start defrost","","u8","1","0","0","0","R/W"],
	47295 => ["Airflow_reduction_trig","How much the airflow is allowed to be reduced before a defrost is trigged","%","u8","1","0","0","0","R/W"],
	47296 => ["Airflow_defrost_done","How much the airflow has to raise before a defrost is ended","%","u8","1","0","0","0","R/W"],
	47297 => ["Initiate_inverter","Start initiation process of the inverter","","u8","1","0","0","0","R/W"],
	47298 => ["Force_inverter_init","Force inverter initiation process of the inverter","","u8","1","0","0","0","R/W"],
	47299 => ["Min_time_defrost","Minimum duration of the defrost","min","u8","1","0","0","0","R/W"],
	47300 => ["DOT","Dimensioning outdoor temperature","°C","s16","10","-400","200","-180","R/W"],
	47301 => ["delta_T_at_DOT","Delta T (BT12-BT3)at dimensioning outdoor temperature","°C","s16","10","0","250","100","R/W"],
	47302 => ["Climate_system_2_accessory","Activates the climate system 2 accessory 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47303 => ["Climate_system_3_accessory","Activates the climate system 3 accessory 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47304 => ["Climate_system_4_accessory","Activates the climate system 4 accessory 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47305 => ["Climate_system_4_mixing_valve_amp.","Mixing valve amplification for extra climate systems","","s8","10","1","100","10","R/W"],
	47306 => ["Climate_system_3_mixing_valve_amp.","Mixing valve amplification for extra climate systems","","s8","10","1","100","10","R/W"],
	47307 => ["Climate_system_2_mixing_valve_amp.","Mixing valve amplification for extra climate systems","","s8","10","1","100","10","R/W"],
	47308 => ["Climate_system_4_shunt_wait","Wait time between changes of the shunt in extra climate systems","secs","s16","10","10","300","30","R/W"],
	47309 => ["Climate_system_3_shunt_wait","Wait time between changes of the shunt in extra climate systems","secs","s16","10","10","300","30","R/W"],
	47310 => ["Climate_system_2_shunt_wait","Wait time between changes of the shunt in extra climate systems","secs","s16","10","10","300","30","R/W"],
	47312 => ["FLM_pump","Operating mode for the FLM pump 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47313 => ["FLM_defrost","Minimum time between defrost in FLM","hrs","u8","1","1","30","10","R/W"],
	47317 => ["Shunt_controlled_add._accessory","Activates the shunt controlled addition accessory 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47318 => ["Shunt_controlled_add._min._temp.","","°C","s8","1","5","90","55","R/W"],
	47319 => ["Shunt_controlled_add._min._runtime","","hrs","u8","1","0","48","12","R/W"],
	47320 => ["Shunt_controlled_add._mixing_valve_amp.","Mixing valve amplification for shunt controlled add.","","s8","10","1","100","10","R/W"],
	47321 => ["Shunt_controlled_add._mixing_valve_wait","Wait time between changes of the shunt in shunt controlled add.","secs","s16","1","10","300","30","R/W"],
	47322 => ["Step_controlled_add._accessory","Activates the step controlled addition accessory 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47323 => ["Step_controlled_add._start_DM","DM where the first step of step controlled add. starts","","s16","1","-2000","-30","-400","R/W"],
	47324 => ["Step_controlled_add._diff._DM","Difference in DM of each step in the step controlled add.","","s16","1","0","1000","100","R/W"],
	47326 => ["Step_controlled_add._mode","Binary or linear stepping method. 0=Linear 1=Binary","","u8","1","0","1","0","R/W"],
	47327 => ["Ground_water_pump_accessory","Ground water pump using AXC40 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47329 => ["Cooling_2-pipe_accessory","Activates the 2-pipe cooling accessory 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47330 => ["Cooling_4-pipe_accessory","Activates the 4-pipe cooling accessory 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47335 => ["Time_betw._switch_heat/cool","Time between switching from heating to cooling or vice versa.","h","s8","1","0","48","2","R/W"],
	47336 => ["Heat_at_room_under_temp.","This value indicates how many degrees under set room temp heating will be allowed","°C","s8","10","5","100","10","R/W"],
	47337 => ["Cool_at_room_over_temp.","This value indicates how many degrees over set room temp cooling will be allowed","°C","s8","10","5","100","10","R/W"],
	47338 => ["Cooling_mix._valve_amp.","Mixing valve amplification for the cooling valve","","s8","10","1","100","10","R/W"],
	47339 => ["Cooling_mix._valve_step_delay","","","s16","1","10","300","30","R/W"],
	47340 => ["Cooling_with_room_sensor","Enables use of room sensor together with cooling 0=Off 1=On","","u8","10","0","1","0","R/W"],
	47341 => ["HPAC_accessory","Activates the HPAC accessory","","u8","1","0","1","0","R/W"],
	47342 => ["HPAC_DM_start_passive_cooling","Value the degree minutes have to reach for the HPAC to start passive cooling","","s16","1","10","200","30","R/W"],
	47343 => ["HPAC_DM_start_active_cooling","Value the degree minutes have to reach for the HPAC to start active cooling","","s16","1","10","300","90","R/W"],
	47351 => ["FJVM_accessory","Activates the FJVM accessory 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47352 => ["SMS40_accessory","Activates the SMS40 accessory","","u8","1","0","1","0","R/W"],
	47365 => ["RMU_System_1","Activates the RMU accessory for system 1","","u8","1","0","1","0","R/W"],
	47366 => ["RMU_System_2","Activates the RMU accessory for system 2","","u8","1","0","1","0","R/W"],
	47367 => ["RMU_System_3","Activates the RMU accessory for system 3","","u8","1","0","1","0","R/W"],
	47368 => ["RMU_System_4","Activates the RMU accessory for system 4","","u8","1","0","1","0","R/W"],
	47370 => ["Allow_Additive_Heating","Whether to allow additive heating (only valid for operational mode Manual)","","u8","1","0","1","1","R/W"],
	47371 => ["Allow_Heating","Whether to allow heating (only valid for operational mode Manual or Add. heat only)","","u8","1","0","1","1","R/W"],
	47372 => ["Allow_Cooling","Whether to allow cooling (only valid for operational mode Manual or Add. heat only)","","u8","1","0","1","1","R/W"],
	47378 => ["Max_diff._comp.","","°C","s16","10","10","250","100","R/W"],
	47379 => ["Max_diff._add.","","°C","s16","10","10","240","70","R/W"],
	47380 => ["Low_brine_out_autoreset"," 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47381 => ["Low_brine_out_temp.","","°C","s16","10","-120","150","-80","R/W"],
	47382 => ["High_brine_in","Activates the High brine in temperature alarm. 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47383 => ["High_brine_in_temp.","The brine in temperature that triggers the high brine in temperature alarm (if active).","°C","s16","10","100","300","200","R/W"],
	47384 => ["Date_format"," 1=DD-MM-YY 2=YY-MM-DD","","u8","1","1","2","1","R/W"],
	47385 => ["Time_format"," 12=12 hours 24=24 Hours","","u8","1","12","24","24","R/W"],
	47387 => ["HW_production","Activates hot water production where applicable 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47388 => ["Alarm_lower_room_temp.","Lowers the room temperature during red light alarms to notify the occupants of the building that something is the matter 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47389 => ["Alarm_lower_HW_temp.","Lowers the hot water temperature during red light alarms to notify the occupants of the building that something is the matter 0=Off 1=On","","u8","1","0","1","1","R/W"],
	47391 => ["Use_room_sensor_S4","When activated the system uses the room sensor 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47392 => ["Use_room_sensor_S3","When activated the system uses the room sensor 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47393 => ["Use_room_sensor_S2","When activated the system uses the room sensor 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47394 => ["Use_room_sensor_S1","When activated the system uses the room sensor 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47395 => ["Room_sensor_setpoint_S4","Sets the room temperature setpoint for the system","°C","s16","10","50","300","200","R/W"],
	47396 => ["Room_sensor_setpoint_S3","Sets the room temperature setpoint for the system","°C","s16","10","50","300","200","R/W"],
	47397 => ["Room_sensor_setpoint_S2","Sets the room temperature setpoint for the system","°C","s16","10","50","300","200","R/W"],
	47398 => ["Room_sensor_setpoint_S1","Sets the room temperature setpoint for the system","°C","s16","10","50","300","200","R/W"],
	47399 => ["Room_sensor_factor_S4","Setting of how much the difference between set and actual room temperature should affect the supply temperature.","","u8","10","0","60","20","R/W"],
	47400 => ["Room_sensor_factor_S3","Setting of how much the difference between set and actual room temperature should affect the supply temperature.","","u8","10","0","60","20","R/W"],
	47401 => ["Room_sensor_factor_S2","Setting of how much the difference between set and actual room temperature should affect the supply temperature.","","u8","10","0","60","20","R/W"],
	47402 => ["Room_sensor_factor_S1","Setting of how much the difference between set and actual room temperature should affect the supply temperature.","","u8","10","0","60","20","R/W"],
	47413 => ["Speed_circ.pump_HW","","%","u8","1","0","100","70","R/W"],
	47414 => ["Speed_circ.pump_Heat","","%","u8","1","0","100","70","R/W"],
	47415 => ["Speed_circ.pump_Pool","","%","u8","1","0","100","70","R/W"],
	47416 => ["Speed_circ.pump_Economy","","%","u8","1","0","100","70","R/W"],
	47417 => ["Speed_circ.pump_Cooling","","%","u8","1","0","100","70","R/W"],
	47418 => ["Speed_brine_pump","","%","u8","1","0","100","75","R/W"],
	47442 => ["preset_flow_clim._sys.","Preset flow setting for climate system. 0 = manual setting, 1 = radiator, 2 = floor heating, 3 = radiator + floor heating.","","u8","1","0","3","1","R/W"],
	47473 => ["Max_time_defrost","Maximum duration of the defrost","min","u8","1","0","0","0","R/W"],
	47536 => ["Fan_synch_mode","If the fan should have a lower speed when the compressor is not running 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47537 => ["Night_cooling","If the fan should have a higher speed when there is a high room temp and a low outdoor temp. 0=Off 1=On","","u8","1","0","1","0","R/W"],
	47538 => ["Start_room_temp._night_cooling","","°C","u8","1","20","30","25","R/W"],
	47539 => ["Night_Cooling_Min._diff.","Minimum difference between room temp and outdoor temp to start night cooling","°C","u8","1","3","10","6","R/W"],
	47540 => ["Heat_DM_diff","Difference in DM between compressor starts in heating mode","","s16","1","10","2000","60","R/W"],
	47543 => ["Cooling_DM_diff","Difference in DM between compressor starts in cooling mode","","s16","1","0","2000","30","R/W"],
	47555 => ["DEW_accessory","Activates the DEW accessory","","u8","1","0","1","0","R/W"],
	47556 => ["DEH_accessory","Activates the DEH accessory","","u8","1","0","1","0","R/W"],
	47564 => ["Allow_Heating_Sys1","Whether to allow heating for system 1 (only valid for operational mode Manual or Add. heat only)","","u8","1","0","1","1","R/W"],
	47565 => ["Allow_Heating_Sys2","Whether to allow heating for system 2 (only valid for operational mode Manual or Add. heat only)","","u8","1","0","1","1","R/W"],
	47570 => ["Operational_mode","The operational mode of the heat pump 0=Auto 1=Manual 2=Add. heat only","","u8","1","0","0","0","R/W"],
	47613 => ["Max_Internal_Add","Maximum allowed steps for the internally connected addition.","","u8","1","0","7","3","R/W"],
	47614 => ["Int._connected_add._mode","Binary or linear stepping method for the internally connected external addition. 0=Linear 1=Binary","","u8","1","0","1","0","R/W"],
	47629 => ["DM_start_ext._add.","","","s16","1","-2000","-30","-1400","R/W"],
	47631 => ["External_add_step_controlled","Puts the external addition i step mode","","u8","1","0","1","0","R/W"],
	47632 => ["External_add._min._runtime","Min. runtime, only relevant if not step mode","hrs","u8","1","0","48","12","R/W"],
	47633 => ["State_ext._add.","Only relevant if not in step mode","","u8","1","0","0","0","R"],
	48053 => ["FLM_2_speed_4","","%","u8","1","0","100","100","R/W"],
	48054 => ["FLM_2_speed_3","","%","u8","1","0","100","80","R/W"],
	48055 => ["FLM_2_speed_2","","%","u8","1","0","100","30","R/W"],
	48056 => ["FLM_2_speed_1","","%","u8","1","0","100","0","R/W"],
	48057 => ["FLM_2_speed_normal","","%","u8","1","0","100","65","R/W"],
	48058 => ["FLM_3_speed_4","","%","u8","1","0","100","100","R/W"],
	48059 => ["FLM_3_speed_3","","%","u8","1","0","100","80","R/W"],
	48060 => ["FLM_3_speed_2","","%","u8","1","0","100","30","R/W"],
	48061 => ["FLM_3_speed_1","","%","u8","1","0","100","0","R/W"],
	48062 => ["FLM_3_speed_normal","","%","u8","1","0","100","65","R/W"],
	48063 => ["FLM_4_speed_4","","%","u8","1","0","100","100","R/W"],
	48064 => ["FLM_4_speed_3","","%","u8","1","0","100","80","R/W"],
	48065 => ["FLM_4_speed_2","","%","u8","1","0","100","30","R/W"],
	48066 => ["FLM_4_speed_1","","%","u8","1","0","100","0","R/W"],
	48067 => ["FLM_4_speed_normal","","%","u8","1","0","100","65","R/W"],
	48068 => ["FLM_4_accessory","Activates the FLM 4 accessory","","u8","1","0","1","0","R/W"],
	48069 => ["FLM_3_accessory","Activates the FLM 3 accessory","","u8","1","0","1","0","R/W"],
	48070 => ["FLM_2_accessory","Activates the FLM 2 accessory","","u8","1","0","1","0","R/W"],
	48071 => ["FLM_1_accessory","Activates the FLM 1 accessory","","u8","1","0","1","0","R/W"],
	48072 => ["DM_diff_start_add.","The value below the last compressor step the degree minutes needed to be reached for the pump to start electric addition","","s16","1","0","0","0","R/W"],
	48073 => ["FLM_cooling","FLM cooling activated","","u8","1","0","1","0","R/W"],
	48074 => ["Set_point_for_BT74","Set point for change between cooling and heating when using BT74","","s16","10","50","400","210","R/W"],
	48085 => ["Heat_medium_pump_manual_speed","Heat medium pump speed if manual","%","s8","1","0","100","70","R/W"],
	48086 => ["Hot_water_tank_type"," 10=VPB 20=VPA","","u8","1","10","20","20","R/W"],
	48087 => ["Pool_2_accessory","Activate the pool 2 accessory","","u8","1","0","1","0","R/W"],
	48088 => ["Pool_1_accessory","Activates the pool 1 accessory","","u8","1","0","1","0","R/W"],
	48089 => ["Pool_2_start_temp.","The Temperature below which the pool heating should start","°C","s16","10","50","800","220","R/W"],
	48090 => ["Pool_1_start_temp.","The Temperature below which the pool heating should start","°C","s16","10","50","800","220","R/W"],
	48091 => ["Pool_2_stop_temp.","The Temperature at which the pool heating will stop","°C","s16","10","50","800","240","R/W"],
	48092 => ["Pool_1_stop_temp.","The Temperature at which the pool heating will stop","°C","s16","10","50","800","240","R/W"],
	48093 => ["Pool_2_Activated","Activates pool heating","","u8","1","0","1","1","R/W"],
	48094 => ["Pool_1_Activated","Activates pool heating","","u8","1","0","1","1","R/W"],
	48099 => ["External_add._accessory","Activates the external addition accessory","","u8","1","0","1","0","R/W"],
	48102 => ["Speed_heat_medium_pump","","%","u16","2","0","0","0","R"],
	48103 => ["Speed_charge_pump","","%","u16","2","0","0","0","R"],
	48107 => ["Charge_pump_manual_speed","Charge pump speed if manual","%","s8","1","0","100","70","R/W"],
	48120 => ["HW_Comfort","Activates the HW Comfort Accessory.","","u8","1","0","1","0","R/W"],
	48130 => ["Manual_heat_medium_pump_speed","Manual heat medium pump speed?","%","s8","1","0","1","0","R/W"],
	48131 => ["Manual_charge_pump_speed","Manual charge pump speed?","%","s8","1","0","1","0","R/W"],
	48133 => ["Period_Pool_2","","min","u8","1","0","180","0","R/W"],
	48134 => ["Operational_mode_charge_pump","","","u8","1","10","20","20","R/W"],
	48139 => ["DM_startdiff_add._with_shunt","","","s16","1","0","2000","400","R/W"],
	48140 => ["Max_pool_2_compr.","Maximum number of compressors that are simultaneously charging the pool","","u8","1","1","18","18","R/W"],
	48141 => ["Max_pool_1_compr.","Maximum number of compressors that are simultaneously charging the pool","","u8","1","1","18","18","R/W"],
	48142 => ["Step_controlled_add._start_DM","DM diff from last compressor step where the first step of step controlled add. starts","","s16","1","0","2000","400","R/W"],
	48144 => ["HW_Comfort_add_during_Heat","Allows the HW Comfort addition to run during heating.","","u8","1","0","1","0","R/W"],
	48145 => ["HW_Comfort_mixing_valve","Activates the HW Comfort Shunt.","","u8","1","0","1","0","R/W"],
	48146 => ["HW_Comfort_mixing_valve_amp.","Mixing valve amplification for the HW Comfort Accessory","","s8","10","1","100","10","R/W"],
	48147 => ["HW_Comfort_mixing_valve_wait","Wait time between changes of the mixing valve for the HW Comfort Accessory","secs","s16","10","10","300","30","R/W"],
	48148 => ["HW_Comfort_hotwater_temperature","The desired hotwater temperature","°C","s8","10","40","65","55","R/W"],
	48156 => ["External_cooling_accessory","Activates the external cooling accessory","","u8","1","0","1","0","R/W"],
	48157 => ["HW_Comfort_add.","Activates the HW Comfort Addition.","","u8","1","0","1","0","R/W"],
	48158 => ["SAM_supply_air_curve:_outdoor_temp_T3","The supply air curve is defined by 3 supply air temperatures at 3 different outdoor temperatures T1, T2 and T3.","°C","s16","10","-400","200","150","R/W"],
	48159 => ["SAM_supply_air_curve:_outdoor_temp_T2","The supply air curve is defined by 3 supply air temperatures at 3 different outdoor temperatures T1, T2 and T3.","°C","s16","10","-390","190","0","R/W"],
	48160 => ["SAM_supply_air_curve:_outdoor_temp_T1","The supply air curve is defined by 3 supply air temperatures at 3 different outdoor temperatures T1, T2 and T3.","°C","s16","10","-400","200","-150","R/W"],
	48161 => ["SAM_supply_air_curve:_supply_air_temp_at_T3","The supply air curve is defined by 3 supply air temperatures at 3 different outdoor temperatures T1, T2 and T3.","°C","s16","10","160","520","220","R/W"],
	48162 => ["SAM_supply_air_curve:_supply_air_temp_at_T2","The supply air curve is defined by 3 supply air temperatures at 3 different outdoor temperatures T1, T2 and T3.","°C","s16","10","160","520","220","R/W"],
	48163 => ["SAM_supply_air_curve:_supply_air_temp_at_T1","The supply air curve is defined by 3 supply air temperatures at 3 different outdoor temperatures T1, T2 and T3.","°C","s16","10","160","520","220","R/W"],
	48174 => ["Min_cooling_supply_temp_S4","Minimum allowed supply temperature during cooling","°C","s8","1","5","50","18","R/W"],
	48175 => ["Min_cooling_supply_temp_S3","Minimum allowed supply temperature during cooling","°C","s8","1","5","50","18","R/W"],
	48176 => ["Min_cooling_supply_temp_S2","Minimum allowed supply temperature during cooling","°C","s8","1","5","50","18","R/W"],
	48177 => ["Min_cooling_supply_temp_S1","Minimum allowed supply temperature during cooling","°C","s8","1","5","50","18","R/W"],
	48178 => ["Cooling_supply_temp._at_20°C","Supply Temperature at 20°C. Used to create cooling curve","°C","s8","1","5","50","25","R/W"],
	48179 => ["Cooling_supply_temp._at_20°C","Supply Temperature at 20°C. Used to create cooling curve","°C","s8","1","5","50","25","R/W"],
	48180 => ["Cooling_supply_temp._at_20°C","Supply Temperature at 20°C. Used to create cooling curve","°C","s8","1","5","50","25","R/W"],
	48181 => ["Cooling_supply_temp._at_20°C","Supply Temperature at 20°C. Used to create cooling curve","°C","s8","1","5","50","25","R/W"],
	48182 => ["Cooling_supply_temp._at_40°C","Supply Temperature at 40°C. Used to create cooling curve","°C","s8","1","5","50","18","R/W"],
	48183 => ["Cooling_supply_temp._at_40°C","Supply Temperature at 40°C. Used to create cooling curve","°C","s8","1","5","50","18","R/W"],
	48184 => ["Cooling_supply_temp._at_40°C","Supply Temperature at 40°C. Used to create cooling curve","°C","s8","1","5","50","18","R/W"],
	48185 => ["Cooling_supply_temp._at_40°C","Supply Temperature at 40°C. Used to create cooling curve","°C","s8","1","5","50","18","R/W"],
	48186 => ["Cooling_use_mix._valves","Close use valves during cooling mode","","u8","1","0","1","0","R/W"],
	48187 => ["Cooling_use_mix._valves","Close use valves during cooling mode","","u8","1","0","1","0","R/W"],
	48188 => ["Cooling_use_mix._valves","Close use valves during cooling mode","","u8","1","0","1","0","R/W"],
	48189 => ["Cooling_use_mix._valves","Close use valves during cooling mode","","u8","1","0","0","0","R/W"],
	48190 => ["Heatdump_mix._valve_delay","Mixing valve step delay for the heatdump valve","s","s16","1","10","300","30","R/W"],
	48191 => ["Heatdump_mix._valve_amp.","Mixing valve amplification for the heatdump valve","","s8","10","1","100","10","R/W"],
	48192 => ["Cooldump_mix._valve_delay","Mixing valve step delay for the cooldump valve for the ACS-system","s","s16","1","10","300","30","R/W"],
	48193 => ["Cooldump_mix._valve_amp.","Mixing valve amplification for the cooldump valve for the ACS-system","","s8","10","1","100","10","R/W"],
	48194 => ["ACS_accessory","Activate the ACS accessory","","u8","1","0","1","0","R/W"],
	48195 => ["ACS_heat_dump_24h-function","","","u8","1","0","1","0","R/W"],
	48196 => ["ACS_run_brinepump_in_wait_mode","","","u8","1","0","1","0","R/W"],
	48197 => ["ACS_closingtime_for_cool_dump","","s","u8","1","0","100","100","R/W"],
	48198 => ["ACS_max_cprs_in_active_cooling","","","u8","1","0","18","18","R/W"],
	48199 => ["ACS_max_brinepumps_in_passive_cooling","","","u8","1","0","18","18","R/W"],
	48201 => ["SCA_accessory","Activates the SCA accessory","","u8","1","0","1","0","R/W"],
	48207 => ["Period_Cool","","min","u8","1","0","180","20","R/W"],
	48208 => ["Operational_mode_cool_pump","","","u8","1","0","1","0","R/W"],
	48214 => ["Cooling_delta_temp._at_20°C","Delta Temperature at 20°C. Used to control charge pump speed","°C","s8","1","2","10","3","R/W"],
	48215 => ["Cooling_delta_temp._at_40°C","Delta Temperature at 40°C. Used to control charge pump speed","°C","s8","1","2","20","6","R/W"],
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
