namespace Test {
	[CCode (lower_case_cprefix="test_")]
	namespace N {
		public static void fn1();
		public static int fn2(int p1, char p2, char *p3, int *p4);
		public static void fn3(out int p1);
		public static void fn4(string? p1=null);
		public static void fn5(out int p1=null);
		public static string fn6();
	}
}
