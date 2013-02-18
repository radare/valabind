valabind todo
=============

0.7.4
-----
      [.] implement ctypes (dynamic python bindings) t/python/ctypes.py
        [ ] support for static methods
        [ ] support for generics


beyond
------
      [ ] Add support for Java using JNA
      [ ] Add support for Go
      [ ] Add support for unions (required for dynamic bindings)
      [ ] Unify all output modes
            --ctypes --swig --node ... those are should not be flags
          Use something like this:
            --mode=gir --mode=swig --mode=c++
            --format=gir
      [ ] Add support to compile from C, do not generate (valabind-cc)
      [ ] Add support for destructors (class.get_destructor () ..
      [ ] Add support for varargs
          //%varargs(int mode = 0) open;
          int open(const char *path, int oflags, int mode = 0);
      [ ] Add support for contractual programming
          %contract Foo::bar(int x, int y) {
          require:
            x > 0;
          ensure:
            bar > 0;
          }
      [ ] Add support for exceptions (See %exception)
      [ ] Add support for properties
      [ ] Add support for %namespace foo { ... }
      [ ] Use templates in Swig?
          %template(intList) List<int>;
          typedef int Integer
          void foo (vector<Integer> *x);
