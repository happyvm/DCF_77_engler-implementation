"""BEA-37 block/subsystem timing-characterisation infrastructure.

Modules:
    svparse   SystemVerilog ANSI port-list parser
    wrapper   isolated timing-wrapper generator (registered I/O)
    nextpnr   post-route report/log parser
    registry  block and subsystem catalogue
    run       campaign runner (Yosys + nextpnr)
    report    CSV/Markdown report generator
    compare   before/after campaign comparison
"""
