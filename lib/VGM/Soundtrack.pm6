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

our class Instrument {
    has %!held-notes;

    # Add held note to storage
    method hold(Int(Cool) $note, Int $blocks) {
        %!held-notes{$note} = $blocks + (%!held-notes{$note}:exists ?? %!held-notes{$note} !! 0)
    }

    #! Check if note is held
    method is-held(Int(Cool) $note --> Bool) {
        ( %!held-notes{$note}:exists and %!held-notes{$note} > 0) ?? True !! False
    }

    #! Update block counter on held notes
    method update-held(Int $steps = 1) {
        for %!held-notes.kv -> $note, $counter {
            %!held-notes{$note} -= $steps if $counter > 0
        }
    }
}

our class State {
    has Numeric @.curve-upper is rw = 0, 0;
    has Numeric @.curve-lower is rw = -12, -12;

    has ScaleVec @.pitch-structure   = scalevec(0, 1), scalevec(0, 1);
    has ScaleVec @.rhythmn-structure = scalevec(0, 1);

    has Int $.dynamic is rw = 80;
    has Int $.dynamic-target is rw = 80;

    has Bool $.combat is rw = False;
    has Bool $.cruise is rw = True;

    has @.contour-history = (0, 0);

    has Instrument %.instruments;

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

    # Calculate absolute interval in scale terms
    method scale-interval(Numeric $a, Numeric $b --> Numeric) {
        [-] do reduce { $^b.reflexive-step($^a) }, $_, |@!pitch-structure[0..*-2] for $b, $a
    }

    method map-into-scale(+@values) {
        eager reduce { $^b.reflexive-step($^a) }, $_, |@!pitch-structure[0..*-2] for @values
    }

    method map-onto-scale(+@values) {
        eager reduce { $^b.step($^a) }, $_, |@!pitch-structure[0..*-2].reverse for @values
    }

    # Extract a pitch contour, fitted to our pitch structure
    method fitted-pitch-contour($t, @stack) {
        self.pitch-contour($t)
        .map( {
            reduce { $^b.reflexive-step: $^a }, $_, |@stack
        } )
        .map( *.round )
        .map( {
            reduce { $^b.step: $^a }, $_, |@stack.reverse
        } )
        .List
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

    #! update instrument counters
    method instrument-update() {
        for %!instruments.values {
            .update-held
        }
    }
}

our class OscSender {
    use Net::OSC::Message;

    has $.socket  = IO::Socket::Async.udp;
    has @.targets = ('127.0.0.1', '5635'), ;

    has Supplier $.record .= new;

    #! send a note message to targets
    method send-note(Str $name, Int(Cool) $note, Int(Cool) $velocity, Int(Cool) $duration, Instant :$at) {
        $!record.emit: "$name, { $at ?? $at.Rat.nude !! now.Rat.nude }, $note, $velocity, $duration";

        my Net::OSC::Message $msg .= new(
            :path("/play-out/$name/note")
            :args($note, $velocity, $duration)
            :is64bit(False)
        );

        if $at {
            Promise.at($at).then: {
                $!socket.write-to($_[0], $_[1], $msg.package) for @!targets
            }
        }
        else {
            $!socket.write-to($_[0], $_[1], $msg.package) for @!targets
        }
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

#! Determine block durations of each chord tone
our sub common-tone-durations(State $s, ScaleVec $chord, @progression --> List) is export {
    do for $chord.scale-pv.values -> $pitch {
        [+] do gather for @progression -> $future-chord {
            my $common-tone-count = [+] do gather for $future-chord.scale-pv.values -> $chord-tone {
                my $match = ( ($s.map-onto-scale($pitch).head % 12) == ($s.map-onto-scale($chord-tone).head % 12) ) ?? 1 !! 0;
                take $match;
                last if $match == 1;
            }
            take $common-tone-count;
            last if $common-tone-count == 0;
        }
    }
}

#! determine the tonicised transposition of the scale space given two chords
our sub tonicise-scale-distance(State $s, ScaleVec $a, ScaleVec $b --> Numeric) is export {
    given (5 - ([-] $s.map-onto-scale($b.root, $a.root))) % 12 {
        when abs($s.pitch-structure[*-2].root + $_) > abs($s.pitch-structure[*-2].root + ($_ - 12)) {
            $_ - 12
        }
        default { $_ }
    }
}

# Drum sequence
our sub drum-pattern($step, $duration, $state) is export {
    gather given $step % 32 {
        when 30|31 {
            # snare
            take (38, $duration, $state.dynamic-live($step), 0);
            # cymbol open
            take (49, $duration / 4, $state.dynamic-live($step), ($duration / 4) * 2 );
        }
        when 14|15 {
            # snare
            take (38, $duration, $state.dynamic-live($step), 0);
            # kick
            take (36, $duration / 4, $state.dynamic-live($step), ($duration / 4) * 3 )
        }
        when $_ mod 8 == 7 {
            take (40, $duration / 4, $state.dynamic-live($step), 0);
            take (36, $duration / 4, $state.dynamic-live($step), ($duration / 4) * 2 );
        }
        when $_ mod 4 == 1 {
            # snare
            take (38, $duration, $state.dynamic-live($step), 0);
            # # hi-hat open
            # take (46, $duration / 4, $state.dynamic-live($step), ($duration / 4) * 2 );
        }
        when $_ mod 2 == 0 {
            # snare
            take (36, $duration, $state.dynamic-live($step), ($duration / 4) * 3);
            # # hi-hat open
            # take (46, $duration / 4, $state.dynamic-live($step), ($duration / 4) * 2 );
            # kick
            take (36, $duration / 4, $state.dynamic-live($step), 0);
        }
        default {
            take (45, $duration / 4, $state.dynamic-live($step), 0);
            take (45, $duration / 4, $state.dynamic-live($step), ($duration / 3) );
            take (41, $duration / 4, $state.dynamic-live($step), ($duration / 3) * 2 );
            # take (36, $duration / 4, $state.dynamic-live($step), ($duration / 4) * 3 )
        }
    }
}

# Chord defenitions
my ScaleVec $tonic          = scalevec 0, 2, 4, 7;
our sub tonic( --> ScaleVec) is export { $tonic }
my ScaleVec $tonic7th       = scalevec 0, 2, 4, 6, 7;

my ScaleVec $submedient     = scalevec 5, 7, 9, 12;
my ScaleVec $subdominant    = scalevec 3, 5, 7, 10;
my ScaleVec $supertonic     = scalevec 1, 3, 5, 8;
my ScaleVec $medient        = scalevec 2, 4, 6, 9;
my ScaleVec $dominant       = scalevec 4, 6, 8, 11;
my ScaleVec $dominant-sus4  = scalevec 4, 7, 8, 11;
my ScaleVec $dominant-sus2  = scalevec 4, 6, 8, 11, 12;
my ScaleVec $dominant7th    = scalevec 4, 6, 8, 10, 11;
my ScaleVec $subtonic       = scalevec -1, 1, 3, 6;

#! plan a chord progression
our sub chord-planner( --> Positional) is export {
    $tonic,
    $tonic,
    $tonic,
    $tonic,
    |I-_-IV,
    |IV-V,
    $submedient,
    $submedient,
    $submedient,
    $submedient,
    |IV-V,
    $dominant7th,
    $dominant7th,
    $dominant7th,
    $dominant7th,
}

#! IV to five progression with variations
sub IV-V() {
    (
        (
            $subdominant,
            $subdominant,
            $subdominant,
            $subdominant,
            $dominant-sus4,
            $dominant-sus4,
            $dominant,
            $dominant,
        ),
        (
            $subdominant,
            $subdominant,
            $subdominant,
            $subdominant,
            $dominant,
            $dominant,
            $dominant,
            $dominant,
        ),
        (
            $subdominant,
            $subdominant,
            $supertonic,
            $supertonic,
            $dominant-sus2,
            $dominant-sus2,
            $dominant,
            $dominant,
        ),
    ).pick
}

#! Pick a chord between I and IV covering a bar
sub I-_-IV() {
    (
        (
            $submedient,
            $submedient,
            $submedient,
            $submedient,
        ),
        (
            $tonic7th,
            $tonic7th,
            $tonic7th,
            $tonic7th,
        ),
        (
            $subtonic,
            $subtonic,
            $subtonic,
            $subtonic,
        ),
    ).pick
}
