Red []

a: context [make op! function [x y][x + y]]
probe 4 a/1 5

; rebol red.r -d -v 1 blockOpTest.red > blockOpOutput.txt