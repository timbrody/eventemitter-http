package EventEmitter::HTTP::UserAgent;

use URI;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use EventEmitter::HTTP::Request;
use EventEmitter::HTTP::Response;

use strict;

sub request
{
	my( $class, $req, $cb ) = @_;

	$req = bless $req, 'EventEmitter::HTTP::Request';

	my $uri = URI->new( $req->uri );

	# add keep-alive etc.

	$req->protocol('HTTP/1.1');
	$req->header(Host => $uri->host);
	$req->header(Transfer_Encoding => 'chunked');

	tcp_connect $uri->host, $uri->port, sub {
		my ($fh) = @_;

		if (!defined $fh) {
			my $err = $!;
			AnyEvent::postpone { $req->emit('error', "Unable to connect: $err") };
			return;
		}

		my $res;

		my $handle;
		$handle = AnyEvent::Handle->new(
			fh => $fh,
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
				$res->emit('end') if defined $res;
			},
		);

		# write the request
		$handle->push_write(sprintf("%s %s %s\r\n",
				$req->method,
				$uri->path,
				$req->protocol,
			));
		$handle->push_write($req->headers->as_string("\r\n"));
		$handle->push_write("\r\n");

		$req->{_connection} = $handle;
		$req->emit('connection', $handle);
	};

	return $req;
}

1;
