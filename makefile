all: ica
ica:
	iverilog -g2005-sv -DICARUS=1 -o tb.qqq tb.v kr580vm80a.v
	vvp tb.qqq >> /dev/null
vcd:
	gtkwave tb.vcd
wave:
	gtkwave tb.gtkw
clean:
	rm -rf obj_dir tb tb.vcd tb.gtkw
