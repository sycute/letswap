module suiclmm::position;

use integer_mate::i32::{Self, I32};
use move_stl::linked_table;
use std::type_name::{Self, TypeName};
use suiclmm::tick_math;

// === Errors ===
const EPOSITION_TICK_RANGE: u64 = 5;
const EPOSITION_NOT_EXISTS: u64 = 6;

// === Structs ===
public struct PositionManager has store {
    tick_spacing: u32,
    // position_index: u64,
    positions: linked_table::LinkedTable<ID, PositionInfo>,
}

public struct Position has key, store {
    id: UID,
    pool: ID,
    coin_type_a: TypeName,
    coin_type_b: TypeName,
    tick_lower_index: I32,
    tick_upper_index: I32,
    liquidity: u128,
}

public struct PositionInfo has copy, drop, store {
    position_id: ID,
    liquidity: u128,
    tick_lower_index: I32,
    tick_upper_index: I32,
}

// === Public Functions ===
public fun tick_range(position_nft: &Position): (I32, I32) {
    (position_nft.tick_lower_index, position_nft.tick_upper_index)
}

public fun check_position_tick_range(tick_lower: I32, tick_upper: I32, tick_spacing: u32) {
    let v0 = i32::gt(tick_upper, tick_lower);
    let v1 = i32::lte(tick_upper, tick_math::max_tick());
    let v2 = i32::gte(tick_lower, tick_math::min_tick());
    let v3 = i32::mod(tick_lower, i32::from_u32(tick_spacing)) == i32::zero();
    let v4 = i32::mod(tick_upper, i32::from_u32(tick_spacing)) == i32::zero();

    assert!(v0 && v1 && v2 && v3 && v4, EPOSITION_TICK_RANGE)
}

// === Package Functions ===
public(package) fun new(tick_spacing: u32, ctx: &mut tx_context::TxContext): PositionManager {
    PositionManager {
        tick_spacing,
        positions: linked_table::new(ctx),
    }
}

public(package) fun open_position<CoinTypeA, CoinTypeB>(
    position_manager: &mut PositionManager,
    pool_id: ID,
    tick_lower_index: I32,
    tick_upper_index: I32,
    ctx: &mut TxContext,
): Position {
    check_position_tick_range(tick_lower_index, tick_upper_index, position_manager.tick_spacing);

    let position = Position {
        id: object::new(ctx),
        pool: pool_id,
        coin_type_a: type_name::get<CoinTypeA>(),
        coin_type_b: type_name::get<CoinTypeB>(),
        tick_lower_index,
        tick_upper_index,
        liquidity: 0,
    };

    let position_id = object::id(&position);

    let info = PositionInfo {
        position_id: position_id,
        liquidity: 0,
        tick_lower_index,
        tick_upper_index,
    };
    position_manager.positions.push_back(position_id, info);

    position
}

public(package) fun add_liquidity(
    manager: &mut PositionManager,
    position_nft: &mut Position,
    liquidity: u128,
) {
    assert!(
        linked_table::contains(&manager.positions, object::id(position_nft)),
        EPOSITION_NOT_EXISTS,
    );
    let position_info = linked_table::borrow_mut<ID, PositionInfo>(
        &mut manager.positions,
        object::id(position_nft),
    );

    position_info.liquidity = position_info.liquidity + liquidity;
    position_nft.liquidity = position_info.liquidity;
}
