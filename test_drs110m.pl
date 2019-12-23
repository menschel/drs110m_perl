#!/usr/bin/perl
# 
# This is actually my first attempt with perl. 
# This script borrows parts of https://wiki.volkszaehler.org/hardware/channels/meters/power/eastron_drs155m
# which itself borrows parts of http://www.ip-symcon.de/forum/threads/21407-Stromz%C3%A4hler-mit-RS485/page2
# The general functions have been developed in python3, see https://github.com/menschel/pyehz
# Use and copy as you wish.
# Menschel (C) 2019

use strict;
use warnings;
 
use Device::SerialPort;

#for time conversion
use POSIX::strptime qw( strptime );
use POSIX qw{strftime};
 
my $port = Device::SerialPort->new("/dev/ttyUSB0") || die $!;
$port->baudrate(9600);
$port->databits(7);
$port->parity("even");
$port->stopbits(1);
$port->handshake("none");
$port->write_settings;
 
$port->purge_all();
$port->read_char_time(0);     # don't wait for each character
$port->read_const_time(100); # 100 millisecond per unfulfilled "read" call
 
my $serialID = "001613300153";        # The serial number of the specific device 12-digits long.
# It is possible to find out the device id of a single device on RS-485 9600@7E1 by sending "/?!\r\n"
my $password = "00000000"; # Standard password 0 over 8-digits
 
my $verbose = 2 ;
 
# ========================================
sub sendgetserial {
  my ($cmd) = @_;
  my $count;
  my $saw;
  my $x;
 
  $port->lookclear;
  $port->write( $cmd );
 
  ($count,$saw)=$port->read(84);   # will read 84 chars
  $x=uc(unpack('H*',$saw)); # nach hex wandeln
 
  $cmd =~ s/\n/\\n/mg;
  $cmd =~ s/\r/\\r/mg;
 
  $saw =~ s/\n/\\n/mg;
  $saw =~ s/\r/\\r/mg;
 
  if ( $verbose>10 ) {
    printf "+++ sendserial\n" ;
    print  " CMD: $cmd \n";  # gibt den Befehl in ASCII aus
    print  " COUNT: $count \n";  # gibt die Anzahl der empfangenen Daten aus
    print  " HEX: $x \n";  # gibt die empfangenen Daten in Hex aus
    print  " ASCII: $saw \n";  # gibt die empfangenen Daten aus
    printf "--- sendserial\n" ;
  }
 
  return $saw;
}
# ========================================
sub decodeVAL {
  my ($val) = @_;
 
  if ( $verbose>10 ) {
    printf "+++ decodeVAL\n" ;
    print " val = ( $val ) \n" ;
  }
 
  if($val =~ m/\((\d+)\)/) {
    if ( $verbose>10 ) {
      print " decoded val = $1\n";
      printf " --- decodeVAL\n" ;
    }
    return $1;
  }

  if($val =~ m/\((\S+)\)/) {#string value for temperature
    if ( $verbose>10 ) {
      print " decoded val = $1\n";
      printf " --- decodeVAL\n" ;
    }
    return $1;
  }
 
  print " val = ( $val ) \n" ;
  die "NICHTS gefunden!\n";
  print "NICHTS gefunden!\n";
  return -8888;
}



sub decodeVal1decimal {
  my ($val) = @_;
  return $val/10;
};

sub decodeVal10times {
  my ($val) = @_;
  return $val*10;
};

sub decodeVal1to1 {
  my ($val) = @_;
  return $val;
};

sub decodeValTime {
#"19112703192714" => 2019-11-27 19:27:14 
  my ($str) = @_;
  #print("$str \n");
  my $fmt = "%y%m%d0%w%H%M%S";
  my @time = (POSIX::strptime($str,$fmt))[0..7];
  #print("@time \n");
  return @time;
};

sub decodeValTemp {
  my ($val) = @_;
  my $hex = "";
  foreach (split '',$val){
      $hex .= sprintf("%X", ord($_)-0x30);
    };
  return hex($hex);
};

