using GLib;

public class Food.Element {
	public enum Counter {
		START,
		STOP,
		RESET
	}

	public Element () {
		print ("Element constructed\n");
	}

	~Element () {
		print ("Element destroyed\n");
	}

	public void say (string str) {
		print (@"Hello $(str)\n");
	}
}
