# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl EventEmitter-HTTP.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 1;
use EventEmitter::HTTP;

#########################

my $condvar = AnyEvent->condvar;

my $req = EventEmitter::HTTP->request(
	HTTP::Request->new( GET => 'http://www.ecs.soton.ac.uk/' ),
	sub {
		my ($res) = @_;

		diag('Got response ' . $res->status_line);

		$res->on('data', sub { });
		
		$res->on('end', sub { $condvar->send });
	}
);

$req->end;

$condvar->recv; # wait

ok(1);

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

