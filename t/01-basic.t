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

#
# Fitted contour
#
is $s.fitted-pitch-contour(0/1), (-12, 0), "Fitted pitch contour begining";
is $s.fitted-pitch-contour(1/2), (-12, 0), "Fitted pitch contour middle";
is $s.fitted-pitch-contour(1/1), (-12, 0), "Fitted pitch contour end";

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

done-testing;
