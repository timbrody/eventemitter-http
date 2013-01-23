# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl EventEmitter-HTTP.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 1;
use AnyEvent;
use EventEmitter::HTTP;

#########################

my $url = 'http://rudar.ruc.dk/bitstream/1800/3027/3/Annika_Agger_-EURS_workshop_C.pdf.txt';
$url = 'http://www.ecs.soton.ac.uk/';

AnyEvent->condvar; # force load

diag $AnyEvent::MODEL;
diag "Connecting to $url";

my $tries = 0;

REDO:

my $condvar = AnyEvent->condvar;

my $req = EventEmitter::HTTP->request(
	HTTP::Request->new( GET => $url ),
	sub {
		my ($res) = @_;

		diag('Got response ' . $res->status_line);
#		diag($res->as_string);

		$res->on('data', sub { });
		
		$res->on('end', sub { $condvar->send });
	}
);

$req->on('connection', sub { diag 'Connected...' });

$req->on('error', sub { diag "@_"; $condvar->send });

$req->end;

$condvar->recv; # wait

$tries++;
goto REDO if $tries < 2;

ok(1);

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

