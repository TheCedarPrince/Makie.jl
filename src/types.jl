abstract type AbstractCamera end

# placeholder if no camera is present
struct EmptyCamera <: AbstractCamera end

@enum RaymarchAlgorithm begin
    IsoValue # 0
    Absorption # 1
    MaximumIntensityProjection # 2
    AbsorptionRGBA # 3
    AdditiveRGBA # 4
    IndexedAbsorptionRGBA # 5
end

include("interaction/iodevices.jl")


"""
This struct provides accessible `Observable`s to monitor the events
associated with a Scene.

Functions that act on a `Observable` must return `Consume()` if the function
consumes an event. When an event is consumed it does
not trigger other observer functions. The order in which functions are exectued
can be controlled via the `priority` keyword (default 0) in `on`.

Example:
```
on(events(scene).mousebutton, priority = 20) do event
    if is_correct_event(event)
        do_something()
        return Consume()
    end
    return
end
```

## Fields
$(TYPEDFIELDS)
"""
struct Events
    """
    The area of the window in pixels, as a `Rect2`.
    """
    window_area::Observable{Rect2i}
    """
    The DPI resolution of the window, as a `Float64`.
    """
    window_dpi::Observable{Float64}
    """
    The state of the window (open => true, closed => false).
    """
    window_open::Observable{Bool}

    """
    Most recently triggered `MouseButtonEvent`. Contains the relevant
    `event.button` and `event.action` (press/release)

    See also [`ispressed`](@ref).
    """
    mousebutton::Observable{MouseButtonEvent}
    """
    A Set of all currently pressed mousebuttons.
    """
    mousebuttonstate::Set{Mouse.Button}
    """
    The position of the mouse as a `NTuple{2, Float64}`.
    Updates once per event poll/frame.
    """
    mouseposition::Observable{NTuple{2, Float64}} # why no Vec2?
    """
    The direction of scroll
    """
    scroll::Observable{NTuple{2, Float64}} # why no Vec2?

    """
    Most recently triggered `KeyEvent`. Contains the relevant `event.key` and
    `event.action` (press/repeat/release)

    See also [`ispressed`](@ref).
    """
    keyboardbutton::Observable{KeyEvent}
    """
    Contains all currently pressed keys.
    """
    keyboardstate::Set{Keyboard.Button}

    """
    Contains the last typed character.
    """
    unicode_input::Observable{Char}
    """
    Contains a list of filepaths to files dragged into the scene.
    """
    dropped_files::Observable{Vector{String}}
    """
    Whether the Scene window is in focus or not.
    """
    hasfocus::Observable{Bool}
    """
    Whether the mouse is inside the window or not.
    """
    entered_window::Observable{Bool}
end

function Base.show(io::IO, events::Events)
    println(io, "Events:")
    fields = propertynames(events)
    maxlen = maximum(length ∘ string, fields)
    for field in propertynames(events)
        pad = maxlen - length(string(field)) + 1
        println(io, "  $field:", " "^pad, to_value(getproperty(events, field)))
    end
end

function Events()
    events = Events(
        Observable(Recti(0, 0, 0, 0)),
        Observable(100.0),
        Observable(false),

        Observable(MouseButtonEvent(Mouse.none, Mouse.release)),
        Set{Mouse.Button}(),
        Observable((0.0, 0.0)),
        Observable((0.0, 0.0)),

        Observable(KeyEvent(Keyboard.unknown, Keyboard.release)),
        Set{Keyboard.Button}(),
        Observable('\0'),
        Observable(String[]),
        Observable(false),
        Observable(false),
    )

    connect_states!(events)
    return events
end

