# $Id$

# IO::Poll event loop bridge for POE::Kernel.  The theory is that this
# will be faster for large scale applications.  This file is
# contributed by Matt Sergeant (baud).

# Empty package to appease perl.
package POE::Kernel::Poll;

use vars qw($VERSION);
$VERSION = (qw($Revision$ ))[1];

# Everything plugs into POE::Kernel;
package POE::Kernel;

use strict;

# Delcare which event loop bridge is being used, but first ensure that
# no other bridge has been loaded.

BEGIN {
  die "POE can't use IO::Poll and " . &POE_LOOP . "\n"
    if defined &POE_LOOP;
  die "IO::Poll is version $IO::Poll::VERSION (POE needs 0.05 or newer)\n"
    if $IO::Poll::VERSION < 0.05;
};

sub POE_LOOP () { LOOP_POLL }

use IO::Poll qw( POLLRDNORM POLLWRNORM POLLRDBAND
                 POLLIN POLLOUT POLLERR POLLHUP
               );

sub MINIMUM_POLL_TIMEOUT () { 0 }

my %poll_fd_masks;

#------------------------------------------------------------------------------
# Loop construction and destruction.

sub loop_initialize {
  my $kernel = shift;

  %poll_fd_masks = ();
}

sub loop_finalize {
  # does nothing
}

#------------------------------------------------------------------------------
# Signal handlers/callbacks.

sub _loop_signal_handler_generic {
  TRACE_SIGNALS and warn "\%\%\% Enqueuing generic SIG$_[0] event...\n";
  $poe_kernel->_enqueue_event
    ( time(), $poe_kernel, $poe_kernel, EN_SIGNAL, ET_SIGNAL, [ $_[0] ],
      __FILE__, __LINE__
    );
  $SIG{$_[0]} = \&_loop_signal_handler_generic;
}

sub _loop_signal_handler_pipe {
  TRACE_SIGNALS and warn "\%\%\% Enqueuing PIPE-like SIG$_[0] event...\n";
  $poe_kernel->_enqueue_event
    ( time(), $poe_kernel, $poe_kernel, EN_SIGNAL, ET_SIGNAL, [ $_[0] ],
      __FILE__, __LINE__
    );
    $SIG{$_[0]} = \&_loop_signal_handler_pipe;
}

# Special handler.  Stop watching for children; instead, start a loop
# that polls for them.
sub _loop_signal_handler_child {
  TRACE_SIGNALS and warn "\%\%\% Enqueuing CHLD-like SIG$_[0] event...\n";
  $SIG{$_[0]} = 'DEFAULT';
  $poe_kernel->_enqueue_event
    ( time(), $poe_kernel, $poe_kernel, EN_SCPOLL, ET_SCPOLL, [ ],
      __FILE__, __LINE__
    );
}

#------------------------------------------------------------------------------
# Signal handler maintenance functions.

sub loop_watch_signal {
  my $signal = shift;

  # Child process has stopped.
  if ($signal eq 'CHLD' or $signal eq 'CLD') {

    # Begin constant polling loop.  Only start it on CHLD or on CLD if
    # CHLD doesn't exist.
    $SIG{$signal} = 'DEFAULT';
    $poe_kernel->_enqueue_event
      ( time() + 1, $poe_kernel, $poe_kernel, EN_SCPOLL, ET_SCPOLL, [ ],
        __FILE__, __LINE__
      ) if $signal eq 'CHLD' or not exists $SIG{CHLD};

    return;
  }

  # Broken pipe.
  if ($signal eq 'PIPE') {
    $SIG{$signal} = \&_loop_signal_handler_pipe;
    return;
  }

  # Artur Bergman (sky) noticed that xterm resizing can generate a LOT
  # of WINCH signals.  That rapidly crashes perl, which, with the help
  # of most libc's, can't handle signals well at all.  We ignore
  # WINCH, therefore.
  return if $signal eq 'WINCH';

  # Everything else.
  $SIG{$signal} = \&_loop_signal_handler_generic;
}

