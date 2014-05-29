// test for converting lowercase symbol names with a bunch of '_'
// to CamelCase
namespace Test {
	[CCode (lower_case_cprefix="test_")]
	namespace N {
		public static void fn1();  // --> Fn1
		public static void fn_fn2();  // --> FnFn2
		public static void fn_fn3_();  // --> FnFn3_
		public static void fn_fn4_a();  // --> FnFn4A
		public static void fn6__();  // --> Fn6__
		public static void fn_f7();  // --> FnF7
	}
}
