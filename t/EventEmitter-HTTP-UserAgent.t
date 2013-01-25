# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl EventEmitter-HTTP.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 5;
use AnyEvent;
use EventEmitter::HTTP;

#########################

our $REQUEST_C;
our $RESPONSE_C;

sub EventEmitter::HTTP::Request::DESTROY { $REQUEST_C--; EventEmitter::DESTROY($_[0]) }
sub EventEmitter::HTTP::Response::DESTROY { $RESPONSE_C--; EventEmitter::DESTROY($_[0]) }

my $url = 'http://rudar.ruc.dk/bitstream/1800/3027/3/Annika_Agger_-EURS_workshop_C.pdf.txt';
$url = 'http://www.ecs.soton.ac.uk/';
#$url = 'http://cadair.aber.ac.uk/dspace/bitstream/handle/2160/5412/to+grip.pdf;jsessionid=E6EFF4E548FDA3A565A27410737FF5F1?sequence=2';

AnyEvent->condvar; # force load

diag $AnyEvent::MODEL;
diag "Connecting to $url";

{
$REQUEST_C = 2;
$RESPONSE_C = 2;

my $tries = 0;

REDO:

my $condvar = AnyEvent->condvar;

my $req = EventEmitter::HTTP->request(
	HTTP::Request->new( GET => $url ),
	sub {
		my ($res) = @_;

		diag('Got response ' . $res->status_line);
#		diag($res->as_string);

		my $total = 0;
		$res->on('data', sub { $total += length($_[0]) });
		
		$res->on('end', sub { diag "Read $total bytes"; $condvar->send });
	}
);

$req->on('connection', sub { diag 'Connected...' });

$req->on('error', sub { diag "@_"; $condvar->send });

$req->end;

$condvar->recv; # wait

undef $req;

$tries++;
goto REDO if $tries < 2;
}

is($REQUEST_C, 0, "Requests freed");
is($RESPONSE_C, 0, "Responses freed");

{
my $maxlength = 100; # a small number

my $condvar = AnyEvent->condvar;

my $total = 0;
my $ok = 1;

my $req = EventEmitter::HTTP->request(
	HTTP::Request->new( GET => $url ),
	sub {
		my ($res) = @_;

		$res->on('data', sub {
			$total += length($_[0]);
			if ($total > $maxlength) {
				$res->request->abort();
				$condvar->send;
			}
		});
		
		$res->on('end', sub { $ok = 0; $condvar->send });
	}
);

$req->on('error', sub { $ok = 0; $condvar->send });

$req->end;

$condvar->recv; # wait

ok($total >= $maxlength, 'abort() happened after maxlength read');
ok($ok, 'abort() does not trigger end or error');
}

ok(1);

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.
