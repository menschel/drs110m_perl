#!/usr/bin/perl
# 
# This is actually my first attempt with perl. 
# This script borrows parts of https://wiki.volkszaehler.org/hardware/channels/meters/power/eastron_drs155m
# which itself borrows parts of http://www.ip-symcon.de/forum/threads/21407-Stromz%C3%A4hler-mit-RS485/page2
# The general functions have been developed in python3, see https://github.com/menschel/pyehz
# Use and copy as you wish.
# Menschel (C) 2020

package iec1107; # we name our package iec1107 as this is the original protocol name


use strict;
use warnings;
use Carp;

use Device::SerialPort;

#for time conversion
use POSIX::strptime qw( strptime );
use POSIX qw{strftime};
 
#constants
our $SOH = chr(0x01);
our $STX = chr(0x02);
our $ETX = chr(0x03);
our $EOT = chr(0x04);

our $ACK = chr(0x06);
our $NACK = chr(0x15);

our $CRLF = "\r\n";
our $STARTCHARACTER = "/";
our $TRANSMISSIONREQUESTCOMMAND = "?";
our $ENDCHARACTER = "!";

our %drs110m_values = (
                   #'<measurement>'=>[<address>,<scalingfunction>,'<unit>'],
                   'Voltage'       =>[ 0,\&_scale_div_by_10,  'V'],
                   'Current'       =>[ 1,\&_scale_div_by_10,  'A'],
                   'Frequency'     =>[ 2,\&_scale_div_by_10, 'Hz'],
                   'Active Power'  =>[ 3, \&_scale_mul_by_10,  'W'],
                   'Reactive Power'=>[ 4, \&_scale_mul_by_10,'VAr'],
                   'Apparent Power'=>[ 5, \&_scale_mul_by_10, 'VA'],
                   'Active Energy' =>[10,    \&_scale_1_to_1, 'Wh'],
                   'Time'          =>[31,    \&_scale_to_time,   ''],
                   'Temperature'   =>[32,    \&_scale_to_temp, '°C'],
                  );


sub new(\$$$){
  #we expect a HASH consisting of a reference to a valid port, an ID and a password
  # {"port"=>$port, #perl automatically converts this to a reference
  #  "id"=>$id,
  #  "passwd"=>$passwd,
  #}
  my $class = shift;
  my $self = {@_};
  bless($self,$class);
  $self->_init;
  return $self;
};

sub _init {
  my $self = shift;
  #we expect $self->port to be setup correctly so nothing to do here
  $self->{"regs"} = ();
  #for whatever reason _init() does not return anything in the LEARN PERL Examples
  return;
};

sub start_communication {
  my $self = shift;
  unless (ref $self){croak "call with an object, not a class";}
  my $res;
  $res = $self->_xfer(_generate_request_message("serialnumber"=>$self->id));
  #there is an automatic sleep from the serial timeout
  if (!$res){
    #a second wakeup call is not required every time but when the device was asleep.
    $res = $self->_xfer(_generate_request_message("serialnumber"=>$self->id));
  };
  return $self; #utility functions should return self according to LEARN PERL examples
};

sub start_programming_mode {
  my $self = shift;
  unless (ref $self){croak "call with an object, not a class";}
  my $res;
  $res = $self->_xfer(_generate_ack_optionselect_msg("protocol"=>0,"mode"=>1));#note: mode 1 is programming mode, obviously privileges are needed for register access
  $res = $self->_xfer(_generate_p1_msg("password"=>$self->passwd));
  return $self; #utility functions should return self according to LEARN PERL examples  
};