function connect_states!(e::Events)
    on(e.mousebutton, priority = typemax(Int)) do event
        set = e.mousebuttonstate
        if event.action == Mouse.press
            push!(set, event.button)
        elseif event.action == Mouse.release
            delete!(set, event.button)
        else
            error("Unrecognized Keyboard action $(event.action)")
        end
        # This never consumes because it just keeps track of the state
        return Consume(false)
    end

    on(e.keyboardbutton, priority = typemax(Int)) do event
        set = e.keyboardstate
        if event.key != Keyboard.unknown
            if event.action == Keyboard.press
                push!(set, event.key)
            elseif event.action == Keyboard.release
                delete!(set, event.key)
            elseif event.action == Keyboard.repeat
                # set should already have the key
            else
                error("Unrecognized Keyboard action $(event.action)")
            end
        end
        # This never consumes because it just keeps track of the state
        return Consume(false)
    end
    return
end

# Compat only
function Base.getproperty(e::Events, field::Symbol)
    if field === :mousebuttons
        error("`events.mousebuttons` is deprecated. Use `events.mousebutton` to react to `MouseButtonEvent`s instead.")
    elseif field === :keyboardbuttons
        error("`events.keyboardbuttons` is deprecated. Use `events.keyboardbutton` to react to `KeyEvent`s instead.")
    elseif field === :mousedrag
        error("`events.mousedrag` is deprecated. Use `events.mousebutton` or a mouse state machine (`addmouseevents!`) instead.")
    else
        return getfield(e, field)
    end
end

function Base.empty!(events::Events)
    for field in fieldnames(Events)
        field in (:mousebuttonstate, :keyboardstate) && continue
        obs = getfield(events, field)
        for (prio, f) in obs.listeners
            prio == typemax(Int) && continue
            off(obs, f)
        end
    end
    return
end


"""
    Camera(pixel_area)

Struct to hold all relevant matrices and additional parameters, to let backends
apply camera based transformations.
"""
struct Camera
    """
    projection used to convert pixel to device units
    """
    pixel_space::Observable{Mat4f}

    """
    View matrix is usually used to rotate, scale and translate the scene
    """
    view::Observable{Mat4{Float64}}

    """
    Projection matrix is used for any perspective transformation
    """
    projection::Observable{Mat4{Float64}}

    """
    just projection * view
    """
    projectionview::Observable{Mat4{Float64}}

    """
    resolution of the canvas this camera draws to
    """
    resolution::Observable{Vec2f}

    """
    Eye position of the camera, sued for e.g. ray tracing.
    """
    eyeposition::Observable{Vec3f} # TODO Should this be Float64?

    """
    To make camera interactive, steering observables are connected to the different matrices.
    We need to keep track of them, so, that we can connect and disconnect them.
    """
    steering_nodes::Vector{ObserverFunction}
end

"""
Holds the transformations for Scenes.
## Fields
$(TYPEDFIELDS)
"""
struct Transformation <: Transformable
    parent::RefValue{Transformation}
    translation::Observable{Vec3f}
    scale::Observable{Vec3f}
    rotation::Observable{Quaternionf}
    model::Observable{Mat4f}
    # data conversion observable, for e.g. log / log10 etc
    transform_func::Observable{Any}
    function Transformation(translation, scale, rotation, model, transform_func)
        return new(
            RefValue{Transformation}(),
            translation, scale, rotation, model, transform_func
        )
    end
end

"""
`PlotSpec{P<:AbstractPlot}(args...; kwargs...)`

Object encoding positional arguments (`args`), a `NamedTuple` of attributes (`kwargs`)
as well as plot type `P` of a basic plot.
"""
struct PlotSpec{P<:AbstractPlot}
    args::Tuple
    kwargs::NamedTuple
    PlotSpec{P}(args...; kwargs...) where {P<:AbstractPlot} = new{P}(args, values(kwargs))
end

PlotSpec(args...; kwargs...) = PlotSpec{Combined{Any}}(args...; kwargs...)

Base.getindex(p::PlotSpec, i::Int) = getindex(p.args, i)
Base.getindex(p::PlotSpec, i::Symbol) = getproperty(p.kwargs, i)

