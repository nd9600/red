Red []

a: context [b: function [x y][x + y]]
probe a/b 4 5

; rebol red.r -d -v 1 objFuncTest.red > objFuncOutput.txt