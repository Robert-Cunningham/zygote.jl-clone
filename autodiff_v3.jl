using IRTools: var, func

function gradient_2(f, args...)
    ir = IRTools.@code_ir f(args...)
    len = length(ir.defs)
    
	# this version works only for a single block
    block = IRTools.blocks(ir)[1]
    
	# this version works only for a single return value
    return_var = IRTools.returnvalue(block)
    
    arg_count = ir.meta.nargs
    
    # every time we add something to gx, it gets a new intermediate variable to represent the new gx. 
    # x_to_gx keeps track of the most recent acucmulation for some variable x.
    x_to_gx = Dict()
    
    one = IRTools.insertafter!(ir, return_var, :(1))

    x_to_gx[return_var] = one
    
    for assignee in len:-1:(arg_count+1)
		ex = ir[var(assignee)].expr
		if ex.head == :call
            g_assignee = x_to_gx[var(assignee)]
            for (i, a) in Iterators.enumerate(ex.args[2:length(ex.args)])
                g_old = get(x_to_gx, a, IRTools.push!(ir, :(0)))
				factor = derivative_rule(eval(ex.args[1]), ex.args[2: length(ex.args)], i)
                g_new = IRTools.push!(ir, :($(g_old) + $(g_assignee) * $(factor)))
                
                x_to_gx[a] = g_new
 			end
		end
    end
    
    outs = [return_var]
    
    for o in 2:arg_count
        g_arg = x_to_gx[var(o)]
        push!(outs, g_arg)
    end
    
    out_var = IRTools.push!(ir, nothing)

    # needed to bypass an internal bug with using tuples directly. Don't ask how long it took to figure this out.
    ir[out_var] = IRTools.Inner.Statement(:($(GlobalRef(Core, :tuple))($(outs...),)))
    
    IRTools.return!(ir, out_var)

	result = Base.invokelatest(func(ir), nothing, args...)

	return result[2:length(result)]
end


# function get_expr_pullback_wrt_arg_i(ex, i)
# 	# do multiple dispatch
#     return derivative_rule(eval(ex.args[1]), ex.args[2:length(ex.args)], i)
# end

# derivative_rule returns the derivative rule wrt the argument at position i.
function derivative_rule(::typeof(sin), args, i)
    return :(cos($(args[1])))
end

function derivative_rule(::typeof(+), args, i)
    return 1
end

function derivative_rule(::typeof(*), args, i)
    if i == 1
        return args[2]
    elseif i == 2
        return args[1]
    end
end