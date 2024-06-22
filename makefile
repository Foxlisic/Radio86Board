VRL=/usr/share/verilator/include

all: ica
app: vbuild
	g++ -o tb -I$(VRL) $(VRL)/verilated.cpp tb.cc obj_dir/Vvg75__ALL.a -lSDL2
	./tb
ica:
	iverilog -g2005-sv -DICARUS=1 -o tb.qqq tb.v kr580vm80a.v
	vvp tb.qqq >> /dev/null
vbuild:
	verilator -cc vg75.v
	cd obj_dir && make -f Vvg75.mk
vcd:
	gtkwave tb.vcd
wave:
	gtkwave tb.gtkw
clean:
	rm -rf obj_dir tb tb.vcd tb.gtkw
