package EventEmitter::HTTP::Request;

use base qw( HTTP::Request EventEmitter );

use strict;

use constant CRLF => "\015\012";

sub write
{
	my ($self, $data) = @_;

	$self->add_content($data);

	if ($self->{_connection} && length ${$self->content_ref}) {
		$self->{_connection}->push_write(sprintf('%x%s',
			length(${$self->content_ref}),
			CRLF
		));
		$self->{_connection}->push_write(${$self->content_ref});
		$self->{_connection}->push_write(CRLF);
		$self->content("");
	}
}

sub end
{
	my ($self) = @_;

	if (!$self->{_connection})
	{
		$self->on('connection', sub {
			$self->end;
		});
		return;
	}

	$self->write(""); # write any buffered data
	$self->{_connection}->push_write('0'.CRLF.CRLF);
}

1;
