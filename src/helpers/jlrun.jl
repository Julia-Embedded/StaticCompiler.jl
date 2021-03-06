using Libdl, LLVM

function show_inttoptr(mod)
    for fun in LLVM.functions(mod),
        blk in LLVM.blocks(fun),
        instr in LLVM.instructions(blk)

        s = string(instr)
        if occursin("inttoptr", s) && occursin(r"[0-9]{8,30}", s)
            println(LLVM.name(fun), "  ---------------------------")
            @show instr
            println()
        end
    end
end

"""
Compiles function call provided and calls it with `ccall` using the shared library that was created.
"""
macro jlrun(e)

    fun = e.args[1]
    efun = esc(fun)
    args = length(e.args) > 1 ? e.args[2:end] : Any[]
    libpath = abspath("test.o")
    dylibpath = abspath("test.so")
    tt = Tuple{(typeof(eval(a)) for a in args)...}
    if length(e.args) > 1
        ct = code_typed(Base.eval(__module__, fun), tt)
    else
        ct = code_typed(Base.eval(__module__, fun))
    end
    rettype = ct[1][2]
    bindir = joinpath(dirname(Sys.BINDIR), "tools")
    libdir = joinpath(dirname(Sys.BINDIR), "lib")

    runCommand = :(run(
        $(`$shellcmd -shared -fPIC -o test.so -L$libdir test.o -ljulia`),
        wait = true,
    ))

    quote
        m = irgen($efun, $tt)
        # m = irgen($efun, $tt, overdub = false)
        LLVM.verify(m)
        # show_inttoptr(m)
        write(m, "test.bc")
        write_object(m, "test.o")
        $runCommand
        dylib = Libdl.dlopen($dylibpath)
        ccall(Libdl.dlsym(dylib, "jl_init_globals"), Cvoid, ())
        res = ccall(
            Libdl.dlsym(dylib, $(Meta.quot(fun))),
            $rettype,
            ($((typeof(eval(a)) for a in args)...),),
            $(eval.(args)...),
        )
        Libdl.dlclose(dylib)
        res
    end
end