sub calc_bcc {
  my ($val) = @_;
  my $bcc = 0;
  foreach (split'',substr($val,1)){
    $bcc ^= ord($_);
  }
  return $bcc;
};

sub generate_r1_msg{
  my %args = @_;
  my $reg = $args{reg};
  my $regstr = sprintf("%08d()",$reg);
  my $msg=generate_programming_command_message("command"=>"R","commandtype"=>1,"data"=>$regstr);
  return $msg;
};


sub generate_p1_msg{
  my %args = @_;
  my $passwd = $args{password};
  my $passwdstr = sprintf("(%08d)",$passwd);
  my $msg=generate_programming_command_message("command"=>"P","commandtype"=>1,"data"=>$passwdstr);
  return $msg;
};

sub generate_b0_msg{
  my $msg=generate_programming_command_message("command"=>"B","commandtype"=>0,"data"=>"");
  return $msg;
};

sub generate_programming_command_message{
  my %args = @_;
  my $command = $args{command};
  my $commandtype = $args{commandtype};
  my $data = $args{data};
  my $cmdstr = sprintf("%s%d",$command,$commandtype);
  my $msg=chr(0x01).$cmdstr.chr(0x02).$data.chr(0x03);
  $msg .= chr(calc_bcc($msg));
  return $msg;  
};

sub generate_ack_optionselect_msg{
  my %args = @_;
  my $protocol = $args{protocol};
  my $mode = $args{mode};
  my $msgstr = sprintf("%d:%d",$protocol,$mode);#the ':' is the baudrate identifier
  my $msg=chr(0x06).$msgstr.chr(0x0D).chr(0x0A);#Todo: make the special characters nicely, note there is no bcc for this msg type
  return $msg;
};


sub generate_request_message{
  my %args = @_;
  my $serialnumber = $args{serialnumber};
  my $msg = sprintf("/?%012d!\r\n",$serialnumber);
  return $msg;  
};

# ========================================
 
#main() starts here 

#my $cmd;
my $res;
#my %vals = (); 

$res = sendgetserial(generate_request_message("serialnumber"=>$serialID));
#there is an automatic sleep from the serial timeout
if (!$res){
  #a second wakeup call is not required every time but when the device was asleep.
  $res = sendgetserial(generate_request_message("serialnumber"=>$serialID));
};
 
 
$res = sendgetserial(generate_ack_optionselect_msg("protocol"=>0,"mode"=>1));#note: mode 1 is programming mode, obvious privileges are needed for register access
$res = sendgetserial(generate_p1_msg("password"=>$password));

 
my %drs110m_values = (
                   #'<measurement>'=>[<address>,<scalingfunction>,'<unit>'],
                   'Voltage'       =>[ 0,\&decodeVal1decimal,  'V'],
                   'Current'       =>[ 1,\&decodeVal1decimal,  'A'],
                   'Frequency'     =>[ 2,\&decodeVal1decimal, 'Hz'],
                   'Active Power'  =>[ 3, \&decodeVal10times,  'W'],
                   'Reactive Power'=>[ 4, \&decodeVal10times,'VAr'],
                   'Apparent Power'=>[ 5, \&decodeVal10times, 'VA'],
                   'Active Energy' =>[10,    \&decodeVal1to1, 'Wh'],
                   'Time'          =>[31,    \&decodeValTime,   ''],
                   'Temperature'   =>[32,    \&decodeValTemp, '°C'],
                  );

my $val;
my $valstr;
my $unit;
while ( my ($measurement, $vals) = each(%drs110m_values) ) {
  $res = sendgetserial( generate_r1_msg("reg"=>$drs110m_values{$measurement}[0]) );
  if ($measurement eq 'Time'){
    $val = strftime("%Y-%m-%d %H:%M:%S",&{$drs110m_values{$measurement}[1]}(decodeVAL($res)));
  }
  else{
    $val = &{$drs110m_values{$measurement}[1]}(decodeVAL($res));
  };

  $unit = $drs110m_values{$measurement}[2];
  $valstr = sprintf("%15s : %s %s\n",$measurement,$val,$unit);
  print($valstr); 
};

$res = sendgetserial(generate_b0_msg());


