package EventEmitter::HTTP::Request;

# must call EventEmitter::DESTROY
use base qw( EventEmitter HTTP::Request );

use strict;

my $CRLF = "\015\012";

#sub DESTROY { warn "DESTROY $_[0]\n"; EventEmitter::DESTROY($_[0]) }

sub error
{
	my ($self, $err) = @_;

	$self->emit('error', $err);
	$self->unbind;
}

sub bind
{
	my ($self, $handle) = @_;

	# write the request
	$handle->push_write(sprintf("%s %s %s%s",
			$self->method,
			$self->uri->path_query,
			$self->protocol,
			$CRLF
		));
	$handle->push_write($self->headers->as_string($CRLF));
	$handle->push_write($CRLF);

	$self->{_handle} = $handle;

	$self->emit('connection', $self);

	if ($self->{_complete}) {
		$self->end;
	}
}

sub unbind
{
	my ($self) = @_;

	delete $self->{_handle};
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
		$self->{_complete} = 1;
		return;
	}

	$self->write(""); # write any buffered data
	$self->{_handle}->push_write('0'.$CRLF.$CRLF);

	$self->unbind;
}

1;
