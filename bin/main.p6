#! /usr/bin/env perl6
use v6.c;

unit sub MAIN(Int :$steps = 32, Str :$scene!);
use ScaleVec;
use Math::Curves;
use Reaper::Control;
use VGM::Scene::Events;
use VGM::Soundtrack;

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
my ScaleVec $tonic          = scalevec 0, 2, 4, 7;
my ScaleVec $submedient     = scalevec 5, 7, 9, 12;
my ScaleVec $subdominant    = scalevec 3, 5, 7, 10;
my ScaleVec $dominant       = scalevec 4, 6, 8, 11;
my ScaleVec $dominant7th    = scalevec 4, 6, 8, 10, 11;

# tempo
my $lento   = scalevec(0, 1.2);
my $vivace  = scalevec(0, 0.45);

# dynamics
my $soft = 40; # piano
my $loud = 105; # forte

my VGM::Soundtrack::OscSender $out .= new;

# Map events
my atomicint $is-playing = 0;
my atomicint $game-state = 0;

my $listener = reaper-listener(:host<127.0.0.1>, :port(9000));
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

# Define state record
my VGM::Soundtrack::State $state .= new(
    :curve-upper(0, 40, 30, -10.5)
    :curve-lower(-12, -12, -7, -15)
    :pitch-structure($chromaitc, $pentatonic, $tonic)
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
for 1..* {

    # update

    # Queue up another phrase length of behaviours
    unless @phrase-queue {
        $step = 0;
        # Were we in cruise or combat when this phrase was queued
        my $combat-running = $state.combat;
        my $cruise-running = $state.cruise;

        @phrase-chords =
            $tonic,
            $tonic,
            $tonic,
            $tonic,
            $submedient,
            $submedient,
            $submedient,
            $submedient,
            $subdominant,
            $subdominant,
            $subdominant,
            $subdominant,
            $dominant,
            $dominant,
            $dominant,
            $dominant,
            $submedient,
            $submedient,
            $submedient,
            $submedient,
            $subdominant,
            $subdominant,
            $subdominant,
            $subdominant,
            $dominant,
            $dominant,
            $dominant,
            $dominant,
            $dominant7th,
            $dominant7th,
            $dominant7th,
            $dominant7th;

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
                    say .contour-history[0], .scale-interval(.contour-history[0].tail, $next-contour.tail), $next-contour given $state;

                    my ($bass, $melody) = $state.contour-history.head;
                    my $next-step-interval = $state.scale-interval($melody, $next-contour.tail);

                    if $state.cruise {
                        $out.send-note('track-6', $bass + 60 , $state.dynamic-live($step) + 10, $block-duration * 990);
                    }

                    my $range = $melody - $bass;
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

                    if $state.combat {
                        # bass
                        my $sub-division = 1;
                        for 0..^$sub-division {
                            $out.send-note( 'track-0', $bass + 60, $state.dynamic-live($step), ($block-duration / $sub-division) * 800, :at( $delta + (($block-duration / $sub-division) * $_) ) );
                        }

                    }

                    if $state.combat or $step % 32 == 0|1|2|3|4|9|10|11|12 {
                        # melody
                        for 0..$next-step-interval -> $passing-note {
                            my $note = .map-onto-scale(.map-into-scale($melody).head + $passing-note).sum given $state;

                            $out.send-note( 'track-3', ($note + 60).Int, (max 60, $state.dynamic-live($step) + 10), (($block-duration / max 1, $next-step-interval) * 990).Int, :at( $delta + (($block-duration / max 1, $next-step-interval) * $passing-note) ) );
                        }
                    }

                    if $combat-running {
                        # synth hold
                        if $step % 4 == 0 {
                            $out.send-note( 'track-1', $state.map-onto-pitch($state.map-into-pitch($melody + 12).head - $_).head + 60, $state.dynamic-live($step), $block-duration * 500 ) for 0..3;
                        }
                        elsif $step % 2 == 0 and $state.cruise {
                            $out.send-note( 'track-1', $state.map-onto-pitch($state.map-into-pitch($melody + 12).head - ($_ * 2)).head + 60, $state.dynamic-live($step), $block-duration * 500 ) for 0..3;
                        }

                        if $step % 3 == 0 and $state.combat {
                            $out.send-note( 'track-1', $state.map-onto-pitch($state.map-into-pitch($melody + 12).head - $_).head + 60, $state.dynamic-live($step), $block-duration * 250, :at($delta + (($block-duration / 4) * 2)) ) for 0..3;
                        }
                    }

                    # queued up while in combat and only during combat
                    if $combat-running and $state.combat {
                        $out.send-note('track-2', $_[0], $_[1] * 1000, $_[2], :at($delta + $_[3])) for drum-pattern($step, $block-duration, $state)
                    }
                }
                #say "Step $_ with state { $state.gist } and curve {  }"
            }
        }
    }

    given ⚛$game-state {
        when 0 {
            $state.rhythmn-structure[0] = $lento;
            $state.pitch-structure[1] = $pentatonic;
            $state.dynamic-target = $soft;
            $state.combat = False;
            $state.cruise = True;
        }
        when 1 {
            $state.rhythmn-structure[0] = $vivace;
            $state.pitch-structure[1] = $nat-minor;
            $state.dynamic-target = $loud;
            $state.combat = True;
            $state.cruise = False;
        }
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
