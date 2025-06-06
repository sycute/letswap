module coin_share::rmb ;
use std::option;
use sui::coin;
use sui::transfer;
use sui::tx_context::{TxContext};

public struct RMB has drop {}

fun init(witness: RMB, ctx: &mut TxContext) {
    let (treasury, metadata) =
        coin::create_currency(witness, 6, b"RMB", b"", b"", option::none(), ctx);
    transfer::public_freeze_object(metadata);

    /// 所有人都能访问
    transfer::public_share_object(treasury);
}
