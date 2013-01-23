package EventEmitter::HTTP::Request;

use base qw( HTTP::Request EventEmitter );

use strict;

my $CRLF = "\015\012";

sub bind
{
	my ($self, $handle) = @_;

	# write the request
	$handle->push_write(sprintf("%s %s %s%s",
			$self->method,
			$self->uri->path,
			$self->protocol,
			$CRLF
		));
	$handle->push_write($self->headers->as_string($CRLF));
	$handle->push_write($CRLF);

	# eof before a response is received is always an error
	$self->{_on_close} = sub {
		$self->emit('error', 'Socket closed before response received');
	};
	$self->on('close', sub { &{$self->{_on_close}} });

	# start reading the response
	$handle->on_read(sub {
		CONTINUE:
		if ($_[0]->{rbuf} =~ /$CRLF$CRLF/) {
			my $res = EventEmitter::HTTP::Response->parse($`);
			$_[0]->{rbuf} = $';
			if ($res->code == 100) {
				goto CONTINUE;
			}

			$res->request($self);

			# eof during a response is up to the response to decide
			$self->{_on_close} = sub {
				$res->emit('close');
			};

			$handle->on_read(sub {
				for($_[0]->{rbuf}) {
					&{$res->{_parse_body}};
				}
			});

			$self->emit('response', $res);

			for($_[0]->{rbuf}) {
				&{$res->{_parse_body}};
			}
		}
	});

	$self->{_handle} = $handle;
	$self->emit('connection', $handle);
}

sub write
{
	my ($self, $data) = @_;

	$self->add_content($data);

	if ($self->{_handle} && length ${$self->content_ref}) {
		$self->{_handle}->push_write(sprintf('%x%s',
			length(${$self->content_ref}),
			$CRLF
		));
		$self->{_handle}->push_write(${$self->content_ref});
		$self->{_handle}->push_write($CRLF);
		$self->content("");
	}
}

sub end
{
	my ($self) = @_;

	if (!$self->{_handle})
	{
		$self->on('connection', sub {
			$self->end;
		});
		return;
	}

	$self->write(""); # write any buffered data
	$self->{_handle}->push_write('0'.$CRLF.$CRLF);
}

1;
