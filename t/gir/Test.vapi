namespace Test {
	public static void hello ();
	[CCode (cname="getenv")]
	public static string getenv (string k);

	public class Animal {
		int legs;
		public Animal ();
		public bool can_walk ();
	}

	public struct Ball {
		int size;
		string color;
	}
}
