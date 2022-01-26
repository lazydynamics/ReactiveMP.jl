
import Base: merge!, show, ==, *, first, last, hash

abstract type FactorisationSpecEntryIndex end

struct FactorisationSpecEntryExact <: FactorisationSpecEntryIndex end
struct FactorisationSpecEntryIndexed <: FactorisationSpecEntryIndex end
struct FactorisationSpecEntryRanged <: FactorisationSpecEntryIndex end
struct FactorisationSpecEntrySplitRanged <: FactorisationSpecEntryIndex end

struct SplittedRange{ R <: AbstractRange }
    range :: R
end

Base.first(range::SplittedRange) = first(range.range)
Base.last(range::SplittedRange)  = last(range.range)

struct FactorisationSpecEntry{I}
    symbol :: Symbol
    index  :: I
end

name(entry::FactorisationSpecEntry) = entry.symbol

Base.show(io::IO, entry::FactorisationSpecEntry) = show(io, indextype(entry), entry)

Base.show(io, ::FactorisationSpecEntryExact, entry::FactorisationSpecEntry) = print(io, entry.symbol)
Base.show(io, ::FactorisationSpecEntryIndexed, entry::FactorisationSpecEntry) = print(io, entry.symbol, "[", entry.index, "]")
Base.show(io, ::FactorisationSpecEntryRanged, entry::FactorisationSpecEntry) = print(io, entry.symbol, "[", entry.index, "]")
Base.show(io, ::FactorisationSpecEntrySplitRanged, entry::FactorisationSpecEntry) = print(io, entry.symbol, "[", first(entry.index), "]..", entry.symbol, "[", last(entry.index), "]")

function Base.:(==)(left::FactorisationSpecEntry, right::FactorisationSpecEntry)
    return left.symbol == right.symbol && left.index == right.index
end

indextype(spec::FactorisationSpecEntry) = indextype(spec, spec.index)

indextype(::FactorisationSpecEntry, index::Nothing)       = FactorisationSpecEntryExact()
indextype(::FactorisationSpecEntry, index::Integer)       = FactorisationSpecEntryIndexed()
indextype(::FactorisationSpecEntry, index::AbstractRange) = FactorisationSpecEntryRanged()
indextype(::FactorisationSpecEntry, index::SplittedRange) = FactorisationSpecEntrySplitRanged()

Base.merge!(left::NTuple{N, FactorisationSpecEntry}, right::FactorisationSpecEntry) where N = TupleTools.setindex(left, merge!(left[end], right), lastindex(left))
Base.merge!(left::FactorisationSpecEntry, right::NTuple{N, FactorisationSpecEntry}) where N = TupleTools.setindex(right, merge!(left, right[begin]), firstindex(right))

function Base.merge!(left::NTuple{N1, FactorisationSpecEntry}, right::NTuple{N2, FactorisationSpecEntry}) where { N1, N2 }
    return TupleTools.insertat(left, lastindex(left), (merge!(left[end], right[begin]), right[begin + 1:end]...))
end

function Base.merge!(left::FactorisationSpecEntry, right::FactorisationSpecEntry)
    if left.symbol !== right.symbol
        error("Cannot merge factorisation specification entries with different names $(left) and $(right)")
    end
    return merge!(indextype(left), indextype(right), left, right) 
end

function Base.merge!(::FactorisationSpecEntryIndex, ::FactorisationSpecEntryIndex, left::FactorisationSpecEntry, right::FactorisationSpecEntry)
    error("Cannot merge factorisation specification entries $(left) and $(right)")
end

function Base.merge!(::FactorisationSpecEntryExact, ::FactorisationSpecEntryExact, left::FactorisationSpecEntry, right::FactorisationSpecEntry)
    return left
end

function Base.merge!(::FactorisationSpecEntryIndexed, ::FactorisationSpecEntryIndexed, left::FactorisationSpecEntry, right::FactorisationSpecEntry)
    @assert right.index > left.index "Cannot merge factorisation specification entries $(left) and $(right). Right index should be greater than left index."
    return FactorisationSpecEntry(left.symbol, SplittedRange(left.index:right.index))
end

function Base.merge!(::FactorisationSpecEntrySplitRanged, ::FactorisationSpecEntryIndexed, left::FactorisationSpecEntry, right::FactorisationSpecEntry)
    @assert right.index > last(left.index) "Cannot merge factorisation specification entries $(left) and $(right). Right index should be greater than left index."
    return FactorisationSpecEntry(left.symbol, SplittedRange(first(left.index):right.index))
end

function Base.merge!(::FactorisationSpecEntryIndexed, ::FactorisationSpecEntrySplitRanged, left::FactorisationSpecEntry, right::FactorisationSpecEntry)
    @assert first(right.index) > left.index "Cannot merge factorisation specification entries $(left) and $(right). Right index should be greater than left index."
    return FactorisationSpecEntry(left.symbol, SplittedRange(left.index:last(right.index)))
end

function Base.merge!(::FactorisationSpecEntrySplitRanged, ::FactorisationSpecEntrySplitRanged, left::FactorisationSpecEntry, right::FactorisationSpecEntry)
    @assert first(right.index) > last(left.index) "Cannot merge factorisation specification entries $(left) and $(right). Right index should be greater than left index."
    return FactorisationSpecEntry(left.symbol, SplittedRange(first(left.index):last(right.index)))
end

# 

struct FactorisationSpec{E}
    entries :: E
end

function Base.show(io::IO, spec::FactorisationSpec) 
    print(io, "q(")
    join(io, spec.entries, ", ")
    print(io, ")")
end

# Base.:(==)(left::FactorisationSpec, right::FactorisationSpec) = all(d -> d[1] == d[2], zip(left.entries, right.entries))

Base.hash(spec::FactorisationSpec, h::UInt) = foldr(hash, spec.entries, init = h)

function Base.merge!(left::FactorisationSpec, right::FactorisationSpec)
    if length(left.entries) == length(right.entries)
        if TupleTools.prod(tuple(Iterators.map((l, r) -> name(l) === name(r), left.entries, right.entries)...))
            return FactorisationSpec(tuple(Iterators.map((l, r) -> merge!(l, r), left.entries, right.entries)...))
        end
    end
    error("Cannot merge factorisation specifications $(left) and $(right)")
end

# Mul 

Base.:(*)(left::FactorisationSpec, right::FactorisationSpec)                    = (left, right)
Base.:(*)(left::NTuple{N, FactorisationSpec}, right::FactorisationSpec) where N = (left..., right)
Base.:(*)(left::FactorisationSpec, right::NTuple{N, FactorisationSpec}) where N = (left, right...)
Base.:(*)(left::NTuple{N1, FactorisationSpec}, right::NTuple{N2, FactorisationSpec}) where { N1, N2 } = (left..., right...)

# `Node` here refers to a node in a tree, it has nothing to do with factor nodes
struct FactorisationSpecNode{K <: FactorisationSpec, N, S}
    key        :: K
    childnodes :: N
    childspec  :: S

    function FactorisationSpecNode(key::K, childnodes::N, childspec::S) where { K <: FactorisationSpec, C1, N <: NTuple{C1, FactorisationSpecNode}, C2, S <: NTuple{C2, FactorisationSpec} }
        return new{K, N, S}(key, childnodes, childspec)
    end
end

function Base.show(io::IO, node::FactorisationSpecNode) 
    print(io, node.key, " -> (childnodes: [")
    join(io, node.childnodes, ", ")
    print(io, "], childspec: [")
    join(io, node.childspec, ", ")
    print(io, "])")
end

## ## 