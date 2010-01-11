using System;

public class test {
	public static void Main () {
		Console.WriteLine ("Hello World\n");
		rBreakpoint bp = new rBreakpoint ();
		bp.use ("x86");
		bp.add_hw (0x8048400, 0, 0);
		bp.list (0);
	}
}
