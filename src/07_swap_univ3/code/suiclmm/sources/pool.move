module suiclmm::pool;

use integer_mate::i32::{Self, I32};
use integer_mate::math_u128;
use move_stl::option_u64;
use sui::balance::{Self, Balance};
use sui::event;
use sui::coin::{Self, Coin};
use suiclmm::clmm_math;
use suiclmm::position::{Self, Position};
use suiclmm::tick;
use suiclmm::tick_math;

// === Errors ===
const ETOKEN_NOT_EXPECTED_AMOUNT: u64 = 0;
const ETICK_RANGE_ERROR: u64 = 2;
const EPOOL_NOT_EQUAL: u64 = 12;

// === Structs ===
public struct Pool<phantom CoinTypeA, phantom CoinTypeB> has key, store {
    id: UID,
    coin_a: Balance<CoinTypeA>,
    coin_b: Balance<CoinTypeB>,
    tick_spacing: u32,
    liquidity: u128,
    current_sqrt_price: u128,
    current_tick_index: I32,
    tick_manager: tick::TickManager,
    position_manager: position::PositionManager,
}

public struct AddLiquidityReceipt<phantom CoinTypeA, phantom CoinTypeB> {
    pool_id: ID,
    amount_a: u64,
    amount_b: u64,
}

public struct  SwapResult has copy, drop {
    amount_in: u64,
    amount_out: u64,
    steps: u64,
}

public struct FlashSwapReceipt<phantom CoinTypeA, phantom CoinTypeB> {
    pool_id: ID,
    a2b: bool,
    pay_amount: u64,
}

// === Evenets ===
public struct AddLiquidityEvent has copy, drop {
    pool_id: ID,
    amount_a: u64,
    amount_b: u64,
}

// === Public Functions ===
public fun id<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): ID {
    object::id(pool)
}

public fun receipt_amount<CoinTypeA, CoinTypeB>(receipt: &AddLiquidityReceipt<CoinTypeA, CoinTypeB>): (u64, u64) {
    (receipt.amount_a, receipt.amount_b)
}

// tick = -443520, tick >>> 0 -> 4294523776 转为无符号整型
public fun open_position<CoinTypeA, CoinTypeB>(
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    tick_lower: u32,
    tick_upper: u32,
    ctx: &mut TxContext,
): Position {
    let tick_lower_index = i32::from_u32(tick_lower);
    let tick_upper_index = i32::from_u32(tick_upper);
    check_position_tick_range(tick_lower_index, tick_upper_index, pool.tick_spacing);
    let pool_id = object::id(pool);

    let position = position::open_position<CoinTypeA, CoinTypeB>(
        &mut pool.position_manager,
        pool_id,
        tick_lower_index,
        tick_upper_index,
        ctx,
    );

    position
}

// 指定一种coin，计算另一种coin的数量
public fun add_liquidity_fix_coin<CoinTypeA, CoinTypeB>(
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    position_nft: &mut Position,
    amount: u64,
    fix_amount_a: bool,
): AddLiquidityReceipt<CoinTypeA, CoinTypeB> {
    let (tick_lower_index, tick_upper_index) = position_nft.tick_range();

    // get_liquidity_by_amount
    let (_delta_liquidity, amount_a, amount_b) = clmm_math::get_liquidity_by_amount(
        tick_lower_index,
        tick_upper_index,
        pool.current_tick_index,
        pool.current_sqrt_price,
        amount,
        fix_amount_a,
    );

    tick::add_liquidity(
        &mut pool.tick_manager,
        tick_lower_index,
        tick_upper_index,
        _delta_liquidity,
    );
    position::add_liquidity(
        &mut pool.position_manager,
        position_nft,
        _delta_liquidity,
    );

    // [lower, upper)
    if (
        i32::gte(pool.current_tick_index, tick_lower_index) 
        && i32::lt(pool.current_tick_index, tick_upper_index)
    ) {
        pool.liquidity = pool.liquidity + _delta_liquidity;
    };
    let e = AddLiquidityEvent {
        pool_id: object::id(pool),
        amount_a,
        amount_b,
    };
    event::emit(e);

    AddLiquidityReceipt {
        pool_id: object::id(pool),
        amount_a,
        amount_b,
    }
}

