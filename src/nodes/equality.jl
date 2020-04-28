export EqualityIOONode

using Rocket

equalityMessage(l, r) = combineLatest((l, r), true, (AbstractMessage, multiply))

struct EqualityIOONode <: AbstractDeterministicNode
    name :: String
    in1  :: Interface
    out1 :: Interface
    out2 :: Interface

    EqualityIOONode(name::String) = begin
        in1  = Interface("[$name]: in1")
        out1 = Interface("[$name]: out1")
        out2 = Interface("[$name]: out2")

        define_sum_product_message!(in1,  equalityMessage(partner_message(out1), partner_message(out2)) |> share(mode = SYNCHRONOUS_SUBJECT_MODE))
        # define_sum_product_message!(in1,  equalityMessage(partner_message(out1), partner_message(out2)))

        define_sum_product_message!(out1, equalityMessage(partner_message(in1), partner_message(out2)))

        define_sum_product_message!(out2, equalityMessage(partner_message(out1), partner_message(in1)))

        return new(name, in1, out1, out2)
    end
end
