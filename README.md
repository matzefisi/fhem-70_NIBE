# Install / Update FHEM modules

Load the modules into FHEM:

    update all https://raw.githubusercontent.com/matzefisi/fhem-70_NIBE/devio/controls_70_NIBE.txt
Restart FHEM:
    
    shutdown restart

# Prerequisite

- Export from NIBE ModbusManager
  - Select model in menu Models
  - Goto File / Export to file
  - Put the file into the directory defined in device "global" attribute "modpath" or use attribute "modbusFile" in the logical module at FHEM master

# Configuration options

1. Integration with program 'nibegw' 
2. Solution using FHEM2FHEM

# 1. Integration with program 'nibegw' 

'nibegw' is an application that read telegrams from a serial port (which requires an RS-485 adapter), sends ACK/NAK to the heat pump and relays untouched telegrams via UDP packets. The FHEM module will listen to a UDP port and parse register data from UDP telegrams.

Run 'nibegw' like described here https://github.com/openhab/openhab2-addons/blob/master/addons/binding/org.openhab.binding.nibeheatpump/README.md

Define FHEM modules like

- physical module

      define NibeUDP NIBE_UDP <nibegw-ipaddress>

- logical module

      define Nibe NIBE
      attr NIBE modbusFile <absolute file path>   <-- optional, default <global-modpath>/export.csv
    

# 2. Solution using FHEM2FHEM

FHEM modules are used for both reading from serial port as well as parsing data. That requires two FHEM installations to separate the different tasks. Otherwise the accuracy of sending acknowledge (ACK and NAK) can't be met and the head pump will raise an alarm and go in alarm state.

## FHEM remote (connected to Nibe)

- physical module:

      define NibeWP NIBE_485 /dev/ttyAMA0

- logical module:

      define Nibe NIBE
      attr Nibe IODev NibeWP   <-- will be set by FHEM automatically
      attr Nibe ignore 1       <-- otherwise messages will be parsed on remote FHEM too (time critical)

## Fhem master

- physical module (dummy for FHEM2FHEM)

      define NibeWP NIBE_485 none
      attr NibeWP dummy 1

- FHEM2FHEM

      define Fhem_on_RPi FHEM2FHEM 192.168.2.47 RAW:NibeWP

- logical module

      define Nibe NIBE
      attr NIBE modbusFile <absolute file path>   <-- optional, default <global-modpath>/export.csv
