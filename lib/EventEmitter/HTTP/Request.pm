package EventEmitter::HTTP::Request;

use base qw( HTTP::Request EventEmitter );

use strict;

use constant CRLF => "\015\012";

sub bind
{
	my ($self, $handle) = @_;

	# write the request
	$handle->push_write(sprintf("%s %s %s\r\n",
			$self->method,
			$self->uri->path,
			$self->protocol,
		));
	$handle->push_write($self->headers->as_string("\r\n"));
	$handle->push_write("\r\n");

	# start reading the response
	$handle->on_read(sub {
		CONTINUE:
		if ($_[0]->{rbuf} =~ /\r\n\r\n/) {
			my $res = EventEmitter::HTTP::Response->parse($`);
			$_[0]->{rbuf} = $';
			if ($res->code == 100) {
				goto CONTINUE;
			}

			$res->request($self);

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
	$handle->on_error(sub { $self->emit('error', $_[2]) });
	$handle->on_eof(sub { $self->emit('eof') });

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
			CRLF
		));
		$self->{_handle}->push_write(${$self->content_ref});
		$self->{_handle}->push_write(CRLF);
		$self->content("");
	}
}

sub end
{
	my ($self) = @_;

	if (!$self->{_handle})
	{
		$self->on('handle', sub {
			$self->end;
		});
		return;
	}

	$self->write(""); # write any buffered data
	$self->{_handle}->push_write('0'.CRLF.CRLF);
}

1;
