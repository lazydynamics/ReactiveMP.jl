export RandomVariable, RandomVariableCreationOptions, randomvar

import Base: show
import Rocket: getscheduler

## Random variable implementation

mutable struct RandomVariableProperties <: VariableProperties
    const input_messages  :: Vector{MessageObservable{AbstractMessage}}
    const output_messages :: Vector{MessageObservable{Message}}
    output_initialised    :: Bool
    output_cache          :: Union{Nothing, EqualityChain}
    const marginal        :: MarginalObservable
    const message_prod_fn
    const marginal_prod_fn
    const pipeline
end

function RandomVariableProperties()
    return RandomVariableProperties(
        Vector{MessageObservable{AbstractMessage}}(),
        Vector{MessageObservable{Message}}(),
        false,
        nothing,
        MarginalObservable(),
        messages_prod_fn(FoldLeftProdStrategy(), GenericProd(), UnspecifiedFormConstraint(), FormConstraintCheckLast()),
        marginal_prod_fn(FoldLeftProdStrategy(), GenericProd(), UnspecifiedFormConstraint(), FormConstraintCheckLast()),
        EmptyPipelineStage()
    )
end

function setmessagein!(properties::RandomVariableProperties, messagein)
    # The `setmessagein!` function for random variables record the input message and return the updated properties
    # It also returns the index of the input message that has been added
    push!(properties.input_messages, messagein)
    return properties, length(properties.input_messages)
end

struct RandomVariableActivationOptions{S}
    scheduler::S
end

# options here must implement at least `Rocket.getscheduler`
function activate!(properties::RandomVariableProperties, options::RandomVariableActivationOptions)
    if properties.output_initialised === true
        error("`activate!` cannot be called on the random variable that has already been activated.")
    end

    # `5` here is empirical observation, maybe we can come up with better heuristic?
    # in case if number of connections is large we use cache equality nodes chain structure 
    if length(properties.input_messages) > 5
        properties.output_cache = EqualityChain(properties.input_messages, schedule_on(options.scheduler), properties.message_prod_fn)
    end

    _setmarginal!(properties, _makemarginal(properties))
    return nothing
end

initialize_output_messages!(properties::RandomVariableProperties) = initialize_output_messages!(properties.output_cache, properties)

# Generic fallback for variables with small number of connected nodes, somewhere <= 5
# We do not create equality chain in this cases, but simply do eager product
function initialize_output_messages!(::Nothing, properties::RandomVariableProperties)
    d          = length(properties.input_messages)
    outputmsgs = properties.output_messages
    inputmsgs  = properties.input_messages
    prod_fn    = properties.messages_prod_fn

    resize!(outputmsgs, d)

    @inbounds for i in 1:d
        outputmsgs[i] = MessageObservable(Message)
        outputmsg     = collectLatest(AbstractMessage, Message, skipindex(inputmsgs, i), prod_fn)
        connect!(outputmsgs[i], outputmsg)
    end

    properties.output_initialised = true

    return nothing
end

# Equality chain initialisation for variables with large number of connected nodes, somewhere > 5
# In this cases it is more efficient to create an equality chain structure, but it does allocate way more memory
function initialize_output_messages!(chain::EqualityChain, properties::RandomVariableProperties)
    d          = length(properties.input_messages)
    outputmsgs = properties.output_messages

    resize!(outputmsgs, d)

    @inbounds for i in 1:d
        outputmsgs[i] = MessageObservable(Message)
    end

    initialize!(chain, outputmsgs)
    properties.output_initialised = true

    return nothing
end

messagein(properties::RandomVariableProperties, index::Int) = randomvar.input_messages[index]

function messageout(properties::RandomVariableProperties, index::Int)
    if !properties.output_initialised
        initialize_output_messages!(properties)
    end
    return properties.output_messages[index]
end

get_pipeline_stages(properties::RandomVariableProperties) = properties.pipeline

_getmarginal(properties::RandomVariableProperties)              = properties.marginal
_setmarginal!(properties::RandomVariableProperties, observable) = connect!(_getmarginal(properties), observable)
_makemarginal(properties::RandomVariableProperties)             = collectLatest(AbstractMessage, Marginal, properties.input_messages, properties.marginal_prod_fn)

# Old stuff is below

