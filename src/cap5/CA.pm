# Bootstrap wrapper for the Perl 5 Channel Access client module.
# This wrapper also contains the POD documentation for the module.

use strict;
use warnings;

my $version = '0.2';

exists $ENV{EPICS_HOST_ARCH}
    or die "EPICS_HOST_ARCH environment variable not set";


package CA;

our $VERSION = $version;


package Cap5;
# This package is required because the loadable library containing the
# Perl interface code shouldn't be called CA but DynaLoader needs the
# package name to match the library name.  The loadable library actually
# declares the packages for both Cap5 and CA which is why this works,
# although the only symbols in the Cap5 package are associated with the
# requirements of the DynaLoader module.

our $VERSION = $version;
our @ISA = qw(DynaLoader);

require DynaLoader;

# Add our lib/<arch> directory to the shared library search path
push @DynaLoader::dl_library_path, "/usr/epics/base/lib/host";

bootstrap Cap5 $VERSION;


package CA::Subscription;
# A subscription reference is a distinct object type.  This package
# provides a convenience method allowing a subscription to clear itself.

our $VERSION = $version;

sub clear {
    CA->clear_subscription(shift);
}

1;
__END__

=head1 NAME

CA - Perl 5 interface to EPICS Channel Access

=head1 SYNOPSIS

    use lib '/path/to/cap5/lib/perl';
    use CA;

    my $chan = CA->new('pvname');
    CA->pend_io(1);

    my @access = ('no ', '');
    printf "    PV name:       %s\n", $chan->name;
    printf "    Data type:     %s\n", $chan->field_type;
    printf "    Element count: %d\n", $chan->element_count;
    printf "    Host:          %s\n", $chan->host_name;
    printf "    State:         %s\n", $chan->state;
    printf "    Access:        %sread, %swrite\n",
        $access[$chan->read_access], $access[$chan->write_access];

    die "PV not found!" unless chan->is_connected;

    $chan->get;
    CA->pend_io(1);
    printf "    Value:         %s\n", $chan->value;

    $chan->create_subscription('v', \&callback, 'DBR_TIME_DOUBLE');
    CA->pend_event(10);

    sub callback {
        my ($chan, $status, $data) = @_;
        if ($status) {
            printf "%-30s %s\n", $chan->name, $status;
        } else {
            printf "    Value:         %g\n", $data->{value};
            printf "    Severity:      %s\n", $data->{severity};
            printf "    Timestamp:     %d.%09d\n",
                $data->{stamp}, $data->{stamp_fraction};
        }
    }


=head1 DESCRIPTION

C<CA> is an efficient interface to the EPICS Channel Access client library for
use by Perl 5 programs.  It provides most of the functionality of the C library
(omitting Synchronous Groups) but only handles the three standard Perl data
types integer (long), floating point (double) and string. Programmers who
understand the C API will very quickly pick up how to use this library since the
calls and concepts are virtually identical.


=head1 FUNCTIONS


=head2 Constructor

=over 4

=item new( I<NAME> )

=item new( I<NAME>, I<SUB> )

Create a channel for the named PV.  If given, I<SUB> will be called whenever the
connection state of the channel changes.  The arguments passed to I<SUB> are the
channel object and a scalar value that is true if the channel is now up.

The underlying CA channel will be cleaned up properly when the channel object is
garbage-collected by Perl.

=back


=head2 Object Methods

The following methods are provided for channel objects returned by 
C<< CA->new() >>.

=over 4


=item name

The PV name provided when this channel was created.


=item field_type

Returns the native DBF type of the process variable as a string, or the string
C<TYPENOTCONN> if unconnected.


=item element_count

The maximum array element count from the server.  Zero if the channel is not
connected.


=item host_name

A string containing the server's hostname and port number.  If the channel is
disconnected it will report C<< <disconnected> >>.


=item read_access

=item write_access

A true/false value that indicates whether the client has read or write access to
the specified channel.


=item state

A string giving the current connection state of the channel, one of C<never
connected>, C<previously connected>, C<connected> or C<closed>.


=item is_connected

Returns C<true> if the channel is currently connected, else C<false>.  Use this
in preference to the equivalent code S<C<< $chan->state eq 'connected' >>>.


=item get

=item value

