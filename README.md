Fhem remote (connected to Nibe)
-------------------------------

- physical module:
define NibeWP NIBE_485 /dev/ttyAMA0

- logical module:
define Nibe NIBE
attr Nibe IODev NibeWP   <== will be set by Fhem automatically
attr Nibe ignore 1       <== otherwise messages will be parsed on remote Fhem too (time critical)

Fhem master
-----------

- physical module (dummy for FHEM2FHEM)
define NibeWP NIBE_485 none
attr NibeWP dummy 1

- FHEM2FHEM
define Fhem_on_RPi FHEM2FHEM 192.168.2.47 RAW:NibeWP

- logical module
define Nibe NIBE
