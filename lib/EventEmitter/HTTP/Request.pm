package EventEmitter::HTTP::Request;

=head1 NAME

EventEmitter::HTTP::Request - HTTP request object

=head1 METHODS

=over 4

=cut

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

=item $req->write(BUFFER)

Sends a chunk of the body.

=cut

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

=item $req->end()

Finishes sending the request. If any parts of the body are unsent, it will flush them to the stream. If the request is chunked, this will send the terminating '0\r\n\r\n'.

=cut

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
}

=item $req->abort()

Aborts a request.

=cut

sub abort
{
	my ($self) = @_;

	$self->emit('abort', $self->{_handle}, $self);

	$self->unbind;
}

1;

__END__

=back

=head1 EVENTS

=over 4

=item error $errmsg

If any error is encountered during the request (be that with DNS resolution, TCP level errors, or actual HTTP parse errors) an 'error' event is emitted on the returned request object.

=item response $res

Emitted when a response is received to this request.

=back

=head1 SEE ALSO

Subclasses L<EventEmitter> and L<HTTP::Request>.

