Red []

a: context [b: make op! function [x y][x + y]]
probe a/b

; rebol red.r -d -v 1 objOpTest.red > objOpOutput.txt