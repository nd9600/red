/*
	Shared library for testing
*/

#ifdef _MSC_VER
	#define EXPORT __declspec(dllexport)
#else
	#define EXPORT extern
#endif

typedef struct tiny {
	char b1;
} tiny;

typedef struct small {
	long one;
	long two;
} small;

typedef struct big {
	long one;
	long two;
	double three;
} big;

typedef struct huge {
	long one;
	long two;
	double three;
	long four;
	long five;
	double six;
} huge;

typedef struct huge3 {
	long one;
	long two;
	long three;
	long four;
	long five;
	long six;
} huge3;

typedef struct bigf32 {
	long one;
	long two;
	float three;
} bigf32;

typedef struct hugef32 {
	float one;
	long two;
	float three;
	long four;
	long five;
	float six;
} hugef32;



EXPORT tiny returnTiny(void) {
	tiny t = { 'z' };
	return t;
}

EXPORT small returnSmall(void) {
	small t = { 111,222 };
	return t;
}

EXPORT big returnBig(void) {
	big t = { 111,222,3.14159 };
	return t;
}

EXPORT huge returnHuge(int a, int b) {
	huge t = { 111,222,3.5,444,555,6.789 };
	t.one = a;
	t.two = b;
	return t;
}

EXPORT huge returnHuge2(huge h, int a, int b) {
	huge t = { 111,222,3.5,444,555,6.789 };
	h.four = 0xBAD0CAFE;	/* try to corrupt h buffer to test for unwanted side-effects */
	t.one = a;
	t.two = b;
	t.six = h.six;
	return t;
}

EXPORT huge3 returnHuge3(huge3 h, int a, int b) {
	huge3 t = { 111,222,3,444,555,789 };
	h.four = 0xBAD0CAFE;	/* try to corrupt h buffer to test for unwanted side-effects */
	t.one = a;
	t.two = b;
	t.six = h.six;
	return t;
}

EXPORT hugef32 returnHugef32(hugef32 h, int a, int b) {
	hugef32 t = { 1.11f,222,3.5f,444,555,6.789f };
	h.four = 0xBAD0CAFE;	/* try to corrupt h buffer to test for unwanted side-effects */
	t.one = 1.23f;
	t.two = b;
	t.six = h.six;
	return t;
}