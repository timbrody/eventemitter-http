use 5.010001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'EventEmitter::HTTP',
    VERSION_FROM      => 'lib/EventEmitter/HTTP.pm', # finds $VERSION
    PREREQ_PM         => {
			EventEmitter => 0.02,
			AnyEvent => 0.1,
		}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/EventEmitter/HTTP.pm', # retrieve abstract from module
       AUTHOR         => 'Tim Brody <tdb2@localdomain>') : ()),
);