to_plotspec(::Type{P}, args; kwargs...) where {P} =
    PlotSpec{P}(args...; kwargs...)

to_plotspec(::Type{P}, p::PlotSpec{S}; kwargs...) where {P, S} =
    PlotSpec{plottype(P, S)}(p.args...; p.kwargs..., kwargs...)

plottype(::PlotSpec{P}) where {P} = P


struct ScalarOrVector{T}
    sv::Union{T, Vector{T}}
end

Base.convert(::Type{<:ScalarOrVector}, v::AbstractVector{T}) where T = ScalarOrVector{T}(collect(v))
Base.convert(::Type{<:ScalarOrVector}, x::T) where T = ScalarOrVector{T}(x)
Base.convert(::Type{<:ScalarOrVector{T}}, x::ScalarOrVector{T}) where T = x

function collect_vector(sv::ScalarOrVector, n::Int)
    if sv.sv isa Vector
        if length(sv.sv) != n
            error("Requested collected vector with $n elements, contained vector had $(length(sv.sv)) elements.")
        end
        sv.sv
    else
        fill(sv.sv, n)
    end
end

"""
    GlyphExtent

Store information about the bounding box of a single glyph.
"""
struct GlyphExtent
    ink_bounding_box::Rect2f
    ascender::Float32
    descender::Float32
    hadvance::Float32
end

function GlyphExtent(font, char)
    extent = get_extent(font, char)
    ink_bb = FreeTypeAbstraction.inkboundingbox(extent)
    ascender = FreeTypeAbstraction.ascender(font)
    descender = FreeTypeAbstraction.descender(font)
    hadvance = FreeTypeAbstraction.hadvance(extent)

    return GlyphExtent(ink_bb, ascender, descender, hadvance)
end

function GlyphExtent(texchar::TeXChar)
    l = MathTeXEngine.leftinkbound(texchar)
    r = MathTeXEngine.rightinkbound(texchar)
    b = MathTeXEngine.bottominkbound(texchar)
    t = MathTeXEngine.topinkbound(texchar)
    ascender = MathTeXEngine.ascender(texchar)
    descender = MathTeXEngine.descender(texchar)
    hadvance = MathTeXEngine.hadvance(texchar)

    return GlyphExtent(Rect2f((l, b), (r - l, t - b)), ascender, descender, hadvance)
end

"""
    GlyphCollection

Stores information about the glyphs in a string that had a layout calculated for them.
"""
struct GlyphCollection
    glyphs::Vector{UInt64}
    fonts::Vector{FTFont}
    origins::Vector{Point3f}
    extents::Vector{GlyphExtent}
    scales::ScalarOrVector{Vec2f}
    rotations::ScalarOrVector{Quaternionf}
    colors::ScalarOrVector{RGBAf}
    strokecolors::ScalarOrVector{RGBAf}
    strokewidths::ScalarOrVector{Float32}

    function GlyphCollection(glyphs, fonts, origins, extents, scales, rotations,
            colors, strokecolors, strokewidths)

        n = length(glyphs)
        @assert length(fonts) == n
        @assert length(origins) == n
        @assert length(extents) == n
        @assert attr_broadcast_length(scales) in (n, 1)
        @assert attr_broadcast_length(rotations) in (n, 1)
        @assert attr_broadcast_length(colors) in (n, 1)

        rotations = convert_attribute(rotations, key"rotation"())
        fonts = [convert_attribute(f, key"font"()) for f in fonts]
        colors = convert_attribute(colors, key"color"())
        strokecolors = convert_attribute(strokecolors, key"color"())
        strokewidths = Float32.(strokewidths)
        new(glyphs, fonts, origins, extents, scales, rotations, colors, strokecolors, strokewidths)
    end
end


# The color type we ideally use for most color attributes
const RGBColors = Union{RGBAf, Vector{RGBAf}, Vector{Float32}}
