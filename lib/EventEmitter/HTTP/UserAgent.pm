package EventEmitter::HTTP::UserAgent;

=head1 NAME

EventEmitter::HTTP::UserAgent - HTTP client

=cut

use URI;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use EventEmitter::HTTP::Request;
use EventEmitter::HTTP::Response;

use strict;

my %CONNCACHE;
my $CONNCACHE_TIMEOUT = 300;

sub request
{
	my( $class, $req, $cb ) = @_;

	$req = $req->clone;
	$req = bless $req, 'EventEmitter::HTTP::Request';

	my $uri = $req->uri;

	# add keep-alive etc.

	$req->protocol('HTTP/1.1');
	$req->header(Host => $uri->host);
	$req->header(Transfer_Encoding => 'chunked');

	my $res;

	my $handle;

	my %req_cb = (
		on_drain => sub {
			$req->emit('drain');
		},
		on_read => sub {
			if (defined $res) {
				for ($_[0]->{rbuf}) {
					&{$res->{_parse_body}};
				}
			}
			elsif ($_[0]->{rbuf} =~ /\r\n\r\n/) {
				$res = EventEmitter::HTTP::Response->parse($`);
				$_[0]->{rbuf} = $';

				$res->on('end', sub {
					conn_cache_store($uri->host_port, $handle);
				});

				&$cb($res) if defined $cb;

				for ($_[0]->{rbuf}) {
					&{$res->{_parse_body}};
				}
			}
		},
		on_error => sub {
			$req->emit('error', $!, $_[2]) if $_[1]; # if fatal
		},
		on_eof => sub {
			$handle->destroy;
			$res->emit('end') if defined $res;
		},
	);

	$handle = conn_cache_fetch($uri->host_port);

	if (!defined $handle) {
		tcp_connect $uri->host, $uri->port, sub {
			my ($fh) = @_;

			if (!defined $fh) {
				my $err = $!;
				AnyEvent::postpone { $req->emit('error', "Unable to connect: $err") };
				return;
			}

			$handle = AnyEvent::Handle->new(
				fh => $fh,
				($uri->scheme eq 'https' ? (tls => 'connect') : ()),
				%req_cb,
			);

			$req->connection($handle);
		};
	}
	else {
		$req->$_($req_cb{$_}) for keys %req_cb;
		$req->connection($handle);
	}

	return $req;
}

sub conn_cache_store
{
	my( $host_port, $handle ) = @_;

	push @{$CONNCACHE{$host_port}}, $handle;

	my $destroy = sub {
		@{$CONNCACHE{$host_port}} = grep { $_ != $handle } @{$CONNCACHE{$host_port}};
		$handle->destroy;
		delete $CONNCACHE{$host_port} if !@{$CONNCACHE{$host_port}};
	};

	$handle->on_error($destroy);
	$handle->on_eof($destroy);
	$handle->on_read($destroy);
	$handle->timeout($CONNCACHE_TIMEOUT);
}

sub conn_cache_fetch
{
	my( $host_port ) = @_;

	my $handle = shift @{$CONNCACHE{$host_port}};
	delete $CONNCACHE{$host_port} if !@{$CONNCACHE{$host_port}};

	return $handle;
}

1;

__END__

=head1 SEE ALSO

L<AnyEvent>, L<EventEmitter>

=head1 COPYRIGHT

Copyright (C) 2013 by Tim Brody

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

