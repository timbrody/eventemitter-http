package EventEmitter::HTTP::Request;

use base qw( HTTP::Request EventEmitter );

use strict;

sub write
{
	my ($self, $data) = @_;

	$self->add_content($data);

	if ($self->{_connection} && length ${$self->content_ref}) {
		$self->{_connection}->push_write(length(${$self->content_ref})."\r\n");
		$self->{_connection}->push_write(${$self->content_ref});
		$self->{_connection}->push_write("\r\n");
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
	$self->{_connection}->push_write("0\r\n\r\n");
}

1;
