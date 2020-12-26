#include "vstest.cxx"

int main () {
	vstest_FoodElement *foo = new vstest_FoodElement ();
	foo->say ("world");
	foo->say ("cruel world");
	delete foo;
	return 0;
}
