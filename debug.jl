#using Pkg
using MacroTools: prewalk, postwalk
using ChainRulesCore
using Zygote

# Pkg.add("MacroTools"); 
# Pkg.add("ChainRulesCore"); 
# Pkg.add("Zygote"); 

function crc_test(x)
    a = sin(x)
    b = 3 + a
    c = b^2
    return c
end

print(Zygote.gradient(x -> crc_test(x), 1))