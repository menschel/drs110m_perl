#!/usr/bin/perl
# 
# This is actually my first attempt with perl. 
# This script borrows parts of https://wiki.volkszaehler.org/hardware/channels/meters/power/eastron_drs155m
# which itself borrows parts of http://www.ip-symcon.de/forum/threads/21407-Stromz%C3%A4hler-mit-RS485/page2
# The general functions have been developed in python3, see https://github.com/menschel/pyehz
# Use and copy as you wish.
# Menschel (C) 2020

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


#constants
my $SOH = chr(0x01);
my $STX = chr(0x02);
my $ETX = chr(0x03);
my $EOT = chr(0x04);

my $ACK = chr(0x06);
my $NACK = chr(0x15);

my $CRLF = "\r\n";
my $STARTCHARACTER = "/";
my $TRANSMISSIONREQUESTCOMMAND = "?";
my $ENDCHARACTER = "!";

#function prototypes

#serial transfer function
sub xfer($);

#read 1 message data interpretation
sub interpret_r1_msg($);

#scaling functions
sub scale_div_by_10($);
sub scale_mul_by_10($);
sub scale_1_to_1($);
sub scale_to_time($);
sub scale_to_temp($);

#calculate message checksum
sub calc_bcc($);


#message generation functions
sub generate_r1_msg(%);
sub generate_p1_msg(%);
sub generate_b0_msg();
sub generate_programming_command_message(%);
sub generate_ack_optionselect_msg(%);
sub generate_request_message(%);








#main() starts here 

my %drs110m_values = (
                   #'<measurement>'=>[<address>,<scalingfunction>,'<unit>'],
                   'Voltage'       =>[ 0,\&scale_div_by_10,  'V'],
                   'Current'       =>[ 1,\&scale_div_by_10,  'A'],
                   'Frequency'     =>[ 2,\&scale_div_by_10, 'Hz'],
                   'Active Power'  =>[ 3, \&scale_mul_by_10,  'W'],
                   'Reactive Power'=>[ 4, \&scale_mul_by_10,'VAr'],
                   'Apparent Power'=>[ 5, \&scale_mul_by_10, 'VA'],
                   'Active Energy' =>[10,    \&scale_1_to_1, 'Wh'],
                   'Time'          =>[31,    \&scale_to_time,   ''],
                   'Temperature'   =>[32,    \&scale_to_temp, '°C'],
                  );
#generate messages first and only once for a run
my %msgs = ();
while ( my ($measurement, $vals) = each(%drs110m_values) ) {
  $msgs{$measurement} = generate_r1_msg("reg"=>$drs110m_values{$measurement}[0]);
};



#communication part starts here
my $res;

$res = xfer(generate_request_message("serialnumber"=>$serialID));
#there is an automatic sleep from the serial timeout
if (!$res){
  #a second wakeup call is not required every time but when the device was asleep.
  $res = xfer(generate_request_message("serialnumber"=>$serialID));
};
 
 
$res = xfer(generate_ack_optionselect_msg("protocol"=>0,"mode"=>1));#note: mode 1 is programming mode, obviously privileges are needed for register access
$res = xfer(generate_p1_msg("password"=>$password));

 

my $valstr;
my $unit;
my ($addr,$val);
while ( my ($measurement, $vals) = each(%drs110m_values) ) {
  $res = xfer( $msgs{$measurement} );
  ($addr,$val) = interpret_r1_msg($res);
  if (defined($addr)){#sanity check
    if ($addr == $drs110m_values{$measurement}[0]){#paranoia check
      $val = &{$drs110m_values{$measurement}[1]}($val);
      $unit = $drs110m_values{$measurement}[2];
      $valstr = sprintf("%15s : %s %s\n",$measurement,$val,$unit);
      print($valstr);
    }
    else{
      die("Found $addr but expected $drs110m_values{$measurement}[0]");
    }
  }
  else {
    die("No Response for $measurement");
  }

}

#log off
$res = xfer(generate_b0_msg());



#functions
sub xfer($){
  my ($cmd) = @_;
  my $count;
  my $res;
 
  $port->lookclear;
  $port->write( $cmd );
 
  ($count,$res)=$port->read(32);

  return $res;
}

sub interpret_r1_msg($){
  my ($str) = @_;
  my $val;
  my $addr;
  if($str =~ m/\((\S+)\)/) {
    $val = $1;
    if($str =~ m/(\d+)\(/) {
      $addr = $1;
    };
  };
  return $addr,$val;
};


sub scale_div_by_10($){
  my ($val) = @_;
  return $val/10;
};

sub scale_mul_by_10($){
  my ($val) = @_;
  return $val*10;
};

sub scale_1_to_1($){
  my ($val) = @_;
  return $val;
};

sub scale_to_time($){
#"19112703192714" => 2019-11-27 19:27:14 
  my ($str) = @_;
  #print("$str \n");
  my $fmt = "%y%m%d0%w%H%M%S";
  my @time = (POSIX::strptime($str,$fmt))[0..7];
  if (wantarray){
    return @time;
  }
  else{
    return strftime("%Y-%m-%d %H:%M:%S",@time);
  };
};

sub scale_to_temp($){
  my ($val) = @_;
  my $hex = "";
  foreach (split '',$val){
      $hex .= sprintf("%X", ord($_)-0x30);
    };
  return hex($hex);
};

sub calc_bcc($){
  my ($val) = @_;
  my $bcc = 0;
  foreach (split'',substr($val,1)){
    $bcc ^= ord($_);
  }
  return $bcc;
};

sub generate_r1_msg(%){
  my %args = @_;
  my $reg = $args{reg};
  my $regstr = sprintf("%08d()",$reg);
  my $msg=generate_programming_command_message("command"=>"R","commandtype"=>1,"data"=>$regstr);
  return $msg;
};


sub generate_p1_msg(%){
  my %args = @_;
  my $passwd = $args{password};
  my $passwdstr = sprintf("(%08d)",$passwd);
  my $msg=generate_programming_command_message("command"=>"P","commandtype"=>1,"data"=>$passwdstr);
  return $msg;
};

sub generate_b0_msg(){
  my $msg=generate_programming_command_message("command"=>"B","commandtype"=>0,"data"=>"");
  return $msg;
};

sub generate_programming_command_message(%){
  my %args = @_;
  my $command = $args{command};
  my $commandtype = $args{commandtype};
  my $data = $args{data};
  my $cmdstr = sprintf("%s%d",$command,$commandtype);
  my $msg=$SOH.$cmdstr.$STX.$data.$ETX;
  $msg .= chr(calc_bcc($msg));
  return $msg;  
};

sub generate_ack_optionselect_msg(%){
  my %args = @_;
  my $protocol = $args{protocol};
  my $mode = $args{mode};
  my $msgstr = sprintf("%d:%d",$protocol,$mode);#the ':' is the baudrate identifier
  my $msg=$ACK.$msgstr.$CRLF;#Todo: make the special characters nicely, note there is no bcc for this msg type
  return $msg;
};


sub generate_request_message(%){
  my %args = @_;
  my $serialnumber = $args{serialnumber};
  my $snstr = sprintf("%012d",$serialnumber);
  my $msg = $STARTCHARACTER.$TRANSMISSIONREQUESTCOMMAND.$snstr.$ENDCHARACTER.$CRLF;
  return $msg;  
};