mutable struct RandomVariable <: AbstractVariable
    name               :: Symbol
    anonymous          :: Bool
    collection_type    :: AbstractVariableCollectionType
    input_messages     :: Vector{MessageObservable{AbstractMessage}}
    output_messages    :: Vector{MessageObservable{Message}}
    output_initialised :: Bool
    output_cache       :: Union{Nothing, EqualityChain}
    marginal           :: MarginalObservable
    pipeline
    proxy_variables
    prod_constraint
    prod_strategy
    marginal_form_constraint
    marginal_form_check_strategy
    messages_form_constraint
    messages_form_check_strategy
end

Base.show(io::IO, randomvar::RandomVariable) = print(io, "RandomVariable(", indexed_name(randomvar), ")")

struct RandomVariableCreationOptions{L, P, C, S, T, G, M, N}
    pipeline                     :: L
    proxy_variables              :: P
    prod_constraint              :: C
    prod_strategy                :: S
    marginal_form_constraint     :: T
    marginal_form_check_strategy :: G
    messages_form_constraint     :: M
    messages_form_check_strategy :: N
end

prod_constraint(options::RandomVariableCreationOptions)              = options.prod_constraint
prod_strategy(options::RandomVariableCreationOptions)                = options.prod_strategy
marginal_form_constraint(options::RandomVariableCreationOptions)     = options.marginal_form_constraint
marginal_form_check_strategy(options::RandomVariableCreationOptions) = options.marginal_form_check_strategy
messages_form_constraint(options::RandomVariableCreationOptions)     = options.messages_form_constraint
messages_form_check_strategy(options::RandomVariableCreationOptions) = options.messages_form_check_strategy

function RandomVariableCreationOptions()
    # Return default settings
    return RandomVariableCreationOptions(
        EmptyPipelineStage(),             # pipeline
        nothing,                          # proxy_variables
        GenericProd(),                    # prod_constraint
        FoldLeftProdStrategy(),           # prod_strategy
        UnspecifiedFormConstraint(),      # marginal_form_constraint
        FormConstraintCheckPickDefault(), # marginal_form_check_strategy
        UnspecifiedFormConstraint(),      # messages_form_constraint
        FormConstraintCheckPickDefault()  # messages_form_check_strategy
    )
end

const EmptyRandomVariableCreationOptions = RandomVariableCreationOptions(nothing, nothing, nothing, nothing, nothing, nothing, nothing, nothing)

# Immutable setters return a new object, this API is considered to be private
randomvar_options_set_pipeline(pipeline)                                         = randomvar_options_set_pipeline(RandomVariableCreationOptions(), pipeline)
randomvar_options_set_proxy_variables(proxy_variables)                           = randomvar_options_set_proxy_variables(RandomVariableCreationOptions(), proxy_variables)
randomvar_options_set_prod_constraint(prod_constraint)                           = randomvar_options_set_prod_constraint(RandomVariableCreationOptions(), prod_constraint)
randomvar_options_set_prod_strategy(prod_strategy)                               = randomvar_options_set_prod_strategy(RandomVariableCreationOptions(), prod_strategy)
randomvar_options_set_marginal_form_constraint(marginal_form_constraint)         = randomvar_options_set_marginal_form_constraint(RandomVariableCreationOptions(), marginal_form_constraint)
randomvar_options_set_marginal_form_check_strategy(marginal_form_check_strategy) = randomvar_options_set_marginal_form_check_strategy(RandomVariableCreationOptions(), marginal_form_check_strategy)
randomvar_options_set_messages_form_constraint(messages_form_constraint)         = randomvar_options_set_messages_form_constraint(RandomVariableCreationOptions(), messages_form_constraint)
randomvar_options_set_messages_form_check_strategy(messages_form_check_strategy) = randomvar_options_set_messages_form_check_strategy(RandomVariableCreationOptions(), messages_form_check_strategy)

