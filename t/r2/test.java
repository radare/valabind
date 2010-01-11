class test {
	public static void main (String[] args) {
		rBreakpoint bp = new rBreakpoint ();
		bp.use ("x86");
		bp.add (0x804800, 0, 0);
		bp.list (0);
	}
}
