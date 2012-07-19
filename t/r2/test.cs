using System;

public class test {
	public static void Main () {
		Console.WriteLine ("Hello World\n");
		RBreakpoint bp = new RBreakpoint ();
		bp.use ("x86");
		bp.add_hw (0x8048400, 0, 0);
		bp.list (0);
	}
}