sub update_values {
  my $self = shift;
  unless (ref $self){croak "call with an object, not a class";}
  my $res;
  my $valstr;
  my $unit;
  my ($addr,$val);
  while ( my ($measurement, $vals) = each(%drs110m_values) ) {
    $res = $self->_xfer(_generate_r1_msg("reg"=>$drs110m_values{$measurement}[0]));
    ($addr,$val) = _interpret_r1_msg($res);
    if (defined($addr)){#sanity check
      if ($addr == $drs110m_values{$measurement}[0]){#paranoia check
        $val = &{$drs110m_values{$measurement}[1]}($val);
        $unit = $drs110m_values{$measurement}[2];
        $valstr = sprintf("%s %s",$val,$unit);
        #print($valstr);
        $self->{regs}{$measurement}=$valstr;
      }
      else{
        die("Found $addr but expected $drs110m_values{$measurement}[0]");
      };
    }
    else {
      die("No Response for $measurement");
    };
  }

  return $self;
};

sub log_off() {
  my $self = shift;
  my $res;
  unless (ref $self){croak "call with an object, not a class";}
  $res = $self->_xfer(_generate_b0_msg());
  return $self;
};

sub _xfer {
  my $self = shift;
  my ($cmd) = @_;
  my $count;
  my $res;
  $self->port->lookclear;
  $self->port->write( $cmd );
 
  ($count,$res)=$self->port->read(32);

  return $res;
}


# Object accessor methods
sub port { $_[0]->{port}=$_[1] if defined $_[1]; $_[0]->{port} }
sub id { $_[0]->{id}=$_[1] if defined $_[1]; $_[0]->{id} }
sub passwd { $_[0]->{passwd}=$_[1] if defined $_[1]; $_[0]->{passwd} }
sub regs { $_[0]->{regs}=$_[1] if defined $_[1]; $_[0]->{regs} }




#basic non-object functions

sub _interpret_r1_msg($){
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


sub _scale_div_by_10($){
  my ($val) = @_;
  return $val/10;
};

sub _scale_mul_by_10($){
  my ($val) = @_;
  return $val*10;
};

sub _scale_1_to_1($){
  my ($val) = @_;
  return $val;
};

sub _scale_to_time($){
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

sub _scale_to_temp($){
  my ($val) = @_;
  my $hex = "";
  foreach (split '',$val){
      $hex .= sprintf("%X", ord($_)-0x30);
    };
  return hex($hex);
};

sub _calc_bcc($){
  my ($val) = @_;
  my $bcc = 0;
  foreach (split'',substr($val,1)){
    $bcc ^= ord($_);
  }
  return $bcc;
};

sub _generate_r1_msg(%){
  my %args = @_;
  my $reg = $args{reg};
  my $regstr = sprintf("%08d()",$reg);
  my $msg=_generate_programming_command_message("command"=>"R","commandtype"=>1,"data"=>$regstr);
  return $msg;
};


sub _generate_p1_msg(%){
  my %args = @_;
  my $passwd = $args{password};
  my $passwdstr = sprintf("(%08d)",$passwd);
  my $msg=_generate_programming_command_message("command"=>"P","commandtype"=>1,"data"=>$passwdstr);
  return $msg;
};

sub _generate_b0_msg(){
  my $msg=_generate_programming_command_message("command"=>"B","commandtype"=>0,"data"=>"");
  return $msg;
};

sub _generate_programming_command_message(%){
  my %args = @_;
  my $command = $args{command};
  my $commandtype = $args{commandtype};
  my $data = $args{data};
  my $cmdstr = sprintf("%s%d",$command,$commandtype);
  my $msg=$SOH.$cmdstr.$STX.$data.$ETX;
  $msg .= chr(_calc_bcc($msg));
  return $msg;  
};

sub _generate_ack_optionselect_msg(%){
  my %args = @_;
  my $protocol = $args{protocol};
  my $mode = $args{mode};
  my $msgstr = sprintf("%d:%d",$protocol,$mode);#the ':' is the baudrate identifier
  my $msg=$ACK.$msgstr.$CRLF;
  return $msg;
};


sub _generate_request_message(%){
  my %args = @_;
  my $serialnumber = $args{serialnumber};
  my $snstr = sprintf("%012d",$serialnumber);
  my $msg = $STARTCHARACTER.$TRANSMISSIONREQUESTCOMMAND.$snstr.$ENDCHARACTER.$CRLF;
  return $msg;  
};


1;#for whatever reason