randomvar_options_set_pipeline(options::RandomVariableCreationOptions, pipeline)                                         = RandomVariableCreationOptions(pipeline, options.proxy_variables, options.prod_constraint, options.prod_strategy, options.marginal_form_constraint, options.marginal_form_check_strategy, options.messages_form_constraint, options.messages_form_check_strategy)
randomvar_options_set_proxy_variables(options::RandomVariableCreationOptions, proxy_variables)                           = RandomVariableCreationOptions(options.pipeline, proxy_variables, options.prod_constraint, options.prod_strategy, options.marginal_form_constraint, options.marginal_form_check_strategy, options.messages_form_constraint, options.messages_form_check_strategy)
randomvar_options_set_prod_constraint(options::RandomVariableCreationOptions, prod_constraint)                           = RandomVariableCreationOptions(options.pipeline, options.proxy_variables, prod_constraint, options.prod_strategy, options.marginal_form_constraint, options.marginal_form_check_strategy, options.messages_form_constraint, options.messages_form_check_strategy)
randomvar_options_set_prod_strategy(options::RandomVariableCreationOptions, prod_strategy)                               = RandomVariableCreationOptions(options.pipeline, options.proxy_variables, options.prod_constraint, prod_strategy, options.marginal_form_constraint, options.marginal_form_check_strategy, options.messages_form_constraint, options.messages_form_check_strategy)
randomvar_options_set_marginal_form_constraint(options::RandomVariableCreationOptions, marginal_form_constraint)         = RandomVariableCreationOptions(options.pipeline, options.proxy_variables, options.prod_constraint, options.prod_strategy, marginal_form_constraint, options.marginal_form_check_strategy, options.messages_form_constraint, options.messages_form_check_strategy)
randomvar_options_set_marginal_form_check_strategy(options::RandomVariableCreationOptions, marginal_form_check_strategy) = RandomVariableCreationOptions(options.pipeline, options.proxy_variables, options.prod_constraint, options.prod_strategy, options.marginal_form_constraint, marginal_form_check_strategy, options.messages_form_constraint, options.messages_form_check_strategy)
randomvar_options_set_messages_form_constraint(options::RandomVariableCreationOptions, messages_form_constraint)         = RandomVariableCreationOptions(options.pipeline, options.proxy_variables, options.prod_constraint, options.prod_strategy, options.marginal_form_constraint, options.marginal_form_check_strategy, messages_form_constraint, options.messages_form_check_strategy)
randomvar_options_set_messages_form_check_strategy(options::RandomVariableCreationOptions, messages_form_check_strategy) = RandomVariableCreationOptions(options.pipeline, options.proxy_variables, options.prod_constraint, options.prod_strategy, options.marginal_form_constraint, options.marginal_form_check_strategy, options.messages_form_constraint, messages_form_check_strategy)

"""
    randomvar()

By default `randomvar()` creates a single random variable in the model and returns it. It is also possible to pass dimensionality arguments to `randomvar()` function in the same way as for the `datavar()` function.

Note: `randomvar()` function is supposed to be used only within the `@model` macro.

## Example

```julia
@model function model_name(...)
    ...
    x = randomvar() # Returns a single random variable which can be used later in the model
    x = randomvar(n) # Returns an vector of random variables with length `n`
    x = randomvar(n, m) # Returns a matrix of random variables with size `(n, m)`
    x = randomvar((n, m)) # It is also possible to use a tuple for dimensionality
    ...
end
```

`randomvar()` call within `@model` macro supports `where { options... }` block for extra options specification, e.g:

```julia
@model function model_name(...)
    ...
    y = randomvar() where { prod_constraint = ProdGeneric() }
    ...
end
```

### Random variables available options

- `prod_constraint`
- `prod_strategy`
- `marginal_form_constraint`
- `marginal_form_check_strategy`
- `messages_form_constraint`
- `messages_form_check_strategy`
- `pipeline`

"""
function randomvar end

randomvar(name::Symbol)                                                  = randomvar(RandomVariableCreationOptions(), name, VariableIndividual())
randomvar(name::Symbol, collection_type::AbstractVariableCollectionType) = randomvar(RandomVariableCreationOptions(), name, collection_type)
randomvar(name::Symbol, length::Int)                                     = randomvar(RandomVariableCreationOptions(), name, length)
randomvar(name::Symbol, dims::Tuple)                                     = randomvar(RandomVariableCreationOptions(), name, dims)
randomvar(name::Symbol, dims::Vararg{Int})                               = randomvar(RandomVariableCreationOptions(), name, dims)

randomvar(options::RandomVariableCreationOptions, name::Symbol)                    = randomvar(options, name, VariableIndividual())
randomvar(options::RandomVariableCreationOptions, name::Symbol, dims::Vararg{Int}) = randomvar(options, name, dims)