sub loop_ignore_signal {
  my $signal = shift;
  $SIG{$signal} = "DEFAULT";
}

sub loop_attach_uidestroy {
  # does nothing
}

#------------------------------------------------------------------------------
# Maintain time watchers.

sub loop_resume_time_watcher {
  # does nothing ($_[0] == next time)
}

sub loop_reset_time_watcher {
  # does nothing ($_[0] == next time)
}

sub loop_pause_time_watcher {
  # does nothing ($_[0] == next time)
}

sub vec_to_poll {
  return POLLIN     if $_[0] == VEC_RD;
  return POLLOUT    if $_[0] == VEC_WR;
  return POLLRDBAND if $_[0] == VEC_EX;
  croak "unknown I/O vector $_[0]";
}

#------------------------------------------------------------------------------
# Maintain filehandle watchers.

sub loop_watch_filehandle {
  my ($handle, $vector) = @_;
  my $fileno = fileno($handle);

  my $type = vec_to_poll($vector);
  my $current = $poll_fd_masks{$fileno} || 0;
  my $new = $current | $type;

  TRACE_SELECT and
    warn( sprintf( "Watch $fileno: " .
                   "Current mask: 0x%02X - including 0x%02X = 0x%02X\n",
                   $current, $type, $new
                 )
        );

  $poll_fd_masks{$fileno} = $new;
}

sub loop_ignore_filehandle {
  my ($handle, $vector) = @_;
  my $fileno = fileno($handle);

  my $type = vec_to_poll($vector);
  my $current = $poll_fd_masks{$fileno} || 0;
  my $new = $current & ~$type;

  TRACE_SELECT and
    warn( sprintf( "Ignore $fileno: " .
                   ": Current mask: 0x%02X - removing 0x%02X = 0x%02X\n",
                   $current, $type, $new
                 )
        );

  if ($new) {
    $poll_fd_masks{$fileno} = $new;
  }
  else {
    delete $poll_fd_masks{$fileno};
  }
}

sub loop_pause_filehandle_watcher {
  my ($handle, $vector) = @_;
  my $fileno = fileno($handle);

  my $type = vec_to_poll($vector);
  my $current = $poll_fd_masks{$fileno} || 0;
  my $new = $current & ~$type;

  TRACE_SELECT and
    warn( sprintf( "Pause $fileno: " .
                   ": Current mask: 0x%02X - removing 0x%02X = 0x%02X\n",
                   $current, $type, $new
                 )
        );

  if ($new) {
    $poll_fd_masks{$fileno} = $new;
  }
  else {
    delete $poll_fd_masks{$fileno};
  }
}

sub loop_resume_filehandle_watcher {
  my ($handle, $vector) = @_;
  my $fileno = fileno($handle);

  my $type = vec_to_poll($vector);
  my $current = $poll_fd_masks{$fileno} || 0;
  my $new = $current | $type;

  TRACE_SELECT and
    warn( sprintf( "Resume $fileno: " .
                   "Current mask: 0x%02X - including 0x%02X = 0x%02X\n",
                   $current, $type, $new
                 )
        );

  $poll_fd_masks{$fileno} = $new;
}

#------------------------------------------------------------------------------
# The event loop itself.

