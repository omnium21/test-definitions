# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2019 Schneider Electric
LINK_TARGET = uart-loopback
CFLAGS += -pthread -Os -Wall

OBJS = \
	uart-loopback.o


REBUILDABLES = $(OBJS) $(LINK_TARGET)

all : $(LINK_TARGET)
	echo All done

clean :
	rm -f $(REBUILDABLES)
	echo Clean done

$(LINK_TARGET) : $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^

%.o : %.cpp
	$(CC) $(CFLAGS) -o $@ -c $<
