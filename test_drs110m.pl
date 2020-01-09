#!/usr/bin/perl
# 
use strict;
use warnings;

sub BEGIN {
push @INC, ".";#how long did we take for this absolute simple path include ?!
}


use iec1107;

my $port = Device::SerialPort->new("/dev/ttyUSB0") || die $!;
$port->baudrate(9600);
$port->databits(7);
$port->parity("even");
$port->stopbits(1);
$port->handshake("none");
$port->write_settings;
 
$port->purge_all();
$port->read_char_time(0);     # don't wait for each character
$port->read_const_time(150); # 100 millisecond per unfulfilled "read" call - this was too short and lead into race conditions
 
my @serialIDs = (1613300152,1613300153); 
# It is possible to find out the device id of a single device on RS-485 9600@7E1 by sending "/?!\r\n"
my $password = "00000000"; # Standard password 0 over 8-digits



for my $serialID (@serialIDs) {
  my $drs110m =   iec1107->new("port"=>$port,"serialID"=>$serialID,"passwd"=>$password);

  #print("start communication to $serialID\n");
  print("Meter: $serialID\n");
  $drs110m->start_communication();
  #print("start programming mode\n");
  $drs110m->start_programming_mode();
  #print("update values\n");
  $drs110m->update_values();
  #print("log off from $serialID\n");
  $drs110m->log_off();
}


