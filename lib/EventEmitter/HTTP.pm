package EventEmitter::HTTP;

=head1 NAME

EventEmitter::HTTP - implementation of Node.JS http

=head1 SYNOPSIS

	use AnyEvent;
	use EventEmitter::HTTP;
	
	# use a cvar to keep the AnyEvent loop open
	$cvar = AnyEvent->condvar;
	
	$req = EventEmitter::HTTP->request(
		HTTP::Request->new(GET => 'http://www.google.com/'),
		sub {
			my ($res) = @_;

			print $res->status_line, "\n";
			
			$res->on('data', sub {
				print $_[0];
			});
			
			$res->on('end', sub {
				print "Done\n";
				$cvar->send;
			});
		}
	);
	
	$req->on('error', sub { die $_[0] });
	
	# send/finish the request
	$req->end;
	
	# wait for $res to end()
	$cvar->recv;


=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

use 5.010001;
use strict;
use warnings;

use AnyEvent;
use EventEmitter;
use EventEmitter::HTTP::UserAgent;

our @ISA = qw();

our $VERSION = '0.02';

=item $req = EventEmitter::HTTP->request( $req, CALLBACK )

Make an HTTP request based on $req, a L<HTTP::Request> object. Returns $req blessed into an L<EventEmitter::HTTP::Request> object.

CALLBACK

=over 4

=item $res

A L<EventEmitter::HTTP::Response> object.

=back

Called when the client has received all of the HTTP response headers.

=cut

sub request
{
	&EventEmitter::HTTP::UserAgent::request;
}

# Preloaded methods go here.

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=back

=head1 SEE ALSO

L<AnyEvent>

L<EventEmitter>

http://nodejs.org/api/http.html

=head1 AUTHOR

Tim Brody, E<lt>tdb2@ecs.soton.ac.ukE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by Tim Brody

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
