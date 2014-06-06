namespace Test {
	[Compact]
	[CCode (cprefix="a_", cname="A", free_function="a_free")]
	public class AA {
		public int m1;
		public char m2;
		public string m3;
		public int type;

		public AA();
		public AA.from_string(string p1);
		public int f1();
		public void f2();
		public int f3(int p1);
		public string f4(string p1);
		public void *f5(void *p1);
	}
}
