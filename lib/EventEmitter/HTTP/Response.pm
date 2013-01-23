package EventEmitter::HTTP::Response;

# must call EventEmitter::DESTROY
use base qw( EventEmitter HTTP::Response );

use strict;

sub close
{
	my ($self) = @_;

	&{$self->{_on_close}}($self);
}

sub read
{
	my ($self) = @_;

	# side-effect the passed buffer
	for($_[1]) {
		&{$self->{_on_read}}($self);
	}
}

sub parse
{
	my( $class, $str ) = @_;

	my $self = $class->SUPER::parse($str);

	my $te = $self->header('Transfer-Encoding') || $self->header('TE') || '';

	if ($te eq 'chunked') {
		$self->{_chunk_length} = undef;
		$self->{_on_read} = \&_parse_te_chunked_range;
		$self->{_on_close} = sub {
			my ($self) = @_;
			if ($self->{_chunk_remains}) {
				$self->request->emit('error', 'Socket closed during chunked response');
			}
		};
	}
	elsif (defined($self->header('Content-Length'))) {
		my $total = 0;
		$self->{_on_read} = sub {
			my ($self) = @_;
			$total += length($_);
			$self->emit('data', $_);
			$_ = "";
			if ($total >= $self->header('Content-Length')) {
				$self->emit('end', $self);
			}
		};
		$self->{_on_close} = sub {
			my ($self) = @_;
			if ($total < $self->header('Content-Length')) {
				$self->request->emit('error', 'Socket closed before entire response received');
			}
		};
	}
	else {
		$self->{_on_read} = sub {
			my ($self) = @_;
			$self->emit('data', $_);
			$_ = "";
		};
		$self->{_on_close} = sub {
			my ($self) = @_;
			$self->emit('end', $self);
		};
	}

	return $self;
}

sub _parse_te_chunked_range
{
	my ($self) = @_;

	return unless s/^([^;\n]+)(;[^\n]+)?\r\n//;
	$self->{_chunk_remains} = hex($1) + 2;

	if ($self->{_chunk_remains} == 2) { # 0 byte payload = end of chunks
		$self->{_chunk_remains} = 0;
		$self->{_on_read} = \&_parse_te_chunked_trailer;
	}
	else {
		$self->{_on_read} = \&_parse_te_chunked_chunk;
	}
	$self->read($_);
}

sub _parse_te_chunked_chunk
{
	my ($self) = @_;

	return if !length $_;

	my $data = substr($_, 0, $self->{_chunk_remains});
	substr($_, 0, $self->{_chunk_remains}) = "";
	$self->{_chunk_remains} -= length $data;

	# strip \r\n
	substr($data,-2) = "" if $self->{_chunk_remains} == 0;
	substr($data,-1) = "" if $self->{_chunk_remains} == 1;

	$self->emit('data', $data) if length $data;

	if ($self->{_chunk_remains} == 0) {
		$self->{_on_read} = \&_parse_te_chunked_range;
		$self->read($_);
	}
}

sub _parse_te_chunked_trailer
{
	my ($self) = @_;

	if (/(^|\r\n)\r\n/) {
		my $res = HTTP::Response->parse($`);
		$_ = $';

		$res->scan(sub {
			$self->header(@_);
		});

		$self->emit('end', $self);
	}
}

1;
