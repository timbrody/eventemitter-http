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

my $CRLF = "\015\012";

my %CONN_CACHE;
my %CONN_CACHE_COUNT;
my %CONN_CACHE_FREE;
my %CONN_CACHE_WAITING;

sub describe
{
	my $msg = "Alive: ";
	foreach my $host_port (keys %CONN_CACHE) {
		$msg .= " $host_port [".@{$CONN_CACHE{$host_port}}."]";
	}
	$msg .= ", Waiting: ";
	foreach my $host_port (keys %CONN_CACHE_WAITING) {
		$msg .= " $host_port [".@{$CONN_CACHE_WAITING{$host_port}}."]";
	}
	return $msg;
}

sub empty_cache
{
	%CONN_CACHE = %CONN_CACHE_FREE = %CONN_CACHE_WAITING;
}

sub request
{
	my( $class, $req, $cb ) = @_;

	$req = $req->clone;
	$req = bless $req, 'EventEmitter::HTTP::Request';

	$req->on('response', sub { &$cb($_[0]) }) if defined $cb;

	my $uri = $req->uri;

	# set protocol etc. for HTTP/1.1
	$req->protocol('HTTP/1.1');
	$req->header(Host => $uri->host);
	$req->header(Transfer_Encoding => 'chunked');

	_connect($req);

	return $req;
}

sub _connect
{
	my ($req) = @_;

	my $host_port = $req->uri->host_port;

	my $handle = conn_cache_fetch($host_port);

	if (defined $handle) {
		conn_cache_bind($host_port, $handle, $req);
	}
	elsif ($CONN_CACHE_COUNT{$host_port} && $CONN_CACHE_COUNT{$host_port} >= $EventEmitter::HTTP::MAX_HOST_CONNS) {
		push @{$CONN_CACHE_WAITING{$host_port} ||= []}, $req;
	}
	else {
		__connect($req, sub {
			conn_cache_store($host_port, $_[0]);
			conn_cache_bind($host_port, $_[0], $req);
		});
	}
}

sub __connect
{
	my ($req, $cb) = @_;

	my $uri = $req->uri;
	my $host_port = $uri->host_port;

	$CONN_CACHE_COUNT{$host_port}++;

	tcp_connect $uri->host, $uri->port, sub {
		my ($fh) = @_;

		if (!defined $fh) {
			delete $CONN_CACHE_COUNT{$host_port} if --$CONN_CACHE_COUNT{$host_port} == 0;
			my $err = $!;
			AnyEvent->timer(
				after => 0,
				cb => sub { $req->emit('error', "Unable to connect: $err") },
			);
			return;
		}

		my $handle;
		$handle = AnyEvent::Handle->new(
			fh => $fh,
			($uri->scheme eq 'https' ? (tls => 'connect') : ()),
			rbuf_max => $EventEmitter::HTTP::MAX_HEADER_LENGTH,
			timeout => $EventEmitter::HTTP::CONN_CACHE_TIMEOUT,
		);

		&$cb($handle);
	}, sub {
		my ($fh) = @_;

		return 15; # 15 second timeout
	};
}

sub conn_cache_bind
{
	my ($host_port, $handle, $req) = @_;

	$CONN_CACHE_FREE{$handle} = 0;

	# get ready to read the respones
	$handle->on_read(sub {
		my ($handle) = @_;
		CONTINUE:
		if ($handle->{rbuf} =~ /$CRLF$CRLF/) {
			my $res = EventEmitter::HTTP::Response->parse($`);
			$handle->{rbuf} = $';
			if (!defined $res->code) {
				$req->unbind;
				conn_cache_remove($host_port, $handle);

				$req->emit('error', "Unrecognised HTTP response: $`");
				return;
			}
			if ($res->code == 100) {
				$req->emit('continue', $req);
				goto CONTINUE;
			}

			$res->request($req);

			$req->emit('response', $res);

			my $on_read = sub {
				my ($handle) = @_;
				if (!$res->read($handle->{rbuf})) {
					$req->unbind($handle);

					# On Connection: close (booo), shut down the socket
					if ($res->header('Connection') && $res->header('Connection') eq 'close') {
						conn_cache_remove($host_port, $handle);
					}
					# Yay, unbind and re-use the connection
					else {
						conn_cache_unbind($host_port, $handle);
					}
				}
			};

			$handle->on_read($on_read);
			$handle->on_eof(sub {
				my ($handle) = @_;
				$req->unbind($handle);
				$res->close;
				conn_cache_remove($host_port, $handle);
			});

			# parse the remaining buffer (if any)
			&$on_read($handle);
		}
	});
	$handle->on_error(sub {
		my ($handle, $fatal, $err) = @_;
		$req->error($err);
		conn_cache_remove($host_port, $handle);
	});
	$handle->on_eof(sub {
		my ($handle) = @_;
		$req->error('Socket closed before response received');
		conn_cache_remove($host_port, $handle);
	});

	$req->bind($handle);

	# user aborted the request (i.e. close the socket and stop receiving)
	$req->on('abort', sub {
		my ($handle) = @_;
		conn_cache_remove($host_port, $handle) if defined $handle;
	});
}

sub conn_cache_next
{
	my ($host_port) = @_;

	my $req = shift @{$CONN_CACHE_WAITING{$host_port}};
	delete $CONN_CACHE_WAITING{$host_port} if @{$CONN_CACHE_WAITING{$host_port}} == 0;

	_connect($req) if defined $req;
}

sub conn_cache_unbind
{
	my ($host_port, $handle) = @_;

	$handle->on_read(sub { conn_cache_remove($host_port, $_[0]) });
	$handle->on_error(sub { conn_cache_remove($host_port, $_[0]) });
	$handle->on_eof(sub { conn_cache_remove($host_port, $_[0]) });

	$CONN_CACHE_FREE{$handle} = 1;

	conn_cache_next($host_port);
}

sub conn_cache_remove
{
	my ($host_port, $handle) = @_;

	delete $CONN_CACHE_FREE{$handle};

	@{$CONN_CACHE{$host_port}} = grep { $_ ne $handle } @{$CONN_CACHE{$host_port}};
	delete $CONN_CACHE{$host_port} if @{$CONN_CACHE{$host_port}} == 0;

	$handle->destroy;

	delete $CONN_CACHE_COUNT{$host_port} if --$CONN_CACHE_COUNT{$host_port} == 0;

	conn_cache_next($host_port);
}

sub conn_cache_store
{
	my ($host_port, $handle) = @_;

	push @{$CONN_CACHE{$host_port}||=[]}, $handle;

	$CONN_CACHE_FREE{$handle} = 1;
}

sub conn_cache_fetch
{
	my( $host_port ) = @_;

	return if !defined $CONN_CACHE{$host_port};

	my ($handle) = grep { $CONN_CACHE_FREE{$_} } @{$CONN_CACHE{$host_port}};

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

