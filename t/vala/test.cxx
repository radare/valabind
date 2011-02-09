#include "vstest.cxx"

int main () {
	vstestFoodElement *foo = new vstestFoodElement ();
	foo->say ("world");
	foo->say ("cruel world");
	delete foo;
	return 0;
}
