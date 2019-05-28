REBOL [
  Title:   "Red op! in object! test script"
	Author:  "Nathan Douglas"
	File: 	 %obj-op-test.r
	Tabs:	 4
	Rights:  "Copyright (C) 2019 Nathan Douglas. All rights reserved."
	License: "BSD-3 - https://github.com/red/red/blob/origin/BSD-3-License.txt"
]

~~~start-file~~~ "Red op! in object!"

 	--test-- "Red op! in object is compiled and executed!"
 		--compile-and-run-this {
 			Red []

 			a: context [b: make op! function [x y][x + y]]
 			print 4 a/b 5
 		}
 		
 		--assert-printed? "9"
~~~end-file~~~ 
