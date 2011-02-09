import vstest
#import gobject

a = vstest.FoodElement ()
a.say ("world")
print ("--")
a.say ("cruel world")
print ("--")

# Creating a 2nd element make it segfault
#b=vstest.FoodElement ()
#b.say ("salsa")
