import vstest
#import gobject

a = vstest.Element ()
a.say ("world")
print ("--")
a.say ("cruel world")
print ("--")

# Creating a 2nd element make it segfault
b=vstest.Element ()
b.say ("salsa")
