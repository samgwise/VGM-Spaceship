#! /usr/bin/env perl6
use v6.d;

sub MAIN(Str :$forward) {
    my ($forward-host, $forward-port) = $forward.split(':', :skip-empty);
    $forward-port .= Int;

    my $udp = IO::Socket::Async.udp;
    react whenever IO::Socket::Async.bind-udp('127.0.0.1', 9000).supply(:bin) {
        $udp.write-to($forward-host, $forward-port, $_)
    }
}