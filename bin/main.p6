#! /usr/bin/env perl6
use v6.c;

unit sub MAIN(Int :$steps = 32, Str :$scene!, Str :$record, Str :$midi-sender, Bool :$midi-sender-remote, Str :$reaper-host='127.0.0.1:9000');
use ScaleVec;
use Math::Curves;
use Reaper::Control;
use VGM::Scene::Events;
use VGM::Soundtrack;
use Config::TOML; # Used for interfacing with midi_sender.exe

my $perfect     = Set(0, 7, 12);
my $imperfect   = Set(3, 4, 8, 9);
my $dissonant   = Set(1, 2, 5, 6, 10, 11);

my ScaleVec $chromaitc = scalevec(0..12);
my ScaleVec $pentatonic = scalevec(-3, -1, 2, 4, 6, 9);
my ScaleVec $octotonic = scalevec(0, 2, 3, 5, 6, 8, 9, 11, 12);
my ScaleVec $nat-minor = scalevec(0, 2, 3, 5, 7, 8, 10, 12);
my ScaleVec $whole-tone = scalevec(0, 2, 4, 6, 8, 10, 12);
my ScaleVec $whole-tone-b = scalevec(-1, 1, 3, 5, 7, 9, 11);

# chords
# See Sountrack.pm6

# tempo
my $lento   = scalevec(0, 1.2);
my $vivace  = scalevec(0, 0.45);

# dynamics
my $soft = 40; # piano
my $loud = 105; # forte

# Set up midi out based on arguments and environment
constant midi-sender-config = 'midi_sender.toml';
my VGM::Soundtrack::OscSender $out = do if $midi-sender-remote or $midi-sender.defined and $midi-sender.IO.f {
    my $config = do if midi-sender-config.IO.f {
        midi-sender-config.IO.slurp.&from-toml
    }
    else {
        midi-sender-config.IO.spurt: q:to<TOML>;
        listen_address = "127.0.0.1:10009"
        midi_port = 0
        TOML

        midi-sender-config.IO.slurp.&from-toml
    }

    my $sender-handle;
    $sender-handle = Proc::Async.new($midi-sender) if $midi-sender.defined;
    .start with $sender-handle;

    say "Using osc-interface MidiSender with { $midi-sender.defined ?? $midi-sender !! "remote: $config<listen_address>" }";
    my %channel-map = |(0..15).map( { "track-$_" => $_ + 1 } );
    say "Using channel map: { %channel-map.perl }";

    VGM::Soundtrack::OscSender::MidiSender.new(
        :targets( [$config<listen_address>.split(':', :skip-empty).head(2), ] ),
        |($midi-sender.defined ?? :midi-sender( $sender-handle ) !! ()),
        :%channel-map
    )
}
else {
    say "Using osc-interface PD";
    VGM::Soundtrack::OscSender::PD.new
}

my $recording-fh = .IO.open(:a) with $record;
start react whenever $out.record.Supply {
    # CLOSE { .close with $recording-fh }
    # CATCH { warn $_ }
    .put;
    # $recording-fh.put: $_
}

# Map events
my atomicint $is-playing = 0;
my atomicint $game-state = 0;

my $listener = reaper-listener(:host($_[0]), :port($_[1].Int)) given $reaper-host.split(':', :skip-empty);
start react whenever $listener.reaper-events {
    when Reaper::Control::Event::Play {
      put 'Playing';
      $is-playing ⚛= 1;
    }
    when Reaper::Control::Event::Stop {
      put 'stopped';
      $is-playing ⚛= 0;
    }
}

my $scene-config = load-scene-config($scene);
start react whenever sync-scene-events($listener, $scene-config) {
    given .<path> {
        when '/combat/start' {
            put 'Start combat';
            $game-state ⚛= 1;
        }
        when '/combat/stop' {
            put 'Stop combat';
            $game-state ⚛= 0;
        }
        default { put "Skipped { .perl }" }
    }
}

my @contours =
        ((0, 40, 30, 20), (-12, -5, -12, -5)),
        ((25, 30, 25, 20, 15), (-12, -24, -17)),
        ((10, 15, 30, 45, 30), (-17, -12, -17)),
        ((25, 30, 20, 7, 12), (-24, -17, -29));

# Define state record
my VGM::Soundtrack::State $state .= new(
    :curve-upper(0, 40, 30, -10.5)
    :curve-lower(-12, -12, -7, -15)
    :pitch-structure($chromaitc, $pentatonic, tonic)
);