The C<get> method makes a C<ca_get()> request for a single element of the Perl
type closest to the channel's native data type (C<DBF_ENUM> fields will be
fetched as strings).  Once the server has returned the value (for which see the
C<pend_io> function below) it can be retrieved using the channel's C<value>
method.  Note that this method deliberately has only very limited capabilities;
the C<get_callback> method must be used for more complex requirements.


=item get_callback( I<SUB> )

=item get_callback( I<SUB>, I<TYPE> )

=item get_callback( I<SUB>, I<COUNT> )

=item get_callback( I<SUB>, I<TYPE>, I<COUNT> )

The C<get_callback> method takes a subroutine reference or name and calls that
routine when the server returns the data requested.  With no other arguments the
request will be for native data type of the channel, and if the channel is an
array it will request all possible array elements.  The subroutine will be
called with three arguments: the channel object, a status value from the server,
and the returned data.  If there was no error the status value will be C<undef>
and the data will be valid; if there was an error the data will be C<undef> and
the status is a printable string giving more information.  The format of the
data is described under L</"Channel Data"> below.

The element count can be overridden by providing an integer argument in the
range 1 .. C<element_count>. The data type can also be given as a string naming
the desired C<DBR_xxx_yyy> type; the actual type used will have the C<yyy> part
widened to one of C<STRING>, C<LONG> or C<DOUBLE>.  The valid type names are
listed in the L<Channel Access Reference Manual|/"SEE ALSO"> under the section
titled Channel Access Data Types; look in the CA Type Code column of the two
tables


=item create_subscription( I<MASK>, I<SUB> )

=item create_subscription( I<MASK>, I<SUB>, I<TYPE> )

=item create_subscription( I<MASK>, I<SUB>, I<COUNT> )

=item create_subscription( I<MASK>, I<SUB>, I<TYPE>, I<COUNT> )

Register a state change subscription and specify a subroutine to be called
whenever the process variable undergoes a significant state change.  I<MASK>
must be a string containing one or more of the letters C<v>, C<l> and C<a> which
indicate that this subscription is for Value, Log or Alarm changes.  The
subroutine I<SUB> is called as described in the C<get_callback> method, and the
same optional I<TYPE> and I<COUNT> arguments may be supplied to modify the data
type and element count requested from the server.

The C<create_subscription> method returns a C<ca::subscription> object which is
required to cancel that particular subscription.  Either call the C<clear>
method on that object directly, or pass it to the C<< CA->clear_subscription >>
class method.


=item put( I<VALUE> )

=item put( I<VALUE>, I<VALUE>, ... )

The C<put> method makes a C<ca_put()> or C<ca_array_put()> call depending on the
number of elements given in its argument list.  For single values the data type
used depends on the actual data item provided by Perl.  For arrays the data type
used will be the native type of the channel widened to one of C<STRING>, C<LONG>
or C<DOUBLE>.


=item put_callback( I<SUB>, I<VALUE> )

=item put_callback( I<SUB>, I<VALUE>, I<VALUE>, ... )

C<put_callback> is similar to the C<put> method with the addition of the
subroutine reference or name I<SUB> which is called when the server reports that
all actions resulting from the put have completed.  For some applications this
callback can be delayed by minutes, hours or possibly even longer.  The data
type is chosen the same way as for C<put>.  The arguments to the subroutine will
be the channel object and the status value from the server which is C<undef> or
a printable string if an error occurred.


=item put_acks( I<SEVR> )

=item put_acks( I<SEVR>, I<SUB> )

Applications that need to ackowledge alarms by doing a C<ca_put()> with type
C<DBR_PUT_ACKS> can do so using the C<put_acks> method.  The severity argument
can be an integer from zero through three or a string containing one of the
corresponding EPICS severity names C<NO_ALARM>, C<MINOR>, C<MAJOR> or
C<INVALID>.  If a subroutine reference is provided it will be called as describe
in C<put_callback> above.


=item put_ackt( I<TRANS> )

=item put_ackt( I<TRANS>, I<SUB> )

This method is for applications that need to enable/disable transient alarms by
doing a C<ca_put()> with type C<DBR_PUT_ACKT>.  The C<TRANS> argument is a
true/false value, and an optional subroutine reference can be provided as
above.


=item change_connection_event( I<SUB> )

