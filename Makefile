
EBIN = ebin
TARGET = erocco
MAIN_MODULE = erocco_main

all: compile escriptize

compile:
	@erl -make

escriptize:
	@escript $(EBIN)/bootstrap.erl $(TARGET) $(EBIN) $(MAIN_MODULE)

clean:
	@rm -rf $(EBIN)/*.beam erl_crash.dump
