# drs110m_perl
A perl module with an object oriented approach for iec1107 (at least I think it is) compliant communication with a DRS110M din rail power meter similar to my [pyehz](https://github.com/menschel/pyehz) project.
This is considered a pre-step for integration in FHEM OBIS Module.
Maybe this module will mature enough to be uploaded to CPAN.

# Usage example:
Define a serial port with setting 9600@7E1.
Define a new iec1107 device with the port reference.
Since there are usually multiple devices on RS-485 a single device can't set up the port.

```
use iec1107;#include the module

my $port = Device::SerialPort->new("/dev/ttyUSB0") || die $!;#define a port with 9600@7E1
$port->baudrate(9600);
$port->databits(7);
$port->parity("even");
$port->stopbits(1);
$port->handshake("none");
$port->write_settings;
$port->purge_all();
$port->read_char_time(0);
$port->read_const_time(150);#was 100ms previously, this lead to race conditions
 
my $id = 1613300152;#or whatever number the meter has
my $passwd = "00000000";

my $drs110m = iec1107->new("port"=>$port,"id"=>$id,"passwd"=>$passwd);
$drs110m->start_communication();
$drs110m->start_programming_mode();
$drs110m->update_values();
$drs110m->log_off();


while ( my ($reg, $val) = each(%{$drs110m->regs})){
  print("$reg : $val\n");
};

```


# Output example:
```
$ perl test_drs110m.pl 
Meter: 1613300152
Voltage : 229.4 V
Active Power : 0 W
Temperature : 23 °C
Reactive Power : 0 VAr
Frequency : 50 Hz
Active Energy : 00000023 Wh
Apparent Power : 0 VA
Time : 2020-01-10 09:26:16 
Current : 0 A
Meter: 1613300153
Voltage : 229.4 V
Active Power : 0 W
Reactive Power : 0 VAr
Temperature : 23 °C
Frequency : 50 Hz
Active Energy : 00000034 Wh
Apparent Power : 0 VA
Time : 2020-01-10 09:25:44 
Current : 0 A
```
