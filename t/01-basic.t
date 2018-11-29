use v6.c;
use Test;
use ScaleVec;

use-ok 'VGM::Soundtrack';
use VGM::Soundtrack;

is order-pair(1, 0), (0, 1), "Order pair forces low to high ordering of values in pair";
is order-pair(0, 1), (0, 1), "Order pair preserves conformant ordering";
is order-pair(-10, -5), (-10, -5), "order pair works with degative values";

ok (.defined and $_ ~~ ScaleVec), "Make a new ScaleVec object" given scalevec(1..12);

my VGM::Soundtrack::State $s .= new;

is $s.defined, True, "Instantiated state";

is $s.pitch-contour(0/1), (-12, 0), "pitch contour pair generated for t of 0/1";
is $s.pitch-contour(1/2), (-12, 0), "pitch contour pair generated for t of 1/2";
is $s.pitch-contour(1/1), (-12, 0), "pitch contour pair generated for t of 1/1";

#
# Mapping methods
#
is $s.map-into-pitch(-12, 0), (-12, 0), "Map into pitch structure";

is $s.map-into-rhythmn(0, 1), (0, 1), "Map into rhythmn structure";

is $s.map-onto-pitch(-12, 0), (-12, 0), "Map onto pitch structure";

is $s.map-onto-rhythmn(0, 1), (0, 1), "Map onto rhythmn structure";

is $s.scale-interval($_, 0), -$_, "scalic interval of $_ to 0 is { -$_ }" for -6..6;

#
# Fitted contour
#
is $s.fitted-pitch-contour(0/1, $s.pitch-structure), (-12, 0), "Fitted pitch contour begining";
is $s.fitted-pitch-contour(1/2, $s.pitch-structure), (-12, 0), "Fitted pitch contour middle";
is $s.fitted-pitch-contour(1/1, $s.pitch-structure), (-12, 0), "Fitted pitch contour end";

#
# Interval class
#
for (
    (0, 12, 0),
    (0, 0, 0),
    (-14, 2, 4),
) -> ($a, $b, $ic) {
    is interval-class($a, $b), $ic, "interval class of [$a, $b] is $ic"
}

#
# Common tone relations
#
my $tonic       = scalevec(0, 4, 7, 12);
my $subdominant = scalevec(5, 9, 12, 17);
my $dominant    = scalevec(7, 11, 14, 19);
is common-tone-durations($s, $tonic, [$subdominant, $dominant, $tonic]), (1, 0, 0, 1), "Common tone durations";
is common-tone-durations($s, $tonic, [$subdominant, $tonic, $dominant]), (2, 0, 0, 2), "Common tone durations";
is common-tone-durations($s, $tonic, [$dominant, $subdominant, $tonic]), (0, 0, 1, 0), "Common tone durations";
is common-tone-durations($s, $subdominant, [$dominant, $tonic, $dominant]), (0, 0, 0, 0), "Common tone durations";
is common-tone-durations($s, $tonic, [$tonic]), (1, 1, 1, 1), "Common tone durations";
is common-tone-durations($s, $tonic, [$tonic, $tonic]), (2, 2, 2, 2), "Common tone durations";

#
# Transpotion difference
#
is tonicise-scale-distance($s, $tonic, $subdominant), 0, "Tonic to subdominant is 0";
is tonicise-scale-distance($s, $dominant, $tonic), 0, "Dominant to tonic is 0";
is tonicise-scale-distance($s, $tonic, $dominant), -2, "Tonic to dominant is -2";
is tonicise-scale-distance($s, $subdominant, $tonic), -2, "Subdominant to tonic is 0";
is tonicise-scale-distance($s, $subdominant, $dominant), 3, "Subdominant to dominant is 3";

done-testing;