function randomvar(options::RandomVariableCreationOptions, name::Symbol, collection_type::AbstractVariableCollectionType)
    return RandomVariable(
        name,
        false,
        collection_type,
        Vector{MessageObservable{AbstractMessage}}(),
        Vector{MessageObservable{Message}}(),
        false,
        nothing,
        MarginalObservable(),
        something(options.pipeline, EmptyPipelineStage()),      # `something(args..)` returns the first `notnothing` object
        options.proxy_variables,                                # here we do allow `nothing`, so no need for `something(...)`
        something(options.prod_constraint, GenericProd()),
        something(options.prod_strategy, FoldLeftProdStrategy()),
        something(options.marginal_form_constraint, UnspecifiedFormConstraint()),
        something(options.marginal_form_check_strategy, FormConstraintCheckPickDefault()),
        something(options.messages_form_constraint, UnspecifiedFormConstraint()),
        something(options.messages_form_check_strategy, FormConstraintCheckPickDefault())
    )
end

function randomvar(options::RandomVariableCreationOptions, name::Symbol, length::Int)
    return map(i -> randomvar(options, name, VariableVector(i)), 1:length)
end

function randomvar(options::RandomVariableCreationOptions, name::Symbol, dims::Tuple)
    indices = CartesianIndices(dims)
    size = axes(indices)
    return map(i -> randomvar(options, name, VariableArray(size, i)), indices)
end

degree(randomvar::RandomVariable)          = length(randomvar.input_messages)
name(randomvar::RandomVariable)            = randomvar.name
isanonymous(randomvar::RandomVariable)     = randomvar.anonymous
proxy_variables(randomvar::RandomVariable) = randomvar.proxy_variables
collection_type(randomvar::RandomVariable) = randomvar.collection_type
equality_chain(randomvar::RandomVariable)  = randomvar.equality_chain
prod_constraint(randomvar::RandomVariable) = randomvar.prod_constraint
prod_strategy(randomvar::RandomVariable)   = randomvar.prod_strategy

marginal_form_constraint(randomvar::RandomVariable)     = randomvar.marginal_form_constraint
marginal_form_check_strategy(randomvar::RandomVariable) = _marginal_form_check_strategy(randomvar.marginal_form_check_strategy, randomvar)

_marginal_form_check_strategy(::FormConstraintCheckPickDefault, randomvar::RandomVariable) = default_form_check_strategy(marginal_form_constraint(randomvar))
_marginal_form_check_strategy(form_check_strategy, randomvar::RandomVariable)              = form_check_strategy

messages_form_constraint(randomvar::RandomVariable)     = randomvar.messages_form_constraint
messages_form_check_strategy(randomvar::RandomVariable) = _messages_form_check_strategy(randomvar.messages_form_check_strategy, randomvar)

_messages_form_check_strategy(::FormConstraintCheckPickDefault, randomvar::RandomVariable) = default_form_check_strategy(messages_form_constraint(randomvar))
_messages_form_check_strategy(form_check_strategy, randomvar::RandomVariable)              = form_check_strategy

isproxy(randomvar::RandomVariable) = proxy_variables(randomvar) !== nothing

israndom(::RandomVariable)                  = true
israndom(::AbstractArray{<:RandomVariable}) = true
isdata(::RandomVariable)                    = false
isdata(::AbstractArray{<:RandomVariable})   = false
isconst(::RandomVariable)                   = false
isconst(::AbstractArray{<:RandomVariable})  = false

function Base.getindex(randomvar::RandomVariable, i...)
    error("Variable $(indexed_name(randomvar)) has been indexed with `[$(join(i, ','))]`. Direct indexing of `random` variables is not allowed.")
end

messages_prod_fn(randomvar::RandomVariable) =
    messages_prod_fn(prod_strategy(randomvar), prod_constraint(randomvar), messages_form_constraint(randomvar), messages_form_check_strategy(randomvar))
marginal_prod_fn(randomvar::RandomVariable) =
    marginal_prod_fn(prod_strategy(randomvar), prod_constraint(randomvar), marginal_form_constraint(randomvar), marginal_form_check_strategy(randomvar))

getlastindex(randomvar::RandomVariable) = degree(randomvar) + 1

setanonymous!(randomvar::RandomVariable, anonymous::Bool) = randomvar.anonymous = anonymous
