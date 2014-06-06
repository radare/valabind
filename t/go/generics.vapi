namespace Test {
	[Compact]
	[CCode (cprefix="a_", cname="A", free_function="a_free")]
	public class AA <G> {
		public int m1;
		public char m2;
		public string m3;
		public int type;

		public AA();
		public AA.from_it(G p1);
		public G f1();
		public void f2();
		public G f3(G p1);
		public void f4(G *p1);
		public G *f5();
	}
	[Compact]
	[CCode (cprefix="b_", cname="B", free_function="b_free")]
	public class BB {
		public AA<int> m1;
	}
}