sub loop_do_timeslice {
  # Check for a hung kernel.
  _data_test_for_idle_poe_kernel();

  # Set the poll timeout based on current queue conditions.  If there
  # are FIFO events, then the poll timeout is zero and move on.
  # Otherwise set the poll timeout until the next pending event, if
  # there are any.  If nothing is waiting, set the timeout for some
  # constant number of seconds.

  my $now = time();

  my $timeout = $poe_kernel->get_next_event_time();
  if (defined $timeout) {
    $timeout -= $now;
    $timeout = MINIMUM_POLL_TIMEOUT if $timeout < MINIMUM_POLL_TIMEOUT;
  }
  else {
    $timeout = 3600;
  }

  if (TRACE_QUEUE) {
    warn( '*** Kernel::run() iterating.  ' .
          sprintf("now(%.4f) timeout(%.4f) then(%.4f)\n",
                  $now-$^T, $timeout, ($now-$^T)+$timeout
                 )
        );
  }

  my @filenos = %poll_fd_masks;

  if (TRACE_SELECT) {
    foreach (sort { $a<=>$b} keys %poll_fd_masks) {
      my @types;
      push @types, "plain-file"        if -f;
      push @types, "directory"         if -d;
      push @types, "symlink"           if -l;
      push @types, "pipe"              if -p;
      push @types, "socket"            if -S;
      push @types, "block-special"     if -b;
      push @types, "character-special" if -c;
      push @types, "tty"               if -t;
      my @modes;
      my $flags = $poll_fd_masks{$_};
      push @modes, 'r' if $flags & (POLLIN | POLLHUP | POLLERR);
      push @modes, 'w' if $flags & (POLLOUT | POLLHUP | POLLERR);
      push @modes, 'x' if $flags & (POLLRDBAND | POLLHUP | POLLERR);
      warn( "file descriptor $_ = modes(@modes) types(@types)\n" );
    }
  }

  # Avoid looking at filehandles if we don't need to.  -><- The added
  # code to make this sleep is non-optimal.  There is a way to do this
  # in fewer tests.

  if ($timeout or @filenos) {

    # There are filehandles to poll, so do so.

    if (@filenos) {
      # Check filehandles, or wait for a period of time to elapse.
      my $hits = IO::Poll::_poll($timeout * 1000, @filenos);

      if (ASSERT_SELECT) {
        if ($hits < 0) {
          confess "poll returned $hits (error): $!"
            unless ( ($! == EINPROGRESS) or
                     ($! == EWOULDBLOCK) or
                     ($! == EINTR)
                   );
        }
      }

      if (TRACE_SELECT) {
        if ($hits > 0) {
          warn "poll hits = $hits\n";
        }
        elsif ($hits == 0) {
          warn "poll timed out...\n";
        }
      }

      # If poll has seen filehandle activity, then gather up the
      # active filehandles and synchronously dispatch events to the
      # appropriate handlers.

      if ($hits > 0) {

        # This is where they're gathered.

        while (@filenos) {
          my ($fd, $got_mask) = splice(@filenos, 0, 2);
          next unless $got_mask;

          my $watch_mask = $poll_fd_masks{$fd};
          if ( $watch_mask & POLLIN and
               $got_mask & (POLLIN | POLLHUP | POLLERR)
             ) {
            TRACE_SELECT and warn "enqueuing read for fileno $fd\n";
            _data_enqueue_ready_selects(VEC_RD, $fd);
          }

          if ( $watch_mask & POLLOUT and
               $got_mask & (POLLOUT | POLLHUP | POLLERR)
             ) {
            TRACE_SELECT and warn "enqueuing write for fileno $fd\n";
            _data_enqueue_ready_selects(VEC_WR, $fd);
          }

          if ( $watch_mask & POLLRDBAND and
               $got_mask & (POLLRDBAND | POLLHUP | POLLERR)
             ) {
            TRACE_SELECT and warn "enqueuing expedite for fileno $fd\n";
            _data_enqueue_ready_selects(VEC_EX, $fd);
          }
        }
      }
    }

    # No filehandles to poll on.  Try to sleep instead.  Use sleep()
    # itself on MSWin32.  Use a dummy four-argument select() everywhere
    # else.

    else {
      if ($^O eq 'MSWin32') {
        sleep($timeout);
      }
      else {
        select(undef, undef, undef, $timeout);
      }
    }
  }

  # Dispatch whatever events are due.
  _data_dispatch_due_events();
}

sub loop_run {
  # Run for as long as there are sessions to service.
  while ($poe_kernel->get_session_count()) {
    loop_do_timeslice();
  }
}

sub loop_halt {
  # does nothing
}

1;
