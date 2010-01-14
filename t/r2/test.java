//import java.math;

class test {
	public static void main (String[] args) {
		System.loadLibrary ("r_bp");
		rBreakpoint bp = new rBreakpoint ();
		bp.use ("x86");
		bp.add_sw (new java.math.BigInteger("0x804800"), 0, 0);
		bp.list (0);
	}
}
