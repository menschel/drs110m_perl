#!/usr/bin/perl
# 
use strict;
use warnings;

sub BEGIN {
push @INC, ".";
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
$port->read_char_time(0);
$port->read_const_time(150);#was 100ms previously, this lead to race conditions
 
my @ids = (1613300152,1613300153); 
# It is possible to find out the device id of a single device on RS-485 9600@7E1 by sending "/?!\r\n"
# It does not work with more than one device on the same bus, it results in garbage!
my $passwd = "00000000"; # Standard password 0 over 8-digits



for my $id (@ids) {
  my $drs110m =   iec1107->new("port"=>$port,"id"=>$id,"passwd"=>$passwd);

  print("Meter: $id\n");
#  $drs110m->start_communication()->start_programming_mode()->update_values();#this function concatenation is neat but absolutely destroying readability
  $drs110m->start_communication();

  $drs110m->start_programming_mode();

  $drs110m->update_values();

  while ( my ($reg, $val) = each(%{$drs110m->regs})){#Note: this type switching in perl is crazy!
    print("$reg : $val\n");
  };

  #print("log off from $serialID\n");
  $drs110m->log_off();
}


