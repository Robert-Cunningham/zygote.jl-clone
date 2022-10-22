using IRTools: var, func
using IRTools

gradient_trace = []

function gradient_4(f, args...)
    ir = IRTools.@code_ir f(args...)
    len = length(ir.defs)

    (block_map, return_map) = statements_to_surrounding_block(f, args...)
    executed_blocks = trace_executed_blocks(f, args...)

    # remote unused blocks, so they don't clutter up the function suffix process.
    for i in length(ir.blocks):-1:0
        if i in executed_blocks
            break
        end

        IRTools.deleteblock!(ir, i)
    end

    # make sure we don't branch to anything that doesn't exist anymore.
    for block in ir.blocks
        for (i, branch) in enumerate(block.branches)
            if !(branch.block in executed_blocks)
                new_branch = IRTools.Branch(branch.condition, 1, branch.args)
                block.branches[i] = new_branch
            end
        end
    end

    println(block_map, executed_blocks, return_map)
    
	# this version works only for a single block
    #block = IRTools.blocks(ir)[length(ir.blocks)]
    
	# this version works only for a single return value
    #return_var = IRTools.returnvalue(block)

    last_block = executed_blocks[length(executed_blocks)]
    return_var = var(return_map[last_block])

    arg_count = ir.meta.nargs
    
    # every time we add something to gx, it gets a new intermediate variable to represent the new gx. 
    # x_to_gx keeps track of the most recent acucmulation for some variable x.
    x_to_gx = Dict()
    
    one = IRTools.insertafter!(ir, return_var, :(1))

    x_to_gx[return_var] = one
    
    for assignee in len:-1:(arg_count+1)
        if !(block_map[assignee] in executed_blocks)
            println("skipped ", assignee)
            continue
        end
        if !(var(assignee) in keys(ir))
            continue
        end
		ex = ir[var(assignee)].expr
		if ex.head == :call
            if !(var(assignee) in keys(x_to_gx)) # assignee isn't in x_to_gx only if it's never used; e.g. it's a branching variable or similar.
                continue
            end
            g_assignee = x_to_gx[var(assignee)]
            for (i, a) in Iterators.enumerate(ex.args[2:length(ex.args)])
                g_old = get(x_to_gx, a, IRTools.push!(ir, :(0)))
				factor = derivative_rule(eval(ex.args[1]), ex.args[2: length(ex.args)], i)
                g_new = IRTools.push!(ir, :($(g_old) + $(g_assignee) * $(factor)))
                
                x_to_gx[a] = g_new
 			end
		end
    end

    null = IRTools.push!(ir, :(nothing))
    
    outs = [return_var]
    
    for o in 2:arg_count
        g_arg = get(x_to_gx, var(o), null)
        push!(outs, g_arg)
    end
    
    out_var = IRTools.push!(ir, nothing)

    # needed to bypass an internal bug with using tuples directly. Don't ask how long it took to figure this out.
    ir[out_var] = IRTools.Inner.Statement(:($(GlobalRef(Core, :tuple))($(outs...),)))
    
    IRTools.return!(ir, out_var)

    println(ir)

    #return ir

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

function statements_to_surrounding_block(f, args...)
    ir = IRTools.@code_ir f(args...)
    
    block_map = Dict()
    return_map = Dict()

    current_block = 0
    for l in split(string(ir), '\n')
        if occursin(r"^\d*:", l)
            current_block = parse(Int64, strip(split(l, ":")[1]))
        elseif occursin(r"=", l)
            v = parse(Int64, match(r"%(\d*) =", l)[1])
            block_map[v] = current_block
        elseif occursin(r"return", l)
            v = parse(Int64, match(r"return %(\d*)", l)[1])
            return_map[current_block] = v
        end
    end
    
    return (block_map, return_map)
end

function trace_executed_blocks(f, args...)
    global gradient_trace
    gradient_trace = []
    
    ir = IRTools.@code_ir f(args...)
    for m in eachmatch(r"(\d.*):.*\n  %(\d*)", string(ir)) #we're using regex here because the IRTools API somehow doesn't expose the thing we want.
        block_index, var_index = parse(Int64, m[1]), parse(Int64, m[2])
        IRTools.insert!(ir, IRTools.var(var_index), :(push!($(GlobalRef(Main, :gradient_trace)), $(block_index))))
    end

    Base.invokelatest(IRTools.func(ir), nothing, args...)
    
    return gradient_trace
end