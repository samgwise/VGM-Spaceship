#! /usr/bin/env perl6
use v6.c;

unit sub MAIN(Int $steps = 8);
use ScaleVec;
use Math::Curves;
use Reaper::Control;
use VGM::Soundtrack;

my $perfect     = Set(0, 7, 12);
my $imperfect   = Set(3, 4, 8, 9);
my $dissonant   = Set(1, 2, 5, 6, 10, 11);

my ScaleVec $chromaitc = scalevec(0..12);
my ScaleVec $pentatonic = scalevec(0, 2, 5, 7, 9, 12);
my ScaleVec $octotonic = scalevec(0, 2, 3, 5, 6, 8, 9, 11, 12);
my ScaleVec $whole-tone = scalevec(0, 2, 4, 6, 8, 10, 12);
my ScaleVec $whole-tone-b = scalevec(-1, 1, 3, 5, 7, 9, 11);

my ScaleVec $tonic = scalevec 0, 2, 4, 7;

my VGM::Soundtrack::OscSender $out .= new;

# Map events
my atomicint $is-playing = 0;
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
  when Reaper::Control::Event::PlayTime {
      put "seconds: { .seconds }\nsamples: { .samples }\nbeats: { .beats }"
  }
}

# Define state record
my VGM::Soundtrack::State $state .= new(
    :curve-upper(0, 40, 30, -10.5)
    :curve-lower(-12, -12, -7, -15)
    :pitch-structure($chromaitc, $pentatonic, $tonic)
);

# Define update (play) behaviour
# Update curve of phrase step
# Orchestrate to curve
my @phrase-queue;
my ScaleVec @phrase-chords;

# Run loop
my $epoch = now;
for 1..* {

    # update

    # Queue up another phrase length of behaviours
    unless @phrase-queue {
        $state.pitch-structure[1] = ($octotonic, $pentatonic, $whole-tone, $whole-tone-b).pick;

        @phrase-chords =
            $tonic,
            (scalevec 5, 7, 9, 12),
            (scalevec 3, 5, 7, 10),
            (scalevec 4, 6, 8, 11),
            (scalevec 5, 7, 9, 12),
            (scalevec 3, 5, 7, 10),
            (scalevec 4, 6, 8, 11),
            (scalevec 4, 6, 8, 10, 11);

        for 0..^$steps -> $step {
            # standard step behaviour
            @phrase-queue.push: -> $state, $delta {
                say "creating step $_ for delta $delta";
                $state.pitch-structure.pop;
                $state.pitch-structure.push: @phrase-chords.shift;
                await Promise.at($delta).then: {
                    my $struct = $state.fitted-pitch-contour($step / $steps);
                    say $struct;
                    $out.send-note('track-0', ($_+60).Int, 100, 1000) for $struct.values
                }
                #say "Step $_ with state { $state.gist } and curve {  }"
            }
        }
    }

    # Execute next behaviour
    if ⚛$is-playing == 1 {
        @phrase-queue.shift.($state, $epoch + $_);
    }
    await Promise.at($epoch + $_);

    #last if $_ > 14
}
