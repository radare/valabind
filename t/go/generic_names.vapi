namespace Test {
	[Compact]
	[CCode (cprefix="l_", cname="L", free_function="l_free")]
	public class List<G> {
		public List();
	}

	[Compact]
	[CCode (cprefix="m_", cname="M", free_function="m_free")]
	public class Map<G, H> {
		public Map();
	}


	[Compact]
	[CCode (cprefix="a_", cname="A", free_function="a_free")]
	public class AA {
		public List<int> m1;
		public Map<int, string> m2;
		public List<List<int>> m3;
		public Map<int, List<int>> m4;
		public Map<List<int>, int> m5;

		public AA();
	}
}
