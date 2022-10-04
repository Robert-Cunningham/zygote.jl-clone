function differentiate(f, args...)
    #println(args)
    ir = IRTools.@code_ir f(args...)
    len = length(ir.defs)
    
    block = IRTools.blocks(ir)[1]
    
    return_var = IRTools.returnvalue(block)
    
    arg_count = ir.meta.nargs
    
    # every time we add something to gx, it gets a new intermediate variable to represent the new gx. 
    # x_to_gx keeps track of the most recent acucmulation for some variable x.
    x_to_gx = Dict()
    
    one = IRTools.insertafter!(ir, return_var, :(1))

    x_to_gx[return_var] = one
    
    for assignee in len:-1:(arg_count+1)
        try
            idx = length(ir)
            println("$(assignee) $(ir[var(assignee)]) $(idx)")

            ex = ir[var(assignee)].expr
            if ex.head == :call
                fn = string(ex.args[1])
                if fn == "Main.:+"
                    println("add")
                    # where %6 is assignee
                     # Take %6 = %4 + %5 and convert it into
                    # g4 += g6
                    # g5 += g6
                   
                    # where is the adjoint of the assignee?
                    g_assignee = x_to_gx[var(assignee)]
                    
                    # either get the variable that we've accumulated adjoints into so far, 
                    # or if it doesn't exist, initialize it to zero.
                    g_arg1_old = get(x_to_gx, ex.args[2], IRTools.push!(ir, :(0)))
                    g_arg2_old = get(x_to_gx, ex.args[3], IRTools.push!(ir, :(0)))
                    
                    # finally, add the new bit (g_assignee) and accumulate it into the new variable.
                    g_arg1_new = IRTools.push!(ir, :($(g_arg1_old) + $(g_assignee)))
                    g_arg2_new = IRTools.push!(ir, :($(g_arg2_old) + $(g_assignee)))
                    
                    x_to_gx[ex.args[2]] = g_arg1_new
                    x_to_gx[ex.args[3]] = g_arg2_new                    
                elseif fn == "Main.:*"
                    # Take %6 = %4 * %5 and convert it into
                    # g4 += g6 * %5
                    # g5 += g6 * %4
                    
                    g_assignee = x_to_gx[var(assignee)]
                    
                    # either get the variable that we've accumulated adjoints into so far, 
                    # or if it doesn't exist, initialize it to zero.
                    g_arg1_old = get(x_to_gx, ex.args[2], IRTools.push!(ir, :(0)))
                    g_arg2_old = get(x_to_gx, ex.args[3], IRTools.push!(ir, :(0)))
                    
                    g_arg1_new = IRTools.push!(ir, :($(g_arg1_old) + $(g_assignee) * $(ex.args[3])))
                    g_arg2_new = IRTools.push!(ir, :($(g_arg2_old) + $(g_assignee) * $(ex.args[2])))
                    
                    x_to_gx[ex.args[2]] = g_arg1_new
                    x_to_gx[ex.args[3]] = g_arg2_new                    
                    #println("add")
                elseif fn == "Main.sin"
                    g_assignee = x_to_gx[var(assignee)]
                    
                    # either get the variable that we've accumulated adjoints into so far, 
                    # or if it doesn't exist, initialize it to zero.
                    g_arg1_old = get(x_to_gx, ex.args[2], IRTools.push!(ir, :(0)))
                    
                    g_arg1_new = IRTools.push!(ir, :($(g_arg1_old) + $(g_assignee) * cos($(ex.args[2]))))
                    
                    x_to_gx[ex.args[2]] = g_arg1_new

                    #println("add")
                end
            end
            #IRTools.insertafter!(ir, var(idx + 1), :(println("Hello, ", $idx)))
            #IRTools.push!(ir, :(println("Hello, ", $idx)))
            #sv = var(s)
            #IRTools.push!(ir, :(sv * sv))
        catch a
            rethrow(a)
            println("Broke on ", assignee)
            break
        end
    end
    
    #vec_statement = IRTools.Inner.Statement(:(Base.vect()), Any, 1)
    #out_list_var = IRTools.push!(ir, vec_statement)
    
    outs = [return_var]
    
    for o in 2:arg_count
        g_arg = x_to_gx[var(o)]
        push!(outs, g_arg)
        #IRTools.push!(ir, :(println("Gradient of", $(o), "is", $(g_arg))))
    #    IRTools.push!(ir, :(Main.push!($(out_list_var), $(g_arg))))
    end
    
    println(x_to_gx)
    
    #out_var = IRTools.push!(ir, :(($(outs...,))))
    
    out_var = IRTools.push!(ir, nothing)
    # needed to bypass an internal bug with using tuples directly. Don't ask how long it took to figure this out.
    # ir[out_var] = IRTools.Inner.Statement(:(Core.tuple($(var(2)), $(var(3)))))
    ir[out_var] = IRTools.Inner.Statement(:($(GlobalRef(Core, :tuple))($(outs...),)))
    #:(Core.tuple($(outs[1]), $(outs[2]) )))
    
    IRTools.return!(ir, out_var)
    #IRTools.return!(ir, out_list_var)
    
    print(ir)
    
    compiled = func(ir)
    
    return compiled
    
    compiled(nothing, args...)
    
    #print(ir)
end