#!/usr/bin/perl
# $Id$

use strict;

use lib qw(./lib);
use ExtUtils::MakeMaker;

eval "require ExtUtils::AutoInstall";
if ($@) {
  warn( "\n",
        "==================================================================\n",
        "\n",
        "POE's installer magic requires ExtUtils::AutoInstall.  POE comes\n",
        "with an older version, but it will not be installed.  You should\n",
        "install the most recent ExtUtils::AutoInstall at your convenience.\n",
        "\n",
        "==================================================================\n",
        "\n",
      );
  eval "require './lib/ExtUtils/AutoInstall.pm'";
  die if $@;
}

ExtUtils::AutoInstall->import
  ( -version => '0.32',
    -core => [
        Carp     => '',
        Exporter => '',
        IO       => '',
        POSIX    => '',
        Socket   => '',
        'Filter::Util::Call' => 1.04,
    ],
    "Recommended: Modules POE uses for high-resolution timers." => [
        -default      => 0,
        'Time::HiRes' => '',
    ],
    "Optional: Modules POE uses to control full-screen programs." => [
        -default  => 0,
        'IO::Pty' => '1.02',
        'IPC::Run' => '0.72',
    ],
    "Optional: Modules POE uses to marshal/serialize data." => [
        -default   => 0,
        'Storable' => '',
        'Compress::Zlib' => '',
    ],
    "Optional: Modules used in POE web applications (client & server)." => [
        -default => 0,
        'HTTP::Status'   => '',
        'HTTP::Request'  => '',
        'HTTP::Date'     => '',
        'HTTP::Response' => '',
        'URI'            => '',
    ],
    "Optional: Modules POE uses for Gtk+ graphical interfaces." => [
        -default => 0,
        -tests => [ qw(t/21_gtk.t) ],
        'Gtk'  => '',
    ],
    "Optional: Modules POE uses for Tk graphical interfaces." => [
        -default => 0,
        -tests => [ qw(t/06_tk.t) ],
        'Tk'   => '800.021',
    ],
    "Optional: Modules POE uses to support Event.pm." => [
        -default => 0,
        -tests  => [ qw(t/07_event.t t/12_signals_ev.t) ],
        'Event' => '',
    ],
);

# Touch CHANGES so it exists.
# open(CHANGES, ">>CHANGES") and close CHANGES;

WriteMakefile
  ( NAME           => 'POE',

    ( ($^O eq 'MacOS')
      ? ()
      : ( AUTHOR   => 'Rocco Caputo <rcaputo@cpan.org>',
          ABSTRACT => 'A networking/multitasking framework for Perl.',
        )
    ),

    VERSION_FROM   => 'POE.pm',
    dist           =>
    { COMPRESS => 'gzip -9f',
      SUFFIX   => 'gz',
    # PREOP    => qq(cvs2cl.pl -l "-d'a year ago<'" --utc --file CHANGES),
    },

    PMLIBDIRS      => [ 'POE' ],
  );

1;