Red/System [
	Title:   "PARSE dialect interpreter"
	Author:  "Nenad Rakocevic"
	File: 	 %parse.reds
	Tabs:	 4
	Rights:  "Copyright (C) 2011-2013 Nenad Rakocevic. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/dockimbel/Red/blob/master/BSL-License.txt
	}
]

parser: context [
	verbose: 0
	
	series: as red-block! 0
	rules:  as red-block! 0
	
	#define PARSE_PUSH_POSITIONS [
		p: as positions! ALLOC_TAIL(rules)
		p/header: TYPE_TRIPLE
		p/rule:	  (as-integer cmd - block/rs-head rule) >> 4	;-- save cmd position
		p/input:  input/head									;-- save input position
	]
	
	#define PARSE_SET_INPUT_LENGTH(word) [
		type: TYPE_OF(input)
		word: either any [								;TBD: replace with ANY_STRING?
			type = TYPE_STRING
			type = TYPE_FILE
		][
			string/rs-length? as red-string! input
		][
			block/rs-length? input
		]
	]
	
	#define PARSE_CHECK_INPUT_EMPTY? [
		type: TYPE_OF(input)
		end?: either any [								;TBD: replace with ANY_STRING?
			type = TYPE_STRING
			type = TYPE_FILE
		][
			string/rs-tail? as red-string! input
		][
			block/rs-tail? input
		]
	]
	
	#define PARSE_PICK_INPUT [
		type: TYPE_OF(input)
		either any [		;TBD: replace with ANY_STRING
			type = TYPE_STRING
			type = TYPE_FILE
		][
			char: as red-char! value
			char/header: TYPE_CHAR
			char/value: string/rs-abs-at as red-string! input p/input
		][
			value: block/rs-abs-at input p/input
		]
	]

	#enum states! [
		ST_PUSH_BLOCK
		ST_POP_BLOCK
		ST_PUSH_RULE
		ST_POP_RULE
		ST_CHECK_PENDING
		ST_DO_ACTION
		ST_NEXT_INPUT
		ST_NEXT_ACTION
		ST_MATCH
		ST_MATCH_RULE
		ST_FIND_ALTERN
		ST_WORD
		ST_END
		ST_EXIT
	]
	
	#enum rule-flags! [									;-- negative values to not collide with t/state counter
		R_NONE:		  -1
		R_TO:		  -2
		R_THRU:		  -3
		R_COPY:		  -4
		R_SET:		  -5
		R_NOT:		  -6
		R_INTO:		  -7
		R_THEN:		  -8
		R_REMOVE:	  -9
		R_INSERT:	  -10
		R_WHILE:	  -11
		R_COLLECT:	  -12
		R_KEEP:		  -13
		R_KEEP_PAREN: -14
		R_AHEAD:	  -15
	]
	
	triple!: alias struct! [
		header [integer!]
		min	   [integer!]
		max	   [integer!]
		state  [integer!]
	]
	
	positions!: alias struct! [
		header [integer!]
		rule   [integer!]
		input  [integer!]
		pad    [integer!]
	]
	
	#if debug? = yes [
		print-state: func [s [integer!]][
			print "state: "
			print-line switch s [
				ST_PUSH_BLOCK	 ["ST_PUSH_BLOCK"]
				ST_POP_BLOCK	 ["ST_POP_BLOCK"]
				ST_PUSH_RULE	 ["ST_PUSH_RULE"]
				ST_POP_RULE	 	 ["ST_POP_RULE"]
				ST_CHECK_PENDING ["ST_CHECK_PENDING"]
				ST_DO_ACTION	 ["ST_DO_ACTION"]
				ST_NEXT_INPUT	 ["ST_NEXT_INPUT"]
				ST_NEXT_ACTION	 ["ST_NEXT_ACTION"]
				ST_MATCH		 ["ST_MATCH"]
				ST_MATCH_RULE	 ["ST_MATCH_RULE"]
				ST_FIND_ALTERN	 ["ST_FIND_ALTERN"]
				ST_WORD			 ["ST_WORD"]
				ST_END			 ["ST_END"]
				ST_EXIT			 ["ST_EXIT"]
			]
		]
	]
	
	advance: func [
		str		[red-string!]
		value	[red-value!]							;-- char! or string! value
		return:	[logic!]
		/local
			end? [logic!]
			type [integer!]
	][
		type: TYPE_OF(value)
		end?: either any [type = TYPE_CHAR type = TYPE_BITSET][
			string/rs-next str
		][
			assert TYPE_OF(value) = TYPE_STRING
			string/rs-skip str string/rs-length? as red-string! value
		]
		end?
	]
	
	find-altern: func [									;-- search for next '| symbol
		rule	[red-block!]
		pos		[red-value!]
		return: [integer!]								;-- >= 0 found, -1 not found 
		/local
			head  [red-value!]
			tail  [red-value!]
			value [red-value!]
			w	  [red-word!]
	][
		s: GET_BUFFER(rule)
		head:  s/offset + ((as-integer pos - s/offset) >> 4)
		tail:  s/tail
		value: head
		
		while [value < tail][
			if TYPE_OF(value) = TYPE_WORD [
				w: as red-word! value
				if w/symbol = words/pipe [
					return ((as-integer value - head) >> 4)
				]
			]
			value: value + 1
		]
		-1
	]
	
	adjust-input-index: func [
		input	[red-series!]
		pos		[positions!]
		base    [integer!]
		offset  [integer!]
		return: [logic!]
	][
		input/head: input/head + base + offset
		pos/input: either zero? input/head [0][input/head - base]
		yes
	]
	
	find-token?: func [									;-- optimized fast token lookup
		rules	[red-block!]							;-- (could be optimized even further)
		input	[red-series!]
		token	[red-value!]
		case?	[logic!]
		return: [logic!]
		/local
			pos*   [positions!]
			head   [red-value!]
			tail   [red-value!]
			value  [red-value!]
			char   [red-char!]
			bits   [red-bitset!]
			s	   [series!]
			p	   [byte-ptr!]
			phead  [byte-ptr!]
			ptail  [byte-ptr!]
			pbits  [byte-ptr!]
			pos    [byte-ptr!]
			p4	   [int-ptr!]
			cp	   [integer!]
			size   [integer!]
			unit   [integer!]
			type   [integer!]
			not?   [logic!]
			match? [logic!]
	][
		s: GET_BUFFER(rules)
		pos*: as positions! s/tail - 2
		
		type: TYPE_OF(input)
		either any [									;TBD: replace with ANY_STRING + TYPE_BINARY
			type = TYPE_STRING
			type = TYPE_FILE
			type = TYPE_BINARY
		][
			switch TYPE_OF(token) [
				TYPE_BITSET [
					s: 	   GET_BUFFER(input)
					unit:  GET_UNIT(s)
					phead: (as byte-ptr! s/offset) + (input/head << (unit >> 1))
					ptail: as byte-ptr! s/tail
					p: 	   phead
					
					bits:  as red-bitset! token
					s:	   GET_BUFFER(bits)
					pbits: as byte-ptr! s/offset
					not?:  FLAG_NOT?(s)
					size:  s/size << 3

					until [
						cp: switch unit [
							Latin1 [as-integer p/value]
							UCS-2  [(as-integer p/2) << 8 + p/1]
							UCS-4  [p4: as int-ptr! p p4/value]
						]
						either size < cp [
							match?: not?				;-- virtual bit
						][
							BS_TEST_BIT(pbits cp match?)
						]
						if match? [
							return adjust-input-index input pos* 1 ((as-integer p - phead) >> (unit >> 1))
						]
						p: p + unit
						p = ptail
					]
				]
				TYPE_STRING
				TYPE_FILE
				TYPE_BINARY [
					size: string/rs-length? as red-string! token
					if (string/rs-length? as red-string! input) < size [return no]
					
					s: GET_BUFFER(input)
					unit:  (GET_UNIT(s) >> 1)
					phead: as byte-ptr! s/offset
					ptail: as byte-ptr! s/tail
					
					until [
						if string/equal? as red-string! input as red-string! token COMP_EQUAL yes [
							return adjust-input-index input pos* size 0
						]
						input/head: input/head + 1
						phead + (input/head + size << unit) > ptail
					]
				]
				TYPE_CHAR [
					char: as red-char! token
					cp: char/value

					s: GET_BUFFER(input)
					unit: GET_UNIT(s)
					phead: (as byte-ptr! s/offset) + (input/head << (unit >> 1))
					ptail: as byte-ptr! s/tail
					p: phead

					switch unit [
						Latin1 [
							while [p < ptail][
								if p/value = as-byte cp [
									return adjust-input-index input pos* 1 (as-integer p - phead)
								]
								p: p + 1
							]
						]
						UCS-2 [
							while [p < ptail][
								if (as-integer p/2) << 8 + p/1 = cp [
									return adjust-input-index input pos* 1 ((as-integer p - phead) >> 1)
								]
								p: p + 2
							]
						]
						UCS-4 [
							p4: as int-ptr! p
							while [p4 < as int-ptr! ptail][
								if p4/value = cp [
									return adjust-input-index input pos* 1 ((as-integer p4 - phead) >> 2)
								]
								p4: p4 + 1
							]
						]
					]
				]
				default [
					print-line "*** Parse Error: invalid literal value to match on string"
				]
			]
		][
			head:  block/rs-head input
			tail:  block/rs-tail input
			value: head
			
			while [value < tail][
				if actions/compare value token COMP_EQUAL [
					return adjust-input-index input pos* 1 ((as-integer value - head) >> 4)
				]
				value: value + 1
			]
		]
		no
	]
	
	loop-bitset: func [									;-- optimized bitset matching loop
		input	[red-series!]
		bits	[red-bitset!]
		min		[integer!]
		max		[integer!]
		counter [int-ptr!]
		return: [logic!]
		/local
			s	   [series!]
			unit   [integer!]
			p	   [byte-ptr!]
			phead  [byte-ptr!]
			ptail  [byte-ptr!]
			pbits  [byte-ptr!]
			pos    [byte-ptr!]
			p4	   [int-ptr!]
			cp	   [integer!]
			cnt	   [integer!]
			size   [integer!]
			not?   [logic!]
			max?   [logic!]
			match? [logic!]
	][
		s:	   GET_BUFFER(input)
		unit:  GET_UNIT(s)
		phead: (as byte-ptr! s/offset) + (input/head << (unit >> 1))
		ptail: as byte-ptr! s/tail
		p:	   phead

		s:	   GET_BUFFER(bits)
		pbits: as byte-ptr! s/offset
		not?:  FLAG_NOT?(s)
		size:  s/size << 3
		
		cnt: 	0
		match?: yes
		max?:	max <> R_NONE
		
		until [
			cp: switch unit [
				Latin1 [as-integer p/value]
				UCS-2  [(as-integer p/2) << 8 + p/1]
				UCS-4  [p4: as int-ptr! p p4/value]
			]
			either size < cp [							;-- virtual bit
				match?: not?
			][
				BS_TEST_BIT(pbits cp match?)
			]
			if match? [
				p: p + unit
				cnt: cnt + 1
			]
			any [
				not match?
				p = ptail
				all [max? cnt >= max]
			]
		]
		input/head: input/head + ((as-integer p - phead) >> (unit >> 1))
		counter/value: cnt
		
		either not max? [min <= cnt][all [min <= cnt cnt <= max]]
	]
	
	loop-token: func [									;-- fast literal matching loop
		input	[red-series!]
		token	[red-value!]
		min		[integer!]
		max		[integer!]
		counter [int-ptr!]
		case?	[logic!]
		return: [logic!]
		/local
			len	   [integer!]
			cnt	   [integer!]
			type   [integer!]
			match? [logic!]
			end?   [logic!]
			s	   [series!]
	][
		PARSE_SET_INPUT_LENGTH(len)
		if any [zero? len len < min][return no]			;-- input too short
		
		cnt: 0
		match?: yes

		either any [									;TBD: replace with ANY_STRING
			type = TYPE_STRING
			type = TYPE_FILE
		][
			either TYPE_OF(token)= TYPE_BITSET [
				match?: loop-bitset input as red-bitset! token min max counter
			][
				until [										;-- ANY-STRING input matching
					match?: string/match? as red-string! input token COMP_EQUAL
					end?: all [match? advance as red-string! input token]	;-- consume matched input
					cnt: cnt + 1
					any [
						not match?
						end?
						all [max <> R_NONE cnt >= max]
					]
				]
			]
		][
			until [										;-- ANY-BLOCK input matching
				match?:	actions/compare block/rs-head input token COMP_EQUAL	;@@ sub-optimal!!
				end?: all [match? block/rs-next input]	;-- consume matched input
				cnt: cnt + 1
				any [
					not match?
					end?
					all [max <> R_NONE cnt >= max]
				]
			]
		]
		
		unless match? [
			cnt: cnt - 1
			match?: either max = R_NONE [min <= cnt][all [min <= cnt cnt <= max]]
		]
		counter/value: cnt
		match?
	]
	
	save-stack: func [
		/local
			cnt [integer!]
			p	[positions!]
	][
		cnt: block/rs-length? rules
		unless zero? cnt [
			p: as positions! ALLOC_TAIL(rules)
			p/header: TYPE_TRIPLE
			p/input:  series/head
			p/rule:   rules/head
			
			series/head: series/head + 1
			rules/head:  rules/head + cnt + 1			;-- account for the new position! slot
		]
	]
	
	restore-stack: func [
		/local
			s [series!]
			p [positions!]
	][
		if rules/head > 0 [
			s: GET_BUFFER(rules)
			s/tail: s/tail - 1
			p: as positions! s/tail
			series/head: p/input
			rules/head: p/rule
		]
	]

	process: func [
		input [red-series!]
		rule  [red-block!]
		case? [logic!]
		;strict? [logic!]
		return: [red-value!]
		/local
			new		 [red-series!]
			int		 [red-integer!]
			int2	 [red-integer!]
			blk		 [red-block!]
			sym*	 [red-symbol!]
			cmd		 [red-value!]
			tail	 [red-value!]
			value	 [red-value!]
			base	 [red-value!]
			char	 [red-char!]
			dt		 [red-datatype!]
			w		 [red-word!]
			t 		 [triple!]
			p		 [positions!]
			state	 [integer!]
			type	 [integer!]
			sym		 [integer!]
			min		 [integer!]
			max		 [integer!]
			s		 [series!]
			cnt		 [integer!]
			upper?	 [logic!]
			end?	 [logic!]
			ended?	 [logic!]
			match?	 [logic!]
			loop?	 [logic!]
			pop?	 [logic!]
			break?	 [logic!]
			rule?	 [logic!]
			collect? [logic!]
	][
		match?:	  yes
		end?:	  no
		ended?:   yes
		break?:	  no
		pop?:	  no
		rule?:	  no
		collect?: no
		value:	  null
		type:	  -1
		min:	  -1
		max:	  -1
		cnt:	  0
		state:    ST_NEXT_ACTION
		
		save-stack
		base: stack/push*								;-- slot on stack for COPY/SET operations (until OPTION?() is fixed)
		input: block/rs-append series as red-value! input	;-- input now points to the series stack entry
		
		cmd: (block/rs-head rule) - 1					;-- decrement to compensate for starting increment
		tail: block/rs-tail rule						;TBD: protect current rule block from changes
		
		until [
			#if debug? = yes [if verbose > 1 [print-state state]]
			
			switch state [
				ST_PUSH_BLOCK [
					none/rs-push rules
					PARSE_PUSH_POSITIONS
					block/rs-append rules as red-value! rule
					if all [value <> null value <> rule][
						assert TYPE_OF(value) = TYPE_BLOCK
						copy-cell value as red-value! rule
					]
					cmd: (block/rs-head rule) - 1		;-- decrement to compensate for starting increment
					tail: block/rs-tail rule			;TBD: protect current rule block from changes
					
					PARSE_CHECK_INPUT_EMPTY?			;-- refresh end? flag
					state: ST_NEXT_ACTION
				]
				ST_POP_BLOCK [
					either zero? block/rs-length? rules [
						state: ST_END
					][
						loop?: no
						ended?: cmd = tail
						
						s: GET_BUFFER(rules)
						copy-cell s/tail - 1 as red-value! rule
						assert TYPE_OF(rule) = TYPE_BLOCK
						p: as positions! s/tail - 2
						
						cmd: (block/rs-head rule) + p/rule
						tail: block/rs-tail rule
						s/tail: s/tail - 3
						value: s/tail - 1
						
						state: either all [
							0 < block/rs-length? rules 
							TYPE_OF(value) = TYPE_INTEGER
						][
							ST_POP_RULE
						][
							either match? [ST_NEXT_ACTION][ST_FIND_ALTERN]
						]
					]
				]
				ST_PUSH_RULE [
					either any [type = R_COPY type = R_SET][
						block/rs-append rules cmd
					][
						t: as triple! ALLOC_TAIL(rules)
						t/header: TYPE_TRIPLE
						t/min:	  min
						t/max:	  max
						t/state:  1
					]
					PARSE_PUSH_POSITIONS
					int: as red-integer! ALLOC_TAIL(rules)
					int/header: TYPE_INTEGER
					int/value: type
					if cmd < tail [cmd: cmd + 1]		;-- move after the rule prologue
					value: cmd
					state: ST_MATCH_RULE
				]
				ST_POP_RULE [
					s: GET_BUFFER(rules)
					value: s/tail - 1
					
					either any [
						s/offset + rules/head = s/tail	;-- rules stack empty already
						TYPE_OF(value) = TYPE_BLOCK    
					][
						state: either pop? [pop?: no ST_POP_BLOCK][ST_NEXT_ACTION]
					][
						pop?: yes
						p: as positions! s/tail - 2
						int: as red-integer! value
						switch int/value [
							R_WHILE
							R_NONE [					;-- iterative rules (ANY, SOME, WHILE, ...)
								t: as triple! s/tail - 3
								cnt: t/state
								either match? [
									loop?: either t/max = R_NONE [match?][cnt < t/max]
								][
									;@@ might need backtracking here
									match?: any [t/min <= (cnt - 1) zero? t/min]
								]
								if any [
									break?
									not match? 
									all [int/value <> R_WHILE input/head = p/input]
								][
									loop?: no
									break?: no
								]
								either any [end? not loop?][
									if all [match? cnt < t/min][match?: no]
								][
									t/state: cnt + 1
									cmd: (block/rs-head rule) + p/rule ;-- loop rule
									state: ST_NEXT_ACTION
									pop?: no
								]
							]
							R_TO
							R_THRU [
								either match? [
									if int/value = R_TO [
										input/head: p/input	;-- move input before the last match
										end?: no
									]
								][
									type: TYPE_OF(input)
									end?: either any [	;TBD: replace with ANY_STRING?
										type = TYPE_STRING
										type = TYPE_FILE
									][
										string/rs-next as red-string! input
									][
										block/rs-next input
									]
									either end? [
										w: as red-word! (block/rs-head rule) + p/rule + 1 ;-- TO/THRU argument
										match?: all [
											TYPE_OF(w) = TYPE_WORD 
											words/end = symbol/resolve w/symbol
										]
									][
										p/input: input/head	;-- refresh saved input head before new iteration
										cmd: (block/rs-head rule) + p/rule ;-- loop rule
										state: ST_NEXT_ACTION
										pop?: no
									]
								]
							]
							R_COPY [
								if match? [
									new: as red-series! value
									copy-cell as red-value! input as red-value! new
									copy-cell as red-value! input base	;@@ remove once OPTION? fixed
									new/head: p/input
									actions/copy new base no null
									_context/set as red-word! s/tail - 3 as red-value! new
								]
							]
							R_SET [
								if match? [
									PARSE_PICK_INPUT
									_context/set as red-word! p - 1 value
								]
							]
							R_KEEP
							R_KEEP_PAREN [
								if match? [
									blk: as red-block! stack/top - 1
									assert TYPE_OF(blk) = TYPE_BLOCK
									value: stack/top
									if int/value = R_KEEP [PARSE_PICK_INPUT]
									block/rs-append blk value 
								]
							]
							R_REMOVE [
								if match? [
									int/value: input/head - p/input
									input/head: p/input
									assert positive? int/value
									copy-cell as red-value! int base	;@@ remove once OPTION? fixed
									actions/remove input base
								]
							]
							R_AHEAD [
								input/head: p/input
								PARSE_CHECK_INPUT_EMPTY? ;-- refresh end? flag after backtracking
							]
							R_NOT [
								match?: not match?
							]
							R_COLLECT [
								either stack/top - 2 = base [	;-- root unnamed block reached
									collect?: yes
								][
									value: stack/top - 1
									assert TYPE_OF(value) = TYPE_BLOCK
									
									blk: as red-block! stack/top - 2
									collect?: either TYPE_OF(blk) = TYPE_WORD [
										_context/set as red-word! blk value
										stack/pop 1
										no
									][
										assert TYPE_OF(blk) = TYPE_BLOCK
										block/rs-append blk value
										yes
									]
									stack/pop 1
								]
							]
							R_INTO [
								s: GET_BUFFER(series)
								s/tail: s/tail - 1
								input: as red-series! s/tail - 1
								unless ended? [match?: no]
								if match? [input/head: input/head + 1]	;-- skip parsed series
								
								PARSE_CHECK_INPUT_EMPTY? ;-- refresh end? flag after popping series
								s: GET_BUFFER(rules)
							]
							R_THEN [
								s/tail: s/tail - 3		;-- pop rule stack frame
								state: either match? [cmd: tail ST_NEXT_ACTION][ST_FIND_ALTERN]
								pop?: no
							]
						]
						if pop? [
							s/tail: s/tail - 3			;-- pop rule stack frame
							state:  ST_CHECK_PENDING
						]
					]
					pop?: no
				]
				ST_CHECK_PENDING [
					s: GET_BUFFER(rules)
					value: s/tail - 1
					
					state: either any [					;-- order of conditional expressions matters!
						zero? block/rs-length? rules
						TYPE_OF(value) <> TYPE_INTEGER
					][
						either match? [ST_NEXT_ACTION][ST_FIND_ALTERN]
					][
						ST_POP_RULE
					]
				]
				ST_DO_ACTION [
					type: TYPE_OF(value)				;-- value is used in this state instead of cmd
					switch type [						;-- allows to enter the state with cmd or :cmd (if word!)
						TYPE_WORD 	[
							if all [value <> cmd TYPE_OF(cmd) = TYPE_WORD][
								print-line "*** Parse Error: invalid word in rule"
								halt
							]
							state: ST_WORD
						]
						TYPE_BLOCK 	[
							state: ST_PUSH_BLOCK
						]
						TYPE_DATATYPE [
							dt: as red-datatype! value
							value: block/rs-head input
							match?: TYPE_OF(value) = dt/value
							state: either match? [ST_NEXT_INPUT][ST_CHECK_PENDING]
						]
						TYPE_SET_WORD [
							_context/set as red-word! value as red-value! input
							state: ST_NEXT_ACTION
						]
						TYPE_GET_WORD [
							new: as red-series! _context/get as red-word! value
							either all [
								TYPE_OF(new) = TYPE_OF(input)
								new/node = input/node
							][
								input/head: new/head
								state: ST_NEXT_ACTION
							][
								print-line "*** Parse Error: get-word refers to a different series!"
							]
						]
						TYPE_INTEGER [
							int:  as red-integer! value
							int2: as red-integer! cmd + 1
							if all [
								int2 < tail
								TYPE_OF(int2) = TYPE_WORD
							][
								int2: as red-integer! _context/get as red-word! cmd + 1
							]
							upper?: TYPE_OF(int2) = TYPE_INTEGER
							if any [
								int2 = tail
								all [upper?	int2 + 1 = tail]
								all [upper? int/value > int2/value]
							][
								print-line "*** Parse Error: invalid integer rule"
							]
							state: either all [zero? int/value not upper?][
								cmd: cmd + 1			;-- skip over sub-rule
								ST_CHECK_PENDING
							][
								min:  int/value
								max:  either upper? [cmd: cmd + 1 int2/value][min]
								type: R_NONE
								ST_PUSH_RULE
							]
						]
						TYPE_PAREN [
							interpreter/eval as red-block! value no
							stack/pop 1
							state: ST_CHECK_PENDING
						]
						default [						;-- try to match a literal value
							state: ST_MATCH
						]
					]
				]
				ST_NEXT_INPUT [
					type: TYPE_OF(input)
					end?: either any [					;TBD: replace with ANY_STRING
						type = TYPE_STRING
						type = TYPE_FILE
					][
						string/rs-next as red-string! input
					][
						block/rs-next input
					]
					state: ST_CHECK_PENDING
				]
				ST_NEXT_ACTION [
					if cmd < tail [cmd: cmd + 1]
					
					state: either cmd = tail [
						ST_POP_BLOCK
					][
						value: cmd
						ST_DO_ACTION
					]
				]
				ST_MATCH [
					either end? [
						match?: no
					][
						type: TYPE_OF(input)
						end?: either any [				;TBD: replace with ANY_STRING?
							type = TYPE_STRING
							type = TYPE_FILE
						][
							match?: either TYPE_OF(value) = TYPE_BITSET [
								string/match-bitset? as red-string! input as red-bitset! value
							][
								string/match? as red-string! input value COMP_EQUAL
							]
							all [match? advance as red-string! input value]	;-- consume matched input
						][
							match?: actions/compare block/rs-head input value COMP_EQUAL
							all [match? block/rs-next input]				;-- consume matched input
						]
					]
					state: ST_CHECK_PENDING
				]
				ST_MATCH_RULE [
					either all [value = tail][
						match?: yes
						state: ST_CHECK_PENDING
					][
						switch TYPE_OF(value) [
							TYPE_BLOCK	 [state: ST_PUSH_BLOCK]
							TYPE_WORD	 [state: ST_WORD rule?: all [type <> R_COLLECT type <> R_KEEP]]
							TYPE_DATATYPE
							TYPE_SET_WORD
							TYPE_GET_WORD
							TYPE_INTEGER [state: ST_DO_ACTION]
							default [
								either min = R_NONE [
									state: either any [type = R_TO type = R_THRU][
										match?: find-token? rules input value case?
										ST_POP_RULE
									][
										ST_DO_ACTION
									]
								][
									match?: loop-token input value min max :cnt case?
									if all [not match? zero? min][match?: yes]
									s: GET_BUFFER(rules)
									s/tail: s/tail - 3		;-- pop rule stack frame
									state: ST_CHECK_PENDING
								]
								PARSE_CHECK_INPUT_EMPTY?
							]
						]
					]
				]
				ST_FIND_ALTERN [
					s: GET_BUFFER(rules)				;-- backtrack input
					p: as positions! s/tail - 2
					input/head: p/input
					PARSE_CHECK_INPUT_EMPTY?			;-- refresh end? flag after backtracking
					
					cnt: find-altern rule cmd
					
					state: either cnt >= 0 [
						cmd: cmd + cnt					;-- point rule head to alternative part
						match?: yes						;-- reset match? flag
						ST_NEXT_ACTION
					][
						ST_POP_BLOCK
					]
				]
				ST_WORD [
					w: as red-word! cmd
					sym: symbol/resolve w/symbol
					#if debug? = yes [
						sym*: symbol/get sym
						if verbose > 0 [print-line ["parse: " sym*/cache]]
					]
					case [
						sym = words/pipe [				;-- |
							cmd: tail
							state: ST_POP_BLOCK
						]
						sym = words/skip [				;-- SKIP
							PARSE_CHECK_INPUT_EMPTY?
							match?: not end?
							state: ST_NEXT_INPUT
						]
						sym = words/any* [				;-- ANY
							min:   0
							max:   R_NONE
							type:  R_NONE
							state: ST_PUSH_RULE
						]
						sym = words/some [				;-- SOME
							min:   1
							max:   R_NONE
							type:  R_NONE
							state: ST_PUSH_RULE
						]
						sym = words/copy [				;-- COPY
							cmd: cmd + 1
							if any [cmd = tail TYPE_OF(cmd) <> TYPE_WORD][
								print-line "*** Parse Error: invalid COPY rule"
							]
							min:   R_NONE
							type:  R_COPY
							state: ST_PUSH_RULE
						]
						sym = words/thru [				;-- THRU
							min:   R_NONE
							type:  R_THRU
							state: ST_PUSH_RULE
						]
						sym = words/to [				;-- TO
							min:   R_NONE
							type:  R_TO
							state: ST_PUSH_RULE
						]
						sym = words/remove [			;-- REMOVE
							min:   R_NONE
							type:  R_REMOVE
							state: ST_PUSH_RULE
						]
						sym = words/break* [			;-- BREAK
							match?: yes
							break?: yes
							cmd:	cmd + 1
							pop?:	yes
							state:	ST_POP_RULE
						]
						sym = words/opt [				;-- OPT
							min:   0
							max:   1
							type:  R_NONE
							state: ST_PUSH_RULE
						]
						sym = words/keep [				;-- KEEP
							value: cmd + 1
							min:   R_NONE
							type:  either TYPE_OF(value) = TYPE_PAREN [R_KEEP_PAREN][R_KEEP]
							state: ST_PUSH_RULE
						]
						sym = words/fail [				;-- FAIL
							match?: no
							state: ST_FIND_ALTERN
						]
						sym = words/ahead [				;-- AHEAD
							min:   R_NONE
							type:  R_AHEAD
							state: ST_PUSH_RULE
						]
						sym = words/while* [			;-- WHILE
							min:   0
							max:   R_NONE
							type:  R_WHILE
							state: ST_PUSH_RULE
						]
						sym = words/into [				;-- INTO
							if TYPE_OF(input) <> TYPE_BLOCK [
								print-line "*** Parse Error: INTO can only be used on a block! value"
							]
							value: cmd + 1
							if any [
								value = tail
								TYPE_OF(value) <> TYPE_BLOCK
							][
								print-line "*** Parse Error: INTO invalid argument"
							]
							value: block/rs-head input
							type: TYPE_OF(value)
							either any [				;@@ replace by ANY_SERIES?()
								type = TYPE_BLOCK
								type = TYPE_PAREN
								type = TYPE_PATH
								type = TYPE_LIT_PATH
								type = TYPE_SET_PATH
								type = TYPE_GET_PATH
								type = TYPE_STRING
								type = TYPE_FILE
							][
								input: block/rs-append series as red-value! block/rs-head input
								min:  R_NONE
								type: R_INTO
								state: ST_PUSH_RULE
							][
								match?: no
								state: ST_CHECK_PENDING
							]
						]
						sym = words/insert [			;-- INSERT
							w: as red-word! cmd + 1
							max: as-integer all [
								(as red-value! w) < tail
								TYPE_OF(w) = TYPE_WORD
								words/only = symbol/resolve w/symbol
							]
							cmd: cmd + max + 1
							actions/insert input cmd null max = 1 null no
							state: ST_NEXT_ACTION
						]
						sym = words/end [				;-- END
							PARSE_CHECK_INPUT_EMPTY?
							match?: end?
							state: ST_POP_RULE
						]
						sym = words/then [				;-- THEN
							if cmd + 1 = tail [
								print-line "*** Parse Error: THEN requires an argument rule"
							]
							min:   R_NONE
							type:  R_THEN
							state: ST_PUSH_RULE
						]
						sym = words/if* [				;-- IF
							cmd: cmd + 1
							if any [cmd = tail TYPE_OF(cmd) <> TYPE_PAREN][
								print-line "*** Parse Error: IF requires a paren argument"
							]
							interpreter/eval as red-block! cmd no
							match?: logic/top-true?
							stack/pop 1
							state: ST_CHECK_PENDING
						]
						sym = words/not* [				;-- NOT
							min:   R_NONE
							type:  R_NOT
							state: ST_PUSH_RULE
						]
						sym = words/quote [				;-- QUOTE
							cmd: cmd + 1
							if cmd = tail [
								print-line "*** Parse Error: missing QUOTE argument"
							]
							value: cmd
							state: ST_MATCH
						]
						sym = words/collect [			;-- COLLECT
							value: cmd + 1
							if all [
								value < tail
								TYPE_OF(value) = TYPE_WORD 
							][
								stack/push value
								cmd: value
							]
							block/push* 8
							min:   R_NONE
							type:  R_COLLECT
							state: ST_PUSH_RULE
						]
						sym = words/reject [			;-- REJECT
							match?: no
							break?: yes
							pop?:	yes
							state:	ST_POP_RULE
						]
						sym = words/set [				;-- SET
							cmd: cmd + 1
							if any [cmd = tail TYPE_OF(cmd) <> TYPE_WORD][
								print-line "*** Parse Error: invalid COPY rule"
							]
							min:   R_NONE
							type:  R_SET
							state: ST_PUSH_RULE
						]
						sym = words/none [				;-- NONE
							match?: yes
							state: ST_CHECK_PENDING
						]
						true [
							value: _context/get w
							state: either rule? [ST_MATCH_RULE][ST_DO_ACTION] ;-- enable fast loops for word argument
							rule?: no
						]
					]
				]
				ST_END [
					if match? [match?: cmd = tail]
					
					PARSE_SET_INPUT_LENGTH(cnt)
					if all [
						cnt > 0
						1 = block/rs-length? series
					][
						match?: no
					]
					state: ST_EXIT
				]
			]
			state = ST_EXIT
		]
		
		block/clear series
		block/clear rules
		restore-stack
		
		either collect? [
			base + 1
		][
			as red-value! logic/push match?
		]
	]

	init: does [
		series: block/make-in root 8
		rules:  block/make-in root 100
	]
]