public fun repay_add_liquidity<CoinTypeA, CoinTypeB>(
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    balance_a: Balance<CoinTypeA>,
    balance_b: Balance<CoinTypeB>,
    receipt: AddLiquidityReceipt<CoinTypeA, CoinTypeB>,
) {
    let AddLiquidityReceipt {
        pool_id,
        amount_a,
        amount_b,
    } = receipt;

    assert!(object::id(pool) == pool_id, EPOOL_NOT_EQUAL);
    assert!(balance_a.value() == amount_a, ETOKEN_NOT_EXPECTED_AMOUNT);
    assert!(balance_b.value() == amount_b, ETOKEN_NOT_EXPECTED_AMOUNT);

    pool.coin_a.join(balance_a);
    pool.coin_b.join(balance_b);
}

public fun open_position_with_liquidity_by_fix_coin<CoinTypeA, CoinTypeB>(
    pool:&mut Pool<CoinTypeA, CoinTypeB>,
    tick_lower: u32, 
    tick_upper: u32, 
    coin_a: Coin<CoinTypeA>,
    coin_b: Coin<CoinTypeB>,
    amount_a: u64,    
    amount_b: u64,
    fix_amount_a: bool, 
    ctx: &mut TxContext
 ): (Position, Coin<CoinTypeA>, Coin<CoinTypeB>) {
    let amount = if (fix_amount_a) {
        amount_a
    } else {
        amount_b
    };
    let mut position_nft = open_position( pool, tick_lower, tick_upper, ctx);
    let receipt = add_liquidity_fix_coin(pool, &mut position_nft, amount, fix_amount_a);
    
    let mut balance_a =  coin_a.into_balance();
    let mut balance_b =  coin_b.into_balance();

    repay_add_liquidity(
        pool, 
    balance_a.split(receipt.amount_a), 
    balance_b.split(receipt.amount_b), 
    receipt
    );    
    
    (position_nft, coin::from_balance(balance_a, ctx), coin::from_balance(balance_b, ctx))
}

public fun swap<CoinTypeA, CoinTypeB>(
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    coin_a: Coin<CoinTypeA>,
    coin_b: Coin<CoinTypeB>,
    a2b: bool,
    by_amount_in: bool,
    amount: u64,
    sqrt_price_limit: u128,
    ctx: &mut TxContext,
): (Coin<CoinTypeA>, Coin<CoinTypeB>) {

    let actual_amount = if (by_amount_in) {
        if (a2b) {
            coin_a.value()
        } else {
            coin_b.value()
        }
    } else {
        amount
    };

    let (out_a, out_b, receipt) = flash_swap(pool, a2b, by_amount_in, actual_amount, sqrt_price_limit);
    
    let mut balance_a = coin_a.into_balance();
    let mut balance_b = coin_b.into_balance();
    let (required_a, required_b) = if (a2b) {
        (balance_a.split(receipt.pay_amount), balance::zero())
    } else {
        (balance::zero(), balance_b.split(receipt.pay_amount))
    };

    repay_flash_swap(pool,required_a, required_b, receipt);
    balance_a.join(out_a);
    balance_b.join(out_b);
    (coin::from_balance(balance_a, ctx), coin::from_balance(balance_b, ctx))
}

public fun flash_swap<CoinTypeA, CoinTypeB>(pool: &mut Pool<CoinTypeA, CoinTypeB>, is_a2b:bool, is_by_amount_in: bool, amount: u64, sqrt_price_limit: u128): (balance::Balance<CoinTypeA>, balance::Balance<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>) {

    let swap_result = flash_swap_internal(pool, is_a2b, is_by_amount_in, amount, sqrt_price_limit);
    let (swap_amount_in, swap_amount_out) = if (is_a2b) {
        (balance::zero(), pool.coin_b.split(swap_result.amount_out))
    } else {
        (pool.coin_a.split(swap_result.amount_out), balance::zero())
    };

    let receipt = FlashSwapReceipt<CoinTypeA, CoinTypeB> {
        pool_id: object::id(pool),
        a2b: is_a2b,
        pay_amount: swap_result.amount_in,
    };

    (swap_amount_in, swap_amount_out, receipt)
}

public fun swap_pay_amount<CoinTypeA, CoinTypeB>(flashswap_receipt: &FlashSwapReceipt<CoinTypeA, CoinTypeB>): u64 {
    flashswap_receipt.pay_amount
}

