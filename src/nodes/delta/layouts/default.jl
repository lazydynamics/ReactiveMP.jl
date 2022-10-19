
"""
    DeltaFnDefaultRuleLayout

Default rule layout for the Delta node:

# Layout 

In order to compute:

- `q_out`: mirrors the posterior marginal on the `out` edge
- `q_ins`: uses inbound message on the `out` edge and all inbound messages on the `ins` edges
- `m_out`: uses all inbound messages on the `ins` edges
- `m_in_k`: uses the inbound message on the `in_k` edge and `q_ins`

See also: [`ReactiveMP.DeltaFnDefaultKnownInverseRuleLayout`](@ref)
"""
struct DeltaFnDefaultRuleLayout end

# This function declares how to compute `q_out` locally around `DeltaFn`
function deltafn_apply_layout(::DeltaFnDefaultRuleLayout, ::Val{:q_out}, model, factornode::DeltaFnNode)
    let out = factornode.out, localmarginal = factornode.localmarginals.marginals[1]
        # We simply subscribe on the marginal of the connected variable on `out` edge
        setstream!(localmarginal, getmarginal(connectedvar(out), IncludeAll()))
    end
end

# This function declares how to compute `q_ins` locally around `DeltaFn`
function deltafn_apply_layout(::DeltaFnDefaultRuleLayout, ::Val{:q_ins}, model, factornode::DeltaFnNode)
    let out = factornode.out, ins = factornode.ins, localmarginal = factornode.localmarginals.marginals[2]
        cmarginal = MarginalObservable()
        setstream!(localmarginal, cmarginal)

        # By default to compute `q_ins` we need messages both from `:out` and `:ins`
        msgs_names      = Val{(:out, :ins)}
        msgs_observable = combineLatestUpdates((messagein(out), combineLatestMessagesInUpdates(ins)), PushNew())

        # By default, we should not need any local marginals
        marginal_names       = nothing
        marginals_observable = of(nothing)

        fform = functionalform(factornode)
        vtag  = Val{:ins}
        meta  = metadata(factornode)

        mapping     = MarginalMapping(fform, vtag, msgs_names, marginal_names, meta, factornode)
        marginalout = combineLatest((msgs_observable, marginals_observable), PushNew()) |> discontinue() |> map(Marginal, mapping)

        connect!(cmarginal, marginalout) # MarginalObservable has RecentSubject by default, there is no need to share_recent() here
    end
end

# This function declares how to compute `m_out` 
function deltafn_apply_layout(::DeltaFnDefaultRuleLayout, ::Val{:m_out}, model, factornode::DeltaFnNode)
    let out = factornode.out, ins = factornode.ins
        # By default we simply request all inbound messages from `ins` edges
        msgs_names      = Val{(:ins,)}
        msgs_observable = combineLatestUpdates((combineLatestMessagesInUpdates(ins),), PushNew())

        # By default we don't need any marginals
        marginal_names       = nothing
        marginals_observable = of(nothing)

        fform       = functionalform(factornode)
        vtag        = tag(out)
        vconstraint = local_constraint(out)
        meta        = metadata(factornode)

        vmessageout = combineLatest((msgs_observable, marginals_observable), PushNew())

        mapping = let messagemap = MessageMapping(fform, vtag, vconstraint, msgs_names, marginal_names, meta, factornode)
            (dependencies) -> VariationalMessage(dependencies[1], dependencies[2], messagemap)
        end

        vmessageout = vmessageout |> map(AbstractMessage, mapping)
        vmessageout = apply_pipeline_stage(get_pipeline_stages(getoptions(model)), factornode, vtag, vmessageout)
        vmessageout = vmessageout |> schedule_on(global_reactive_scheduler(getoptions(model)))

        connect!(messageout(out), vmessageout)
    end
end

