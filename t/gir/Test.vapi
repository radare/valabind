namespace Test {
	public static void hello ();
	[CCode (cname="getenv")]
	public static string getenv (string k);
	public enum Mode {
		ALPHA,
		BETA
	}
	public static string? maybe_getenv (string? k);
	public static void take_strings (string[] values);

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