This method replaces, adds or cancels the connection handler subroutine for the
channel; see the C<new> constructor for details.  If I<SUB> is C<undef> any
existing handler is removed, otherwise the new subroutine will be used for all
future connection events on this channel.

=back


=head2 Channel Data

The data provided to a callback function registered with either C<get_callback>
or C<create_subscription> can be a scalar value or a reference to an array or a
hash, depending on the data type that was used for the data transfer.  If the
request was for a single item of one of the basic data types, the data argument
will be a perl scalar that holds the value directly.  If the request was for
multiple items of one of the basic types, the data argument will be a reference
to an array holding the data.

If the request was for one of the compound data types, the data argument will be
a reference to a hash with keys as described below.  Keys that are not classed
as metadata are named directly after the fields in the C C<struct dbr_xxx_yyy>,
and are only included when the C structure contains that particular field.


=head3 Metadata

These metadata will always be present in the hash:


=over 4

=item TYPE

The C<DBR_xxx_yyy> name of the data type from the server.


=item COUNT

The number of elements in the data returned by the server.

=back


=head3 Fixed Fields

These fields are always present in the hash:

=over 4


=item value

The actual process variable data.  If I<COUNT> is 1 C<value> will be the data as
a scalar; if the channel returned multiple elements, C<value> will be a
reference to an array of scalars.

If I<TYPE> is C<DBR_GR_ENUM> or C<DBR_CTRL_ENUM>, C<value> can be accessed both
as the integer choice value and (if within range) as the string associated with
that particular choice.


=item status

The alarm status of the PV as a printable string, or C<undef> if not in alarm.


=item severity

The alarm severity of the PV, or C<undef> if not in alarm.  A defined severity
can be used as a human readable string or as a number giving the numeric value
of the alarm severity (1 = MINOR, 2 = MAJOR, 3 = INVALID).

=back


=head3 Ephemeral Fields

These fields are only present for some values of I<TYPE>:

=over 4


=item strs

A reference to an array containing all the possible choice strings for an ENUM.

Present only when I<TYPE> is C<DBR_GR_ENUM> or C<DBR_CTRL_ENUM>.


=item no_str

The number of choices defined for an ENUM.

Present only when I<TYPE> is C<DBR_GR_ENUM> or C<DBR_CTRL_ENUM>.


=item stamp

The process variable timestamp, converted to a local C<time_t>.  This value is
suitable for passing to the perl C<localtime> or C<gmtime> functions.

Present only when I<TYPE> is C<DBR_TIME_yyy>.

=item stamp_fraction

The fractional part of the process variable timestamp as a positive floating
point number less than 1.0.

Present only when I<TYPE> is C<DBR_TIME_yyy>.


=item ackt

The value of the process variable's transient acknowledgment flag, an integer.

Present only when I<TYPE> is C<DBR_STSACK_STRING>.


=item acks

The alarm severity of the highest unacknowledged alarm for this process
variable.  As with the C<severity> value, this scalar is both a string and
numeric severity.

Present only when I<TYPE> is C<DBR_STSACK_STRING>.


=item precision

The process variable's display precision, an integer giving the number of
decimal places to display.

Present only when I<TYPE> is C<DBR_GR_DOUBLE> or C<DBR_CTRL_DOUBLE>.


=item units

The engineering units string for the process variable.

Present only when I<TYPE> is C<DBR_GR_yyy> or C<DBR_CTRL_yyy> where C<yyy> is
not C<STRING>.


=item upper_disp_limit

=item lower_disp_limit

The display range for the process variable; graphical tools often provide a way
to override these limits.

Present only when I<TYPE> is C<DBR_GR_yyy> or C<DBR_CTRL_yyy> where C<yyy> is
not C<STRING>.


=item upper_alarm_limit

=item upper_warning_limit

=item lower_warning_limit

=item lower_alarm_limit

These items give the values at which the process variable should go into an
alarm state, although in practice the alarm severity associated with each level
is not provided.

Present only when I<TYPE> is C<DBR_GR_yyy> or C<DBR_CTRL_yyy> where C<yyy> is
not C<STRING>.


=item upper_ctrl_limit

=item lower_ctrl_limit

The range over which a client can control the value of the process variable.

Present only when I<TYPE> is C<DBR_CTRL_yyy> where C<yyy> is not C<STRING>.

