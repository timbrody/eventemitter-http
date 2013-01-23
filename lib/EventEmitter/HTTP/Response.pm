package EventEmitter::HTTP::Response;

use base qw( HTTP::Response EventEmitter );

use strict;

sub parse
{
	my( $class, $str ) = @_;

	my $self = $class->SUPER::parse($str);

	my $te = $self->header('Transfer-Encoding') || $self->header('TE') || '';

	if ($te eq 'chunked') {
		$self->{_chunk_length} = undef;
		$self->{_parse_body} = sub { $self->_parse_te_chunked_range };
		$self->on('close', sub {
			if ($self->{_chunk_remains}) {
				$self->request->emit('error', 'Socket closed during chunked response');
			}
		});
	}
	elsif (defined($self->header('Content-Length'))) {
		my $total = 0;
		$self->{_parse_body} = sub {
			$total += length($_);
			$self->emit('data', $_);
			$_ = "";
			if ($total >= $self->header('Content-Length')) {
				$self->emit('end');
			}
		};
		$self->on('close', sub {
			if ($total < $self->header('Content-Length')) {
				$self->request->emit('error', 'Socket closed before entire response received');
			}
		});
	}
	else {
		$self->{_parse_body} = sub {
			$self->emit('data', $_);
			$_ = "";
		};
		# close must always be 'end'
		$self->on('close', sub {
			$self->emit('end');
		});
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
		$self->{_parse_body} = sub { $self->_parse_te_chunked_trailer };
	}
	else {
		$self->{_parse_body} = sub { $self->_parse_te_chunked_chunk };
	}
	&{$self->{_parse_body}};
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
		$self->{_parse_body} = sub { $self->_parse_te_chunked_range };
		&{$self->{_parse_body}};
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

		$self->emit('end');
	}
}

1;