# prepare instrument state objects
for 0..8 {
    $state.instruments{"track-$_"} .= new
}

# Define update (play) behaviour
# Update curve of phrase step
# Orchestrate to curve
my @phrase-queue;
my ScaleVec @phrase-chords;

# Run loop
my $step-delta = now;
my $step = 0;
# What was the game state of the previous loop iteration
my $previous-game-state = 0;
# How many beats have passed, should I force a change
my $boredom-counter = 0;
my $boredom-threshold = 84;
# How many phrases we have iterated over
my $phrase-counter = 0;
my $phrase-beats-since-change = 0;
for 1..* {

    # update

    # Queue up another phrase length of behaviours
    unless @phrase-queue {
        $phrase-beats-since-change = 0;
        $step = 0;
        # Were we in cruise or combat when this phrase was queued
        my $combat-running = $state.combat;
        my $cruise-running = $state.cruise;

        @phrase-chords = chord-planner;

        $state.curve-upper = @contours[$phrase-counter % @contours.elems].head;
        $state.curve-lower = @contours[$phrase-counter % @contours.elems].tail;

        # manage our phrase iterations
        $phrase-counter++;

        for 0..^$steps -> $step {
            # standard step behaviour
            @phrase-queue.push: -> $state, $delta {
                say "creating step $step for delta $delta, dynamic: { $state.dynamic }";
                # Update current dynamic if needed
                $state.dynamic-update;
                $state.instrument-update;

                # Get chord for this phrase step
                $state.pitch-structure.pop;
                $state.pitch-structure.push: @phrase-chords.shift;

                # Get contour for this phrase and add it to the history
                $state.contour-history.unshift: $state.fitted-pitch-contour($step / $steps, $state.pitch-structure); # assign to 0
                $state.contour-history.pop if $state.contour-history.elems > $steps;

                my $next-contour = $state.fitted-pitch-contour( (min ($step + 1) / $steps, 1/1), [|$state.pitch-structure[0..*-2], @phrase-chords.head // $state.pitch-structure.tail] );

                my $block-duration = $state.rhythmn-structure.head.interval($step, $step + 1);

                await Promise.at($delta).then: {
                    say .contour-history[0], .scale-interval(.contour-history[0].tail, $next-contour.tail), $next-contour, ' ', .curve-upper, '/', .curve-lower given $state;

                    my ($bass, $melody) = $state.contour-history.head;
                    my $next-step-interval = $state.scale-interval($melody, $next-contour.tail);

                    # Rhythm instruments first else other calculations will disrupt timing :(
                    if $state.combat or $combat-running {
                        # bass
                        my $sub-division = ($state.combat and $step % 2 == 1) ?? 2 !! 1;
                        for 0..^$sub-division {
                            $out.send-note( 'track-0', $bass + (12 * $_) + 60, $state.dynamic-live($step), ($block-duration / $sub-division) * 800, :at( $delta + (($block-duration / $sub-division) * $_) ) );
                        }

                        # kick
                        $out.send-note('track-2', 36, $block-duration * 250, $state.dynamic-live($step) + 10) if $state.combat and $step % 2 == 1;
                        $out.send-note( 'track-2', 36, $block-duration * 250, $state.dynamic-live($step)) if $state.combat and $cruise-running and ($step % 2 == 0);
                    }

                    if $state.cruise and $step % 4 == 0 {
                        $out.send-note('track-6', $bass + 60 , $state.dynamic-live($step) + 10, $block-duration * 995 * 4);
                    }

                    # queued up while in combat and only during combat
                    if $combat-running and $state.combat {
                        $out.send-note('track-2', $_[0], $_[1] * 1000, $_[2], :at($delta + $_[3])) for drum-pattern($step, $block-duration, $state)
                    }

                    # Build pad and chior parts
                    my $range = $melody - $bass;
                    start {
                        my $current-chord = $state.pitch-structure.tail;
                        my $common-tone-durations = common-tone-durations($state, $current-chord, @phrase-chords);
                        say "Arrangement space: $range, common tones: $common-tone-durations, current chord { $current-chord.scale-pv }";
                        my $track = $state.combat ?? 'track-5' !! 'track-4';
                        for $common-tone-durations.kv -> $index, $duration {
                            my $instrument = $state.instruments{$track};
                            my $absolute-pitch = $state.map-onto-scale($current-chord.scale-pv[$index]).head;
                            if $duration > 0 and !$instrument.is-held($absolute-pitch) {
                                $instrument.hold($absolute-pitch, $duration);
                                $out.send-note( $track, $absolute-pitch + 60, $state.dynamic-live($step), ($block-duration * (1 + $duration)) * 990);
                            }
                        }
                    }

                    if $state.combat or $step % 32 == 0|1|2|3|4|8|9|10|11|12|13 {
                        # glock melody
                        # during cruise play on the offbeat
                        my $offset = $state.cruise ?? $block-duration / 2 !! 0;
                        for 0..$next-step-interval -> $passing-note {
                            my $note = .map-onto-scale(.map-into-scale($melody).head + $passing-note).sum given $state;
                            # Do not repeat notes during combat
                            next if $state.combat and $note == $state.contour-history[1].tail;

                            $out.send-note( 'track-3', ($note + 60).Int, (max 60, $state.dynamic-live($step) + 10), (($block-duration / max 1, $next-step-interval) * 990).Int, :at( $delta + $offset + (($block-duration / max 1, $next-step-interval) * $passing-note) ) );
                        }
                    }

                    if $combat-running {
                        # Piano chords
                        if $step % 4 == 0 {
                            $out.send-note( 'track-1', $state.map-onto-pitch($state.map-into-pitch($melody).head - ($_ + 1)).head + 60, $state.dynamic-live($step), $block-duration * 500 ) for 0..3;
                        }
                        elsif $step % 2 == 0 and $state.cruise {
                            $out.send-note( 'track-1', $state.map-onto-pitch($state.map-into-pitch($melody + 12).head - (($_ + 1) * 2)).head + 60, $state.dynamic-live($step), $block-duration * 500 ) for 0..3;
                        }

                        if $step % 3 == 0 and $state.combat {
                            $out.send-note( 'track-1', $state.map-onto-pitch($state.map-into-pitch($melody + 12).head - $_).head + 60, $state.dynamic-live($step), $block-duration * 250, :at($delta + (($block-duration / 4) * 2)) ) for 0..3;
                        }
                    }

                    if $step == 6|14|22|24|30 {
                        # Tubular bells
                        $out.send-note: 'track-8', $state.map-onto-pitch($state.map-into-pitch($bass + ($range / 2) + ($step % 3)).head.round).head + 60, $state.dynamic-live($step), $block-duration * 4;
                    }

                }
                #say "Step $_ with state { $state.gist } and curve {  }"
            }
        }
    }

    $phrase-beats-since-change++;
    given ⚛$game-state {
        when $previous-game-state {
            # no change
        }
        when 0 {
            say "Updating structure for cruise";
            $previous-game-state = $_;
            $boredom-counter = 0;
            $boredom-threshold = 84 - $phrase-beats-since-change; # change about half way through repeat 3
            $state.rhythmn-structure[0] = $lento;
            $state.pitch-structure[1] = $pentatonic.transpose($state.pitch-structure.head.root + tonicise-scale-distance($state, $state.pitch-structure.tail, @phrase-chords.head));
            say "Scale transposed by { $state.pitch-structure[1].root } semitones";
            $state.dynamic-target = $soft;
            $state.combat = False;
            $state.cruise = True;
        }
        when 1 {
            say "Updating structure for combat";
            $previous-game-state = $_;
            $boredom-counter = 0;
            $boredom-threshold = 84 - $phrase-beats-since-change;
            $state.rhythmn-structure[0] = $vivace;
            $state.pitch-structure[1] = $nat-minor.transpose($state.pitch-structure.head.root + tonicise-scale-distance($state, $state.pitch-structure.tail, @phrase-chords.head));
            say "Scale transposed by { $state.pitch-structure[1].root } semitones";
            $state.dynamic-target = $loud;
            $state.combat = True;
            $state.cruise = False;
        }
        default {
            warn "Unhandled game state $_";
        }
    }

    if ++$boredom-counter > $boredom-threshold {
        $previous-game-state = -1; # force a change
        $boredom-threshold = 64; # bring next retrigger sooner
        say "Change triggered from bordom counter"
    }

    # Execute next behaviour
    $step-delta = $step-delta + $state.rhythmn-structure.head.interval($step, $step + 1);
    if ⚛$is-playing == 1 {
        @phrase-queue.shift.($state, $step-delta);
    }
    await Promise.at($step-delta);

    $step++;

    #last if $_ > 14
}
