Red []

a: context [b: make op! function [x y][x + y]]
probe 4 a/b 5

; rebol red.r -d -v 1 objOpTest.red > objOpOutput.txt