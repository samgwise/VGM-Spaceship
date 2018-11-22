use v6.c;
unit module VGM::Soundtrack:ver<0.0.1>;
use ScaleVec;
use Math::Curves;

=begin pod

=head1 NAME

VGM::Soundtrack - blah blah blah

=head1 SYNOPSIS

  use VGM::Soundtrack;

=head1 DESCRIPTION

VGM::Soundtrack is ...

=head1 AUTHOR

= <=>

=head1 COPYRIGHT AND LICENSE

Copyright 2018 =

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

our class State {
    has Numeric @.curve-upper = 0, 0;
    has Numeric @.curve-lower = -12, -12;

    has ScaleVec @.pitch-structure   = scalevec(0, 1);
    has ScaleVec @.rhythmn-structure = scalevec(0, 1);

    has Int $.dynamic is rw = 80;
    has Int $.dynamic-target is rw = 80;

    # select a pair of pitch bounds from a context given a transition
    method pitch-contour($t) {
        order-pair (bézier $t, @!curve-upper), (bézier $t, @!curve-lower)
    }

    # Map values into pitch structure
    method map-into-pitch(+@values) {
        eager reduce { $^b.reflexive-step($^a) }, $_, |@!pitch-structure for @values
    }

    # Map values into rhythmn structure
    method map-into-rhythmn(+@values) {
        eager reduce { $^b.reflexive-step($^a) }, $_, |@!rhythmn-structure for @values
    }

    # Map values onto pitch structure
    method map-onto-pitch(+@values) {
        eager reduce { $^b.step($^a) }, $_, |@!pitch-structure.reverse for @values
    }

    # Map values onto rhythmn structure
    method map-onto-rhythmn(+@values) {
        eager reduce { $^b.step($^a) }, $_, |@!rhythmn-structure.reverse for @values
    }

    # Extract a pitch contour, fitted to our pitch structure
    method fitted-pitch-contour($t) {
        self.map-onto-pitch(
            self.map-into-pitch(
                self.pitch-contour($t)
            ).map( *.round )
        )
    }

    #! Emulate a more lively dynamic behaviour
    method dynamic-live(Int $step, Int $subdivision = 2 --> Int ) {
        return $!dynamic + ($!dynamic / 20).rand.round if $step % $subdivision == 0;
        $!dynamic + ($!dynamic / 20).rand.round;
    }

    #! update our dynamic towards the current target
    method dynamic-update(Int $rate = 4) {
        if $!dynamic-target < $!dynamic {
            $!dynamic -= $rate
        }
        else {
            $!dynamic += $rate
        }
    }
}

our class OscSender {
    use Net::OSC::Message;

    has $.socket  = IO::Socket::Async.udp;
    has @.targets = ('127.0.0.1', '5635'), ;

    #! send a note message to targets
    method send-note(Str $name, Int $note, Int $velocity, Int $duration) {
        my Net::OSC::Message $msg .= new(
            :path("/play-out/$name/note")
            :args($note, $velocity, $duration)
            :is64bit(False)
        );

        $!socket.write-to($_[0], $_[1], $msg.package) for @!targets
    }
}

# Order a pair of values in ascending order
our sub order-pair(Numeric $a, Numeric $b) is export {
    ($a, $b).sort
}

#select a pair of pitch bounds from a context given a transition
our sub pitch-contour($context, $t) is export {
    order-pair $context<upper-voice>.($t), $context<lower-voice>.($t)
}

# Sugar for creating ScaleVec objects
our sub scalevec(+@vector) is export {
    ScaleVec.new( :@vector )
}

# Calculate the interval class of two values
our sub interval-class(Numeric $a, Numeric $b --> Numeric) is export {
    (abs $b - $a) % 12
}
