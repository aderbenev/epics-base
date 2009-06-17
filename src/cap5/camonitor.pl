#!/usr/bin/perl

use strict;

use FindBin qw($Bin);
use lib "$Bin/../../lib/perl";

use Getopt::Std;
use CA;

our ($opt_0, $opt_C, $opt_e, $opt_f, $opt_g, $opt_h, $opt_n, $opt_s);
our $opt_w = 1;
our $opt_m = 'va';

$Getopt::Std::OUTPUT_HELP_VERSION = 1;

HELP_MESSAGE() unless getopts('0:C:e:f:g:hm:nsw:');
HELP_MESSAGE() if $opt_h;

die "No pv name specified. ('camonitor -h' gives help.)\n"
    unless @ARGV;

my %monitors;
my @chans = map { CA->new($_, \&conn_callback); } @ARGV;

CA->pend_event($opt_w);
map {
    printf "%-30s %s\n", $_->name, '*** Not connected (PV not found)'
        unless $monitors{$_};
} @chans;
CA->pend_event(0);


sub conn_callback {
    my ($chan, $up) = @_;
    if ($up && ! $monitors{$chan}) {
        my $type = $chan->field_type;
        $type = 'DBR_STRING'
            if $opt_s && $type =~ m/ DBR_DOUBLE | DBR_FLOAT /x;
        $type = 'DBR_LONG'
            if $opt_n && $type eq 'DBR_ENUM';
        $type =~ s/^DBR_/DBR_TIME_/;
        
        my $count = $chan->element_count;
        $count = +$opt_C if $opt_C && $opt_C <= $count;
        
        $monitors{$chan} =
            $chan->create_subscription($opt_m, \&mon_callback, $type, $count);
    }
}

sub mon_callback {
    my ($chan, $status, $data) = @_;
    if ($status) {
        printf "%-30s %s\n", $chan->name, $status;
    } else {
        display($chan, $data);
    }
}

sub format_number {
    my ($data, $type) = @_;
    if ($type =~ m/_DOUBLE$/) {
        return sprintf "%.${opt_e}e", $data if $opt_e;
        return sprintf "%.${opt_f}f", $data if $opt_f;
        return sprintf "%.${opt_g}g", $data if $opt_g;
    }
    if ($type =~ m/_LONG$/) {
        return sprintf "%lx", $data if $opt_0 eq 'x';
        return sprintf "%lo", $data if $opt_0 eq 'o';
        if ($opt_0 eq 'b') {
            my $bin = unpack "B*", pack "l", $data;
            $bin =~ s/^0*//;
            return $bin;
        }
    }
    return $data;
}

sub display {
    my ($chan, $data) = @_;
    die "Internal error"
        unless ref $data eq 'HASH';
    
    my $type = $data->{TYPE};
    my $value = $data->{value};
    if (ref $value eq 'ARRAY') {
        $value = join(' ', $data->{COUNT},
            map { format_number($_, $type); } @{$value});
    } else {
        $value = format_number($value, $type);
    }
    my $stamp;
    if (exists $data->{stamp}) {
        my @t = localtime $data->{stamp};
        splice @t, 6;
        $t[5] += 1900;
        $t[0] += $data->{stamp_fraction};
        $stamp = sprintf "%4d-%02d-%02d %02d:%02d:%09.6f", reverse @t;
    }
    printf "%-30s %s %s %s %s\n", $chan->name,
        $stamp, $value, $data->{status}, $data->{severity};
}

sub HELP_MESSAGE {
    print STDERR "\nUsage: camonitor [options] <PV name> ...\n",
        "\n",
        "  -h: Help: Print this message\n",
        "Channel Access options:\n",
        "  -w <sec>:  Wait time, specifies longer CA timeout, default is $opt_w second\n",
        "  -m <mask>: Specify CA event mask to use, with <mask> being any combination of\n",
        "             'v' (value), 'a' (alarm), 'l' (log). Default: '$opt_m'\n",
#        "Timestamps:\n",
#        "  Default: Print absolute timestamps (as reported by CA)\n",
#        "  -r: Relative timestamps (time elapsed since start of program)\n",
#        "  -i: Incremental timestamps (time elapsed since last update)\n",
#        "  -I: Incremental timestamps (time elapsed since last update for this channel)\n",
        "Enum format:\n",
        "  -n: Print DBF_ENUM values as number (default are enum string values)\n",
        "Arrays: Value format: print number of values, then list of values\n",
        "  Default:    Print all values\n",
        "  -C <count>: Print first <count> elements of an array\n",
        "Floating point type format:\n",
        "  Default: Use %g format\n",
        "  -e <nr>: Use %e format, with a precision of <nr> digits\n",
        "  -f <nr>: Use %f format, with a precision of <nr> digits\n",
        "  -g <nr>: Use %g format, with a precision of <nr> digits\n",
        "  -s:      Get value as string (may honour server-side precision)\n",
        "Integer number format:\n",
        "  Default: Print as decimal number\n",
        "  -0x: Print as hex number\n",
        "  -0o: Print as octal number\n",
        "  -0b: Print as binary number\n",
        "\n",
        "Example: camonitor -f8 my_channel another_channel\n",
        "  (doubles are printed as %f with 8 decimal digits)\n",
        "\n";
    exit 1;
}

