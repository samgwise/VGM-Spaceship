#! /usr/bin/env perl6
use v6.d;
use Math::Curves;

my @contours =
        ((0, 40, 30, 20), (-12, -5, -12, -5)),
        ((25, 30, 25, 20, 15), (-12, -24, -17)),
        ((10, 15, 30, 45, 30), (-17, -12, -17)),
        ((25, 30, 20, 7, 12), (-24, -17, -29));

say "label, { (0..32).map({ "t$_" }).join: ', ' }";
for @contours -> ($upper, $lower) {
    say "Upper, { (0..32).map( { bézier $_ / 32, $upper } ).join: ', ' }";
    say "Lower, { (0..32).map( { bézier $_ / 32, $lower } ).join: ', ' }"
}