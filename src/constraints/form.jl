export AbstractFormConstraint
export FormConstraintCheckEach, FormConstraintCheckLast, FormConstraintCheckPickDefault
export constrain_form, default_prod_constraint, default_form_check_strategy
export UnspecifiedFormConstraint, CompositeFormConstraint

using TupleTools

import BayesBase: resolve_prod_strategy
import Base: +

# Form constraints are preserved during execution of the `prod` function
# There are two major strategies to check current functional form
# We may check and preserve functional form of the result of the `prod` function
# after each subsequent `prod` 
# or we may want to wait after all `prod` functions in the equality chain have been executed 

"""
    AbstractFormConstraint

Every functional form constraint is a subtype of `AbstractFormConstraint` abstract type.

Note: this is not strictly necessary, but it makes automatic dispatch easier and compatible with the `CompositeFormConstraint`.
"""
abstract type AbstractFormConstraint end

"""
    FormConstraintCheckEach

This form constraint check strategy checks functional form of the messages product after each product in an equality chain. 
Usually if a variable has been connected to multiple nodes we want to perform multiple `prod` to obtain a posterior marginal.
With this form check strategy `constrain_form` function will be executed after each subsequent `prod` function.
"""
struct FormConstraintCheckEach end

"""
    FormConstraintCheckEach

This form constraint check strategy checks functional form of the last messages product in the equality chain. 
Usually if a variable has been connected to multiple nodes we want to perform multiple `prod` to obtain a posterior marginal.
With this form check strategy `constrain_form` function will be executed only once after all subsequenct `prod` functions have been executed.
"""
struct FormConstraintCheckLast end

"""
    FormConstraintCheckPickDefault

This form constraint check strategy simply fallbacks to a default check strategy for a given form constraint. 
"""
struct FormConstraintCheckPickDefault end

"""
    default_form_check_strategy(form_constraint)

Returns a default check strategy (e.g. `FormConstraintCheckEach` or `FormConstraintCheckEach`) for a given form constraint object.
"""
function default_form_check_strategy end

"""
    default_prod_constraint(form_constraint)

Returns a default prod constraint needed to apply a given `form_constraint`. For most form constraints this function returns `ProdGeneric`.
"""
function default_prod_constraint end

"""
    constrain_form(form_constraint, distribution)

This function must approximate `distribution` object in a form that satisfies `form_constraint`.
"""
function constrain_form end

"""
    UnspecifiedFormConstraint

One of the form constraint objects. Does not imply any form constraints and simply returns the same object as receives.
However it does not allow `DistProduct` to be a valid functional form in the inference backend.
"""
struct UnspecifiedFormConstraint <: AbstractFormConstraint end

default_form_check_strategy(::UnspecifiedFormConstraint) = FormConstraintCheckLast()

default_prod_constraint(::UnspecifiedFormConstraint) = GenericProd()

constrain_form(::UnspecifiedFormConstraint, something) = something
constrain_form(::UnspecifiedFormConstraint, something::Union{ProductOf, LinearizedProductOf}) =
    error("`ProductOf` object cannot be used as a functional form in inference backend. Use form constraints to restrict the functional form of marginal posteriors.")

"""
    CompositeFormConstraint

Creates a composite form constraint that applies form constraints in order. The composed form constraints must be compatible and have the exact same `form_check_strategy`. 
"""
struct CompositeFormConstraint{C} <: AbstractFormConstraint
    constraints::C
end

Base.show(io::IO, constraint::CompositeFormConstraint) = join(io, constraint.constraints, " :: ")

function constrain_form(composite::CompositeFormConstraint, something)
    return reduce((form, constraint) -> constrain_form(constraint, form), composite.constraints; init = something)
end

function default_prod_constraint(constraint::CompositeFormConstraint)
    return mapfoldl(default_prod_constraint, resolve_prod_strategy, constraint.constraints)
end

function default_form_check_strategy(composite::CompositeFormConstraint)
    strategies = map(default_form_check_strategy, composite.constraints)
    if !(all(e -> e === first(strategies), TupleTools.tail(strategies)))
        error("Different default form check strategy for composite form constraints found. Use `form_check_strategy` options to specify check strategy.")
    end
    return first(strategies)
end

Base.:+(constraint::AbstractFormConstraint) = constraint

Base.:+(left::AbstractFormConstraint, right::AbstractFormConstraint)   = CompositeFormConstraint((left, right))
Base.:+(left::AbstractFormConstraint, right::CompositeFormConstraint)  = CompositeFormConstraint((left, right.constraints...))
Base.:+(left::CompositeFormConstraint, right::AbstractFormConstraint)  = CompositeFormConstraint((left.constraints..., right))
Base.:+(left::CompositeFormConstraint, right::CompositeFormConstraint) = CompositeFormConstraint((left.constraints..., right.constraints...))
