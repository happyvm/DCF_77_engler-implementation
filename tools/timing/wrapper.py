"""Generate an isolated timing wrapper around a DUT.

Principle (from the BEA-37 specification)::

    registered inputs  ->  DUT  ->  registered outputs

Every non-clock input is captured by a wrapper register; every output is
registered inside the wrapper.  The registered DUT outputs are then folded into
a compact signature and only ``clk`` + ``sig_o`` leave the wrapper.  This keeps
the measurement **pad-free** (no external I/O path is ever part of the DUT's
register-to-register path) and keeps every benchmark inside the package IO
budget regardless of how wide the DUT's ports are.

The DUT is never modified and is instantiated with its production default
parameters (or an explicit, documented override for blocks whose default
configuration folds to an empty design).
"""

from __future__ import annotations

from .svparse import Port, parse_module_ports, get_parameter_text

# Inactive level for the reset ports we recognise.  Matched by exact name so
# functional inputs such as ``reset_cycle`` (a correlation-accumulator reset,
# not a design reset) are NOT treated as resets.
_INACTIVE = {
    "rst": "1'b0",
    "rst_n": "1'b1",
    "reset": "1'b0",
    "reset_n": "1'b1",
}

SIG_BITS = 16


def generate_wrapper(module: str, ports: list[Port], clock: str, source: str,
                     param_text: str = "", params: dict[str, str] | None = None) -> str:
    ins = [p for p in ports if p.direction == "input"]
    outs = [p for p in ports if p.direction == "output"]
    for p in ports:
        if p.direction == "inout":
            raise ValueError(f"{module}: inout port {p.name!r} is not benchmarkable")

    # A purely combinational module has no clock port; the wrapper clock then
    # only times the wrapper registers (reg -> DUT -> reg), which is the
    # intended isolation for such blocks.

    def d(p: Port) -> str:
        sign = " signed" if p.signed else ""
        return sign + (f" {p.dim}" if p.dim else "")

    lines: list[str] = []
    lines.append(f"// AUTO-GENERATED timing wrapper for {module!r} by tools/timing/wrapper.py.")
    lines.append(f"// Source: {source}")
    lines.append("// principle: registered inputs -> DUT -> registered outputs -> signature.")
    lines.append("// Clock : %s.  Resets held inactive." % clock)
    lines.append("// Data inputs are driven by free-running counters so no input")
    lines.append("// net is constant (constant inputs would be folded and prune the")
    lines.append("// logic under test).  The DUT is instantiated with default parameters")
    lines.append("// unless an explicit override is documented in the block registry.")
    lines.append("// Only clk and the folded signature are exposed: the whole")
    lines.append("// register-to-register path under test is internal (no pad delay).")
    lines.append("`timescale 1ns/1ps")
    if param_text:
        lines.append(f"module {module}__timing #(")
        lines.append(param_text)
        lines.append(f") (")
    else:
        lines.append(f"module {module}__timing (")
    port_decls = [
        "    input  logic clk",
        f"    output logic [{SIG_BITS-1}:0] sig_o",
    ]
    lines.append(",\n".join(port_decls))
    lines.append(");")

    # Registered input sources.
    for p in ins:
        if p.name in _INACTIVE:
            lines.append(f"    logic{d(p)} sig_{p.name};")
            lines.append(f"    assign sig_{p.name} = {_INACTIVE[p.name]};")
        elif p.name == clock:
            lines.append(f"    logic sig_{p.name};")
            lines.append(f"    assign sig_{p.name} = clk;")
        else:
            lines.append(f"    logic{d(p)} sig_{p.name};")
            lines.append(f"    always_ff @(posedge clk) sig_{p.name} <= sig_{p.name} + 1'b1;")

    # DUT output nets.
    for p in outs:
        lines.append(f"    logic{d(p)} sig_{p.name}_w;")

    # DUT instance.  Optional per-block parameter overrides are needed only
    # when a block's production *default* configuration folds to an empty
    # design (e.g. receiver_lock_controller with QUALIFICATION_ENABLED = 0);
    # such overrides are recorded in the report's `config` field.
    if params:
        over = ", ".join(f".{k}({v})" for k, v in params.items())
        lines.append(f"    {module} #({over}) dut (")
    else:
        lines.append(f"    {module} dut (")
    conns = []
    for p in ports:
        net = f"sig_{p.name}" if p.direction == "input" else f"sig_{p.name}_w"
        conns.append(f"        .{p.name}({net})")
    lines.append(",\n".join(conns))
    lines.append("    );")

    # Registered DUT outputs.
    for p in outs:
        lines.append(f"    logic{d(p)} sig_{p.name}_q;")
        lines.append(f"    always_ff @(posedge clk) sig_{p.name}_q <= sig_{p.name}_w;")

    # Fold registered outputs into a compact, non-constant signature.
    lines.append("    logic sig_fold;")
    if outs:
        concat = ", ".join(f"sig_{p.name}_q" for p in outs)
        lines.append(f"    assign sig_fold = ^{{{concat}}};")
    else:
        lines.append("    assign sig_fold = 1'b0;")
    lines.append(f"    logic [{SIG_BITS-1}:0] sig_q, sig_ctr;")
    lines.append("    always_ff @(posedge clk) begin")
    lines.append("        sig_ctr <= sig_ctr + 16'd1;")
    lines.append(f"        sig_q   <= {{sig_q[{SIG_BITS-2}:0], sig_fold ^ sig_ctr[0]}};")
    lines.append("    end")
    lines.append("    assign sig_o = sig_q ^ sig_ctr;")

    lines.append("endmodule")
    lines.append("")
    return "\n".join(lines)


def wrapper_for_source(module: str, source_text: str, clock: str, source: str,
                       params: dict[str, str] | None = None) -> tuple[str, list[Port]]:
    ports = parse_module_ports(source_text, module)
    param_text = get_parameter_text(source_text, module)
    return generate_wrapper(module, ports, clock, source, param_text, params), ports