# This function declares how to compute `m_in` for each `k` 
function deltafn_apply_layout(::DeltaFnDefaultRuleLayout, ::Val{:m_in}, model, factornode::DeltaFnNode)
    # For each outbound message from `in_k` edge we need an inbound message on this edge and a joint marginal over `:ins` edges
    foreach(factornode.ins) do interface
        msgs_names      = Val{(:in,)}
        msgs_observable = combineLatestUpdates((messagein(interface),), PushNew())

        marginal_names       = Val{(:ins,)}
        marginals_observable = combineLatestUpdates((getstream(factornode.localmarginals.marginals[2]),), PushNew())

        fform       = functionalform(factornode)
        vtag        = tag(interface)
        vconstraint = local_constraint(interface)
        meta        = metadata(factornode)

        vmessageout = combineLatest((msgs_observable, marginals_observable), PushNew())

        mapping = let messagemap = MessageMapping(fform, vtag, vconstraint, msgs_names, marginal_names, meta, factornode)
            (dependencies) -> VariationalMessage(dependencies[1], dependencies[2], messagemap)
        end

        vmessageout = vmessageout |> map(AbstractMessage, mapping)
        vmessageout = apply_pipeline_stage(get_pipeline_stages(getoptions(model)), factornode, vtag, vmessageout)
        vmessageout = vmessageout |> schedule_on(global_reactive_scheduler(getoptions(model)))

        connect!(messageout(interface), vmessageout)
    end
end

"""
    DeltaFnDefaultKnownInverseRuleLayout

Default rule layout for the Delta node:

# Layout 

In order to compute:

- `q_out`: mirrors the posterior marginal on the `out` edge (same as the `DeltaFnDefaultRuleLayout`)
- `q_ins`: uses inbound message on the `out` edge and all inbound messages on the `ins` edges (same as the `DeltaFnDefaultRuleLayout`)
- `m_out`: uses all inbound messages on the `ins` edges (same as the `DeltaFnDefaultRuleLayout`)
- `m_in_k`: uses inbound message on the `out` edge and inbound messages on the `ins` edges except `k`

See also: [`ReactiveMP.DeltaFnDefaultRuleLayout`](@ref)
"""
struct DeltaFnDefaultKnownInverseRuleLayout end

function deltafn_apply_layout(::DeltaFnDefaultKnownInverseRuleLayout, ::Val{:q_out}, model, factornode::DeltaFnNode)
    return deltafn_apply_layout(DeltaFnDefaultRuleLayout(), Val(:q_out), model, factornode)
end

function deltafn_apply_layout(::DeltaFnDefaultKnownInverseRuleLayout, ::Val{:q_ins}, model, factornode::DeltaFnNode)
    return deltafn_apply_layout(DeltaFnDefaultRuleLayout(), Val(:q_ins), model, factornode)
end

function deltafn_apply_layout(::DeltaFnDefaultKnownInverseRuleLayout, ::Val{:m_out}, model, factornode::DeltaFnNode)
    return deltafn_apply_layout(DeltaFnDefaultRuleLayout(), Val(:m_out), model, factornode)
end

# This function declares how to compute `m_in` 
function deltafn_apply_layout(::DeltaFnDefaultKnownInverseRuleLayout, ::Val{:m_in}, model, factornode::DeltaFnNode{F, N}) where {F, N}
    # For each outbound message from `in_k` edge we need an inbound messages from all OTHER! `in_*` edges and inbound message on `m_out`
    foreach(enumerate(factornode.ins)) do (index, interface)

        # If we have only one `interface` we replace it with nothing
        # In other cases we remove the current index from the list of interfaces
        msgs_ins_stream = if N === 1 # `N` should be known at compile-time here so this `if` branch must be compiled out
            of(Message(nothing, true, true))
        else
            combineLatestMessagesInUpdates(TupleTools.deleteat(factornode.ins, index))
        end

        msgs_names      = Val{(:out, :ins)}
        msgs_observable = combineLatestUpdates((messagein(factornode.out), msgs_ins_stream), PushNew())

        marginal_names       = nothing
        marginals_observable = of(nothing)

        fform       = functionalform(factornode)
        vtag        = tag(interface)
        vconstraint = local_constraint(interface)
        meta        = metadata(factornode)

        vmessageout = combineLatest((msgs_observable, marginals_observable), PushNew())

        mapping = let messagemap = MessageMapping(fform, vtag, vconstraint, msgs_names, marginal_names, meta, factornode)
            (dependencies) -> VariationalMessage(dependencies[1], dependencies[2], messagemap)
        end

        vmessageout = vmessageout |> map(AbstractMessage, mapping)
        vmessageout = apply_pipeline_stage(get_pipeline_stages(getoptions(model)), factornode, vtag, vmessageout)
        vmessageout = vmessageout |> schedule_on(global_reactive_scheduler(getoptions(model)))

        connect!(messageout(interface), vmessageout)
    end
end
