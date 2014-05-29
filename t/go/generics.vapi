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

	[Compact]
	[CCode (cprefix="c_", cname="C", free_function="c_free")]
	public class CC <G, H> {
		public G m1;
		public H m2;

		public CC();
	}
	[Compact]
	[CCode (cprefix="D_", cname="D", free_function="d_free")]
	public class DD {
		public CC<int, string> m1;
	}
	[Compact]
	[CCode (cprefix="e_", cname="E", free_function="e_free")]
	public class EE {
		public CC<string, AA<int>> m1;  // note, AA<int> already used
	[Compact]
	[CCode (cprefix="f_", cname="F", free_function="f_free")]
	public class FF {
		public CC<string, AA<string>> m1;  // note, AA<string> not yet defined
	}
}
}