public fun repay_flash_swap<CoinTypeA, CoinTypeB>(
    pool:&mut Pool<CoinTypeA, CoinTypeB>,
    balance_a: Balance<CoinTypeA>,
    balance_b: Balance<CoinTypeB>,
    flashswap_receipt: FlashSwapReceipt<CoinTypeA, CoinTypeB>
) {
    let FlashSwapReceipt {
        pool_id,        a2b,
        pay_amount,
    } = flashswap_receipt;

    assert!(object::id(pool) == pool_id, EPOOL_NOT_EQUAL);

    if (a2b) {
        assert!(balance_a.value() == pay_amount, ETOKEN_NOT_EXPECTED_AMOUNT);
        pool.coin_a.join(balance_a);
        balance::destroy_zero(balance_b);
    } else {
        assert!(balance_b.value() == pay_amount, ETOKEN_NOT_EXPECTED_AMOUNT);
        pool.coin_b.join(balance_b);
        balance::destroy_zero(balance_a);
    }
}



// === Package Functions ===
public(package) fun new<CoinTypeA, CoinTypeB>(
    tick_spacing: u32,
    initial_sqrt_price: u128,
    ctx: &mut TxContext,
): Pool<CoinTypeA, CoinTypeB> {
    Pool {
        id: object::new(ctx),
        coin_a: balance::zero<CoinTypeA>(),
        coin_b: balance::zero<CoinTypeB>(),
        tick_spacing,
        liquidity: 0,
        current_sqrt_price: initial_sqrt_price,
        current_tick_index: tick_math::get_tick_at_sqrt_price(initial_sqrt_price),
        tick_manager: tick::new(tick_spacing, 0, ctx),
        position_manager: position::new(tick_spacing, ctx),
    }
}

// === Internal Functions ===
fun flash_swap_internal<CoinTypeA, CoinTypeB>(
    pool: &mut Pool<CoinTypeA, CoinTypeB>,
    a2b: bool,
    is_by_amount_in: bool,
    amount: u64,
    sqrt_price_limit: u128
): SwapResult {
    let mut swap_result = default_swap_result();
    let mut tick_score = tick::first_score_for_swap(&pool.tick_manager, pool.current_tick_index, a2b);
    let mut remain_amount = amount;

    while (remain_amount > 0 && pool.current_sqrt_price != sqrt_price_limit) {
        if (option_u64::is_none(&tick_score)) {
            abort 4
        };
        let (tick, op64) = tick::borrow_tick_for_swap(&pool.tick_manager, option_u64::borrow(&tick_score), a2b);
        tick_score = op64;
        let tick_index = tick.index();
        let tick_sqrt_price = tick.sqrt_price();
        let target_sqrt_price = if (a2b) {
            math_u128::max(sqrt_price_limit, tick_sqrt_price)
        } else {
            math_u128::min(sqrt_price_limit, tick_sqrt_price)
        };

        let (amount_in, amount_out, next_sqrt_price, _fee_amount) = clmm_math::compute_swap_step(
            pool.current_sqrt_price,
            target_sqrt_price,
            pool.liquidity,
            remain_amount,
            0,
            a2b,
            is_by_amount_in
        );

        if (amount_in > 0) {
            assert!(remain_amount >= amount_in, 5);
            remain_amount = remain_amount - amount_in;

            // update swap_result
            swap_result.amount_in = swap_result.amount_in + amount_in;
            swap_result.amount_out = swap_result.amount_out + amount_out;
            swap_result.steps = swap_result.steps + 1;
        };

        // todo ?
        if (next_sqrt_price == tick_sqrt_price) {
            pool.current_sqrt_price = next_sqrt_price;
            if (a2b) {
                pool.current_tick_index = i32::sub(tick_index, i32::from(1)); // todo why?
            };
            pool.liquidity = tick::cross_by_swap(&mut pool.tick_manager, tick_index, a2b, pool.liquidity);
            continue
        };

        if (pool.current_sqrt_price != tick_sqrt_price) {
            pool.current_sqrt_price = next_sqrt_price;
            pool.current_tick_index = tick_math::get_tick_at_sqrt_price(next_sqrt_price);
            continue
        };
    };
    swap_result
}
fun check_position_tick_range(lower: I32, upper: I32, spacing: u32) {
    assert!(i32::gt(upper, lower), ETICK_RANGE_ERROR);
    assert!(
        i32::gte(tick_math::max_tick(), upper) && i32::lte(tick_math::min_tick(), lower),
        ETICK_RANGE_ERROR,
    );
    assert!(
        i32::mod(lower, i32::from(spacing)) == i32::from(0) && i32::mod(upper, i32::from(spacing)) == i32::from(0),
        ETICK_RANGE_ERROR,
    );
}

fun default_swap_result() : SwapResult {
    SwapResult{
        amount_in      : 0,
        amount_out     : 0,
        steps          : 0,
    }
}
