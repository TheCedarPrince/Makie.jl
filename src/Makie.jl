__precompile__(true)
module Makie

using Reactive, GeometryTypes, Colors, StaticArrays

using Colors, GeometryTypes, GLVisualize, GLAbstraction, ColorVectorSpace
using StaticArrays, GLWindow, ModernGL, Contour
import Quaternions
using Primes

using Base.Iterators: repeated, drop
using Base: RefValue
using Fontconfig, FreeType, FreeTypeAbstraction, UnicodeFun
using IntervalSets

include("types.jl")
include("utils.jl")
include("signals.jl")

GLAbstraction.gl_convert(x::Vector{Vec3f0}) = x

include("scene.jl")

include("basic_drawing.jl")
include("basic_recipes.jl")
include("layouting.jl")

include("attribute_conversion.jl")


include("events.jl")
include("glbackend/glbackend.jl")
include("cairo/cairo.jl")

include("plot.jl")
include("camera2d.jl")
include("camera3d.jl")
include("axis2d.jl")
include("axis3d.jl")
include("buffers.jl")
include("legend.jl")
include("output.jl")
include("gui.jl")

export cam2d!, campixel!, cam3d!, update_cam!, Scene, Screen, plot!, CairoScreen, axis2d, RGBAf0
export Combined, Theme, node, @extract, translated, translate!, transform!, grid
# picking
export mouseover, onpick, pick, @key_str, attribute_convert, Attributes, colorlegend
export (..) # reexport interval

end