=back


=head2 Class Methods


The following functions are not channel methods, and should be called using the
class method syntax, e.g. C<< CA->pend_io(10) >>.

=over 4

=item flush_io

Flush outstanding IO requests to the server. This routine is useful for users
who need to flush requests prior to performing client side labor in parallel
with labor performed in the server. Outstanding requests are also sent whenever
the buffer which holds them becomes full.


=item test_io

This function tests to see if all C<get> requests are complete and channels
created without a connection callback subroutine are connected.  It will return
a true value if all such operations are complete, otherwise false.


=item pend_io( I<TIMEOUT> )

This function flushes the send buffer and then blocks until all outstanding
C<get> requests complete and all channels created without a connection callback
subroutine have connected for the first time.  Unlike C<pend_event>, this
routine does not process CA's background activities if no IO requests are
pending.

If any I/O or connection operations remain incomplete after I<TIMEOUT> seconds,
the function will die with the error C<ECA_TIMEOUT>; see L</"ERROR HANDLING">
below.  A I<TIMEOUT> interval of zero is taken to mean wait forever if
necessary.  The I<TIMEOUT> value should take into account worst case network
delays such as Ethernet collision exponential back off until retransmission
delays which can be quite long on overloaded networks.


=item pend_event( I<TIMEOUT> )

Flush the send buffer and process CA's background activities for I<TIMEOUT>
seconds.  This function always blocks for the full I<TIMEOUT> period, and if a
value of zero is used it will never return.


=item poll

Flush the send buffer and process any outstanding CA background activity.


=item clear_subscription( I<SUBSCRIPTION> )

Cancel a subscription.  Note that for this to take effect immediately it is
necessary to call C<< CA->flush_io >> or one of the other class methods that
flushes the send buffer.


=item add_exception_event( I<SUB> )

Trap exception events and execute I<SUB> whenever they occur.  The subroutine is
provided with four arguments: The channel object (if applicable), the status
value from the server, a printable context string giving more information about
the error, and a hash reference containing some additional data.  If the
exception is not specific to a particular channel the channel object will be
C<undef>.  The status value is a printable string.  The hash may contain any of
the following members:

=over 8

=item * OP

The operation in progress when the exception occurred.  This scalar when used as
a string is one of C<GET>, C<PUT>, C<CREATE_CHANNEL>, C<ADD_EVENT>,
C<CLEAR_EVENT> or C<OTHER> but can also be accessed as an integer (0-5).

=item * TYPE

The C<DBR_xxx_yyy> name of the data type involved.

=item * COUNT

The number of elements in the request.

=item * FILE

=item * LINE

These refer to the source file and line number inside the CA client library
where the exception was noticed.

=back

=item replace_printf_handler( I<SUB> )

This function provides a method to trap error messages from the CA client
library and redirect them to some other place than the C<STDERR> stream.  The
subroutine provided will be called with a single string argument every time the
client library wishes to output an error or warning message.  Note that a single
message may result in several calls to this subroutine.

To revert back to the original handler, call C<< CA->replace_printf_handler() >>
passing C<undef> as the subroutine reference.

=back


=head1 ERROR HANDLING

Errors in using the library will be indicated by the module throwing an
exception, i.e. calling C<croak()> with an appropriate error message.  These
exceptions can be caught using the standard Parl C<eval {}> statement and
testing the C<$@> variable afterwards; if not caught, they will cause the
running program to C<die> with an appropriate error message pointing to the
program line that called the C<CA> library.

Errors messages reported by the underlying CA client library all start with the
string C<ECA_> and the remainder of the symbol for the associated CA error
number, and are followed after a space-hyphen-space by a human-readable message
describing the error.  Errors that are detected by the perl interface layer do
not follow this pattern, but are still printable strings.


=head1 SEE ALSO

=over

=item [1] R3.14 Channel Access Reference Manual by Jeffrey O. Hill

L<http://www.aps.anl.gov/epics/base/R3-14/9-docs/CAref.html>

=back


=head1 AUTHOR

Andrew Johnson, E<lt>anj@aps.anl.govE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 UChicago Argonne LLC, as Operator of Argonne National
Laboratory.

This software is distributed under the terms of the EPICS Open License.

=cut
