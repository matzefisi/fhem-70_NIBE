Prerequisite
------------

- Export from NIBE ModbusManager
  - Select model in menu Models
  - Goto File / Export to file
  - Put the file into the directory defined in device "global" attribute "modpath" or use attribute "modbusFile" in the logical module at Fhem master

Fhem remote (connected to Nibe)
-------------------------------

- physical module:<br>
define NibeWP NIBE_485 /dev/ttyAMA0

- logical module:<br>
define Nibe NIBE<br>
attr Nibe IODev NibeWP   &lt;-- will be set by Fhem automatically<br>
attr Nibe ignore 1       &lt;-- otherwise messages will be parsed on remote Fhem too (time critical)

Fhem master
-----------

- physical module (dummy for FHEM2FHEM)<br>
define NibeWP NIBE_485 none<br>
attr NibeWP dummy 1

- FHEM2FHEM<br>
define Fhem_on_RPi FHEM2FHEM 192.168.2.47 RAW:NibeWP

- logical module<br>
define Nibe NIBE
attr NIBE modbusFile <absolute file path>   &lt;-- optional, default <global-modpath>/export.csv
