# drs110m_perl
A perl module with an object oriented approach for iec1107 (at least I think it is) compliant communication with a DRS110M din rail power meter similar to my [pyehz](https://github.com/menschel/pyehz) project.
This is considered a pre-step for integration in FHEM OBIS Module.
Use and Copy as you wish. Maybe this module will mature enough to be uploaded to CPAN.

# What works and what not
The module iec1107 can be used with a pre-defined serial port, a device serial number and a device password.
The basic functions have been tested. There is work to do with sanity checks and data retrieval.
Currently the module just prints out what it reads from the meter, basically for debug purposes.


# Output example:
```
$ perl test_drs110m.pl 
Meter: 1613300152
  Active Energy : 00000023 Wh
        Current : 0 A
 Reactive Power : 0 VAr
      Frequency : 49.9 Hz
        Voltage : 228.6 V
   Active Power : 0 W
 Apparent Power : 0 VA
           Time : 2020-01-09 14:22:09 
    Temperature : 32 °C
Meter: 1613300153
  Active Energy : 00000034 Wh
        Current : 0 A
 Reactive Power : 0 VAr
      Frequency : 49.9 Hz
        Voltage : 228.8 V
   Active Power : 0 W
 Apparent Power : 0 VA
           Time : 2020-01-09 14:21:37 
    Temperature : 31 °C
```
