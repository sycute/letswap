module suiclmm::tick;

use integer_mate::i128;
use integer_mate::i32;
use integer_mate::math_u128;
use move_stl::option_u64;
use move_stl::skip_list;
use suiclmm::tick_math;

// === Errors ===
const ELIQUIDITY_OVERFLOW: u64 = 0;
const ELIQUIDITY_GROSS_UNDERFLOW: u64 = 1;
const ETICK_INDEX_OUTBOUND: u64 = 2;
const ETICK_UNEXISTS: u64 = 3;

// === Structs ===
public struct Tick has store {
    index: i32::I32,
    sqrt_price: u128,
    liquidity_net: i128::I128,
    liquidity_gross: u128, // 判断是否还有流动性可用
}

public struct TickManager has store {
    tick_spacing: u32,
    ticks: skip_list::SkipList<Tick>,
}

// === Public Functions ===
public fun tick_score(tick_index: i32::I32): u64 {
    let score = i32::as_u32(i32::add(tick_index, i32::from_u32(tick_math::tick_bound())));

    assert!(score >= 0 && score <= tick_math::tick_bound() * 2, ETICK_INDEX_OUTBOUND);

    score as u64
}
public  fun index(tick: &Tick): i32::I32 {
    tick.index
}

public fun sqrt_price(tick: &Tick):u128 {
    tick.sqrt_price
}

public fun liquidity_net(tick: &Tick): i128::I128 {
    tick.liquidity_net
}

public fun liquidity_gross(tick: &Tick):u128 {
    tick.liquidity_gross
}

// === Package Functions ===
public(package) fun new(tick_spacing: u32, seed: u64, ctx: &mut TxContext): TickManager {
    TickManager {
        tick_spacing,
        ticks: skip_list::new(16, 2, seed, ctx),
    }
}

public(package) fun add_liquidity(
    tick_manager: &mut TickManager,
    tick_lower_index: i32::I32,
    tick_upper_index: i32::I32,
    liquidity: u128,
) {
    let tick_lower_score = tick_score(tick_lower_index);
    let tick_upper_score = tick_score(tick_upper_index);

    if (!skip_list::contains(&tick_manager.ticks, tick_lower_score)) {
        skip_list::insert(&mut tick_manager.ticks, tick_lower_score, default(tick_lower_index))
    };
    if (!skip_list::contains(&tick_manager.ticks, tick_upper_score)) {
        skip_list::insert(&mut tick_manager.ticks, tick_upper_score, default(tick_upper_index))
    };

    // update lower tick
    let lower_tick = skip_list::borrow_mut(&mut tick_manager.ticks, tick_lower_score);

    assert!(math_u128::add_check(lower_tick.liquidity_gross, liquidity), ELIQUIDITY_OVERFLOW);

    let (new_liquidity_net, overflow) = i128::overflowing_add(
        lower_tick.liquidity_net,
        i128::from(liquidity),
    );
    if (overflow) {
        abort ELIQUIDITY_OVERFLOW
    };

    lower_tick.liquidity_gross = lower_tick.liquidity_gross + liquidity;
    lower_tick.liquidity_net = new_liquidity_net;

    // update upper tick
    let upper_tick = skip_list::borrow_mut(&mut tick_manager.ticks, tick_upper_score);

    assert!(math_u128::add_check(upper_tick.liquidity_gross, liquidity), ELIQUIDITY_OVERFLOW);
    upper_tick.liquidity_gross = upper_tick.liquidity_gross + liquidity;

    let (new_liquidity_net, overflow) = i128::overflowing_sub(
        upper_tick.liquidity_net,
        i128::from(liquidity),
    );
    if (overflow) {
        abort ELIQUIDITY_OVERFLOW
    };
    upper_tick.liquidity_net = new_liquidity_net;
}

public(package) fun remove_liquidity(
    tick_manager: &mut TickManager,
    tick_lower_index: i32::I32,
    tick_upper_index: i32::I32,
    liquidity: u128,
) {
    let tick_lower_score = tick_score(tick_lower_index);
    let tick_upper_score = tick_score(tick_upper_index);
    assert!(skip_list::contains(&tick_manager.ticks, tick_lower_score), ETICK_UNEXISTS);
    assert!(skip_list::contains(&tick_manager.ticks, tick_upper_score), ETICK_UNEXISTS);

    let lower_tick = skip_list::borrow_mut(&mut tick_manager.ticks, tick_lower_score);

    assert!(lower_tick.liquidity_gross >= liquidity, ELIQUIDITY_GROSS_UNDERFLOW);
    lower_tick.liquidity_gross = lower_tick.liquidity_gross - liquidity;

    let (new_liquidity_net, overflow) = i128::overflowing_sub(
        lower_tick.liquidity_net,
        i128::from(liquidity),
    );
    if (overflow) {
        abort ELIQUIDITY_OVERFLOW
    };
    lower_tick.liquidity_net = new_liquidity_net;

    // update upper tick
    let upper_tick = skip_list::borrow_mut(&mut tick_manager.ticks, tick_upper_score);

    assert!(upper_tick.liquidity_gross >= liquidity, ELIQUIDITY_GROSS_UNDERFLOW);
    upper_tick.liquidity_gross = upper_tick.liquidity_gross - liquidity;

    let (new_liquidity_net, overflow) = i128::overflowing_add(
        upper_tick.liquidity_net,
        i128::from(liquidity),
    );
    if (overflow) {
        abort ELIQUIDITY_OVERFLOW
    };

    upper_tick.liquidity_net = new_liquidity_net;
}

public(package) fun cross_by_swap(tick_manager: &mut TickManager, tick_index: i32::I32, a2b: bool, liquidity: u128) : u128 {
    let tick = skip_list::borrow_mut<Tick>(&mut tick_manager.ticks, tick_score(tick_index));
    let liquidity_net = if (a2b) {
        i128::neg(tick.liquidity_net)
    } else {
        tick.liquidity_net
    };
    let liquidity = if (!i128::is_neg(liquidity_net)) {
        let v = i128::abs_u128(liquidity_net);
        assert!(math_u128::add_check(v, liquidity), 1);
        liquidity + v
    } else {
        let v = i128::abs_u128(liquidity_net);
        assert!(liquidity >= v, 1);
        liquidity - v
    };

    liquidity
}

public(package) fun first_score_for_swap(tick_manager: &TickManager, current_tick_index: i32::I32, a2b: bool): option_u64::OptionU64 {
    let tick_score = tick_score(current_tick_index);
    if (a2b) { // todo why next+false?
        skip_list::find_prev<Tick>(&tick_manager.ticks, tick_score, true)
    } else {
        skip_list::find_next(&tick_manager.ticks, tick_score, false)
    }
}

public(package) fun borrow_tick_for_swap(tick_manager: &TickManager, tick_score: u64, a2b: bool) : (&Tick, option_u64::OptionU64) {
    let node = skip_list::borrow_node<Tick>(&tick_manager.ticks, tick_score);
    let v = if (a2b) {
        skip_list::prev_score<Tick>(node)
    } else {
        skip_list::next_score<Tick>(node)
    };

    (skip_list::borrow_value<Tick>(node), v)
}


// === Private Functions ===

fun default(index: i32::I32): Tick {
    Tick {
        index,
        sqrt_price: tick_math::get_sqrt_price_at_tick(index),
        liquidity_net: i128::from(0),
        liquidity_gross: 0,
    }
}
