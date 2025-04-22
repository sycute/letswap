module suiclmm::clmm_math;

use integer_mate::full_math_u128;
use integer_mate::full_math_u64;
use integer_mate::i32::{Self, I32};
use integer_mate::math_u128;
use integer_mate::math_u256;
use suiclmm::tick_math;

// === Errors ===
const ETOKEN_AMOUNT_MAX_EXCEEDED: u64 = 0;
const ETOKEN_AMOUNT_MIN_SUBCEEDED: u64 = 1;
const EMULTIPLICATION_OVERFLOW: u64 = 2;
const EINVALID_SQRT_PRICE_INPUT: u64 = 4;
const EINVALID_FIXED_TOKEN_TYPE: u64 = 3018;
// === Constants ===
const FEE_RATE_DENOMINATOR: u64 = 1000000;

public fun fee_rate_denominator(): u64 {
    FEE_RATE_DENOMINATOR
}

public fun get_liquidity_from_a(
    sqrt_price_0: u128,
    sqrt_price_1: u128,
    amount_a: u64,
    round_up: bool,
): u128 {
    let sqrt_price_diff = if (sqrt_price_0 > sqrt_price_1) {
        sqrt_price_0 - sqrt_price_1
    } else {
        sqrt_price_1 - sqrt_price_0
    };
    let numberator =
        (full_math_u128::full_mul(sqrt_price_0, sqrt_price_1) >> 64) * (amount_a as u256);
    let div_res = math_u256::div_round(numberator, (sqrt_price_diff as u256), round_up);
    (div_res as u128)
}

public fun get_liquidity_from_b(
    sqrt_price_0: u128,
    sqrt_price_1: u128,
    amount_b: u64,
    round_up: bool,
): u128 {
    let sqrt_price_diff = if (sqrt_price_0 > sqrt_price_1) {
        sqrt_price_0 - sqrt_price_1
    } else {
        sqrt_price_1 - sqrt_price_0
    };
    let div_res = math_u256::div_round(
        ((amount_b as u256) << 64),
        (sqrt_price_diff as u256),
        round_up,
    );
    (div_res as u128)
}

public fun get_delta_a(
    sqrt_price_0: u128,
    sqrt_price_1: u128,
    liquidity: u128,
    round_up: bool,
): u64 {
    let sqrt_price_diff = if (sqrt_price_0 > sqrt_price_1) {
        sqrt_price_0 - sqrt_price_1
    } else {
        sqrt_price_1 - sqrt_price_0
    };
    if (sqrt_price_diff == 0 || liquidity == 0) {
        return 0
    };
    let (numberator, overflowing) = math_u256::checked_shlw(
        full_math_u128::full_mul(liquidity, sqrt_price_diff),
    );
    if (overflowing) {
        abort EMULTIPLICATION_OVERFLOW
    };
    let denominator = full_math_u128::full_mul(sqrt_price_0, sqrt_price_1);
    let quotient = math_u256::div_round(numberator, denominator, round_up);
    (quotient as u64)
}

public fun get_delta_b(
    sqrt_price_0: u128,
    sqrt_price_1: u128,
    liquidity: u128,
    round_up: bool,
): u64 {
    let sqrt_price_diff = if (sqrt_price_0 > sqrt_price_1) {
        sqrt_price_0 - sqrt_price_1
    } else {
        sqrt_price_1 - sqrt_price_0
    };
    if (sqrt_price_diff == 0 || liquidity == 0) {
        return 0
    };

    let lo64_mask = 0x000000000000000000000000000000000000000000000000ffffffffffffffff;
    let product = full_math_u128::full_mul(liquidity, sqrt_price_diff);
    // 乘积结果的低 64 位不为 0，则+1取整
    let should_round_up = (round_up) && ((product & lo64_mask) > 0);
    if (should_round_up) {
        return (((product >> 64) + 1) as u64)
    };
    ((product >> 64) as u64)
}

public fun get_next_sqrt_price_a_up(
    sqrt_price: u128,
    liquidity: u128,
    amount: u64,
    by_amount_input: bool,
): u128 {
    if (amount == 0) {
        return sqrt_price
    };

    let (numberator, overflowing) = math_u256::checked_shlw(
        full_math_u128::full_mul(sqrt_price, liquidity),
    );
    if (overflowing) {
        abort EMULTIPLICATION_OVERFLOW
    };

    let liquidity_shl_64 = (liquidity as u256) << 64;
    let product = full_math_u128::full_mul(sqrt_price, (amount as u128));
    let new_sqrt_price = if (by_amount_input) {
        (math_u256::div_round(numberator, (liquidity_shl_64 + product), true) as u128)
    } else {
        (math_u256::div_round(numberator, (liquidity_shl_64 - product), true) as u128)
    };

    if (new_sqrt_price > tick_math::max_sqrt_price()) {
        abort ETOKEN_AMOUNT_MAX_EXCEEDED
    } else if (new_sqrt_price < tick_math::min_sqrt_price()) {
        abort ETOKEN_AMOUNT_MIN_SUBCEEDED
    };

    new_sqrt_price
}

public fun get_next_sqrt_price_b_down(
    sqrt_price: u128,
    liquidity: u128,
    amount: u64,
    by_amount_input: bool,
): u128 {
    let delta_sqrt_price = math_u128::checked_div_round(
        ((amount as u128) << 64),
        liquidity,
        !by_amount_input,
    );
    let new_sqrt_price = if (by_amount_input) {
        sqrt_price + delta_sqrt_price
    } else {
        sqrt_price - delta_sqrt_price
    };

    if (new_sqrt_price > tick_math::max_sqrt_price()) {
        abort ETOKEN_AMOUNT_MAX_EXCEEDED
    } else if (new_sqrt_price < tick_math::min_sqrt_price()) {
        abort ETOKEN_AMOUNT_MIN_SUBCEEDED
    };

    new_sqrt_price
}

public fun get_next_sqrt_price_from_input(
    sqrt_price: u128,
    liquidity: u128,
    amount: u64,
    a_to_b: bool,
): u128 {
    if (a_to_b) {
        get_next_sqrt_price_a_up(sqrt_price, liquidity, amount, true)
    } else {
        get_next_sqrt_price_b_down(sqrt_price, liquidity, amount, true)
    }
}

public fun get_next_sqrt_price_from_output(
    sqrt_price: u128,
    liquidity: u128,
    amount: u64,
    a_to_b: bool,
): u128 {
    if (a_to_b) {
        get_next_sqrt_price_b_down(sqrt_price, liquidity, amount, false)
    } else {
        get_next_sqrt_price_a_up(sqrt_price, liquidity, amount, false)
    }
}

public fun get_delta_up_from_input(
    current_sqrt_price: u128,
    target_sqrt_price: u128,
    liquidity: u128,
    a_to_b: bool,
): u256 {
    let sqrt_price_diff = if (current_sqrt_price > target_sqrt_price) {
        current_sqrt_price - target_sqrt_price
    } else {
        target_sqrt_price - current_sqrt_price
    };
    if (sqrt_price_diff == 0 || liquidity == 0) {
        return 0
    };
    if (a_to_b) {

        let (numberator, overflowing) = math_u256::checked_shlw(
            full_math_u128::full_mul(liquidity, sqrt_price_diff),
        );
        if (overflowing) {
            abort EMULTIPLICATION_OVERFLOW
        };
        let denominator = full_math_u128::full_mul(current_sqrt_price, target_sqrt_price);
        math_u256::div_round(numberator, denominator, true)
    } else {

        let product = full_math_u128::full_mul(liquidity, sqrt_price_diff);
        let lo64_mask = 0x000000000000000000000000000000000000000000000000ffffffffffffffff;
        let should_round_up = (product & lo64_mask) > 0;
        if (should_round_up) {
            return (product >> 64) + 1
        };
        product >> 64
    }
}

public fun get_delta_down_from_output(
    current_sqrt_price: u128,
    target_sqrt_price: u128,
    liquidity: u128,
    a_to_b: bool,
): u256 {
    let sqrt_price_diff = if (current_sqrt_price > target_sqrt_price) {
        current_sqrt_price - target_sqrt_price
    } else {
        target_sqrt_price - current_sqrt_price
    };
    if (sqrt_price_diff == 0 || liquidity == 0) {
        return 0
    };
    if (a_to_b) {
        let product = full_math_u128::full_mul(liquidity, sqrt_price_diff);
        product >> 64
    } else {

        let (numberator, overflowing) = math_u256::checked_shlw(
            full_math_u128::full_mul(liquidity, sqrt_price_diff),
        );
        if (overflowing) {
            abort EMULTIPLICATION_OVERFLOW
        };
        let denominator = full_math_u128::full_mul(current_sqrt_price, target_sqrt_price);
        math_u256::div_round(numberator, denominator, false)
    }
}

public fun compute_swap_step(
    current_sqrt_price: u128,
    target_sqrt_price: u128,
    liquidity: u128,
    amount: u64,
    fee_rate: u64,
    a2b: bool,
    by_amount_in: bool,
): (u64, u64, u128, u64) {
    let mut next_sqrt_price = target_sqrt_price;
    let mut amount_in: u64 = 0;
    let mut amount_out: u64 = 0;
    let mut fee_amount: u64 = 0;
    if (liquidity == 0) {
        return (amount_in, amount_out, next_sqrt_price, fee_amount)
    };
    if (a2b) {
        assert!(current_sqrt_price >= target_sqrt_price, EINVALID_SQRT_PRICE_INPUT)
    } else {
        assert!(current_sqrt_price < target_sqrt_price, EINVALID_SQRT_PRICE_INPUT)
    };

    if (by_amount_in) {
        let amount_remain = full_math_u64::mul_div_floor(
            amount,
            (FEE_RATE_DENOMINATOR - fee_rate),
            FEE_RATE_DENOMINATOR,
        );
        let max_amount_in = get_delta_up_from_input(
            current_sqrt_price,
            target_sqrt_price,
            liquidity,
            a2b,
        );

        if (max_amount_in > (amount_remain as u256)) {
            amount_in = amount_remain;
            fee_amount = amount - amount_remain;
            next_sqrt_price =
                get_next_sqrt_price_from_input(
                    current_sqrt_price,
                    liquidity,
                    amount_remain,
                    a2b,
                );
        } else {
            amount_in = (max_amount_in as u64);
            fee_amount =
                full_math_u64::mul_div_ceil(amount_in, fee_rate, (FEE_RATE_DENOMINATOR - fee_rate));
            next_sqrt_price = target_sqrt_price;
        };
        amount_out =
                get_delta_down_from_output(
                    current_sqrt_price,
                    next_sqrt_price,
                    liquidity,
                    a2b,
                ) as u64
    } else {
        let max_amount_out = get_delta_down_from_output(
            current_sqrt_price,
            target_sqrt_price,
            liquidity,
            a2b,
        );
        if (max_amount_out > (amount as u256)) {
            amount_out = amount;
            next_sqrt_price =
                get_next_sqrt_price_from_output(current_sqrt_price, liquidity, amount, a2b);
        } else {
            amount_out = (max_amount_out as u64);
            next_sqrt_price = target_sqrt_price;
        };
        amount_in =
            (get_delta_up_from_input(current_sqrt_price, next_sqrt_price, liquidity, a2b) as u64);
        fee_amount =
            full_math_u64::mul_div_ceil(amount_in, fee_rate, (FEE_RATE_DENOMINATOR - fee_rate));
    };

    (amount_in, amount_out, next_sqrt_price, fee_amount)
}

/// Get the coin amount by liquidity
/// Params
///     - tick_lower The liquidity's lower tick
///     - tick_upper The liquidity's upper tick
///     - current_tick_index
/// Returns
///     - amount_a
///     - amount_b
///
/// 当提供/增加流动性时，会使用 RoundUp，这样可以保证增加数量为 L 的流动性时，用户提供足够的 token 到 pool 中
/// 当移除/减少流动性时，会使用 RoundDown，这样可以保证减少数量为 L 的流动性时，不会从 pool 中给用户多余的 token
public fun get_amount_by_liquidity(
    tick_lower: I32,
    tick_upper: I32,
    current_tick_index: I32,
    current_sqrt_price: u128,
    liquidity: u128,
    round_up: bool,
): (u64, u64) {
    if (liquidity == 0) {
        return (0, 0)
    };
    let lower_price = tick_math::get_sqrt_price_at_tick(tick_lower);
    let upper_price = tick_math::get_sqrt_price_at_tick(tick_upper);
    // Only coin a

    let (amount_a, amount_b) = if (i32::lt(current_tick_index, tick_lower)) {
        (get_delta_a(lower_price, upper_price, liquidity, round_up), 0)
    } else if (i32::lt(current_tick_index, tick_upper)) {
        (
            get_delta_a(current_sqrt_price, upper_price, liquidity, round_up),
            get_delta_b(lower_price, current_sqrt_price, liquidity, round_up),
        )
    } else {
        (0, get_delta_b(lower_price, upper_price, liquidity, round_up))
    };
    (amount_a, amount_b)
}

public fun get_liquidity_by_amount(
    lower_index: I32,
    upper_index: I32,
    current_tick_index: I32,
    current_sqrt_price: u128,
    amount: u64,
    is_fixed_a: bool,
): (u128, u64, u64) {
    let lower_price = tick_math::get_sqrt_price_at_tick(lower_index);
    let upper_price = tick_math::get_sqrt_price_at_tick(upper_index);
    let mut amount_a: u64 = 0;
    let mut amount_b: u64 = 0;
    let mut _liquidity: u128 = 0;
    if (is_fixed_a) {
        amount_a = amount;
        if (i32::lt(current_tick_index, lower_index)) {
            // 当前价格在区间外，delta_y = 0
            _liquidity = get_liquidity_from_a(lower_price, upper_price, amount, false);
        } else if (i32::lt(current_tick_index, upper_index)) {
            // 当前价格在区间内，先计算流动性L，然后计算 delta_y
            _liquidity = get_liquidity_from_a(current_sqrt_price, upper_price, amount, false);
            amount_b = get_delta_b(current_sqrt_price, lower_price, _liquidity, true);
        } else {
            abort EINVALID_FIXED_TOKEN_TYPE
        };
    } else {
        amount_b = amount;
        if (i32::gte(current_tick_index, upper_index)) {
            _liquidity = get_liquidity_from_b(lower_price, upper_price, amount, false);
        } else if (i32::gte(current_tick_index, lower_index)) {
            _liquidity = get_liquidity_from_b(lower_price, current_sqrt_price, amount, false);
            amount_a = get_delta_a(current_sqrt_price, upper_price, _liquidity, true);
        } else {
            abort EINVALID_FIXED_TOKEN_TYPE
        }
    };
    (_liquidity, amount_a, amount_b)
}

#[test]
fun test_get_liquidity_from_a() {
    use integer_mate::i32;
    //18446744073709551616 19392480388906836277 1000000 20505166
    let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i32::from(0));
    let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i32::from(1000));
    let amount_a = 1000000;
    assert!(get_liquidity_from_a(sqrt_price_0, sqrt_price_1, amount_a, false) == 20505166, 0);

    //11188795550323325955 30412779051191548722 1000000000 959569283
    let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i32::neg_from(10000));
    let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i32::from(10000));
    let amount_a = 1000000000;
    assert!(get_liquidity_from_a(sqrt_price_0, sqrt_price_1, amount_a, false) == 959569283, 0);

    //18437523468038800957 18455969290605290427 300000000000 300014987250637
    let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i32::neg_from(10));
    let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i32::from(10));
    let amount_a = 300000000000;
    assert!(
        get_liquidity_from_a(sqrt_price_0, sqrt_price_1, amount_a, false) == 300014987250637,
        0,
    );

    // 18437523468038800957 19392480388906836277 300000000000 6089108304263
    let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i32::neg_from(10));
    let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i32::from(1000));
    let amount_a = 300000000000;
    assert!(get_liquidity_from_a(sqrt_price_0, sqrt_price_1, amount_a, false) == 6089108304263, 0);

    //18437523468038800957 18455969290605290427 999000000000000 999049907544623895
    let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i32::neg_from(10));
    let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i32::from(10));
    let amount_a = 999000000000000;
    assert!(
        get_liquidity_from_a(sqrt_price_0, sqrt_price_1, amount_a, false) == 999049907544623895,
        0,
    );

    //18437523468038800957 18455969290605290427 18446744073709551615 18447665626965832135371
    let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i32::neg_from(10));
    let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i32::from(10));
    let amount_a = 18446744073709551615;
    assert!(
        get_liquidity_from_a(sqrt_price_0, sqrt_price_1, amount_a, false) == 18447665626965832135371,
        0,
    );
}

#[test]
fun test_get_liquidity_from_b() {
    use integer_mate::i32;
    // 18446744073709551616 19392480388906836277 1000000 19505166
    let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i32::from(0));
    let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i32::from(1000));
    let amount_b = 1000000;
    assert!(get_liquidity_from_b(sqrt_price_0, sqrt_price_1, amount_b, false) == 19505166, 0);

    // 11188795550323325955 30412779051191548722 1000000000 959569283
    let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i32::neg_from(10000));
    let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i32::from(10000));
    let amount_b = 1000000000;
    assert!(get_liquidity_from_b(sqrt_price_0, sqrt_price_1, amount_b, false) == 959569283, 0);

    // 18437523468038800957 18455969290605290427 300000000000 300014987250637
    let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i32::neg_from(10));
    let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i32::from(10));
    let amount_b = 300000000000;
    assert!(
        get_liquidity_from_b(sqrt_price_0, sqrt_price_1, amount_b, false) == 300014987250637,
        0,
    );

    // 18437523468038800957 19392480388906836277 300000000000 5795050123394
    let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i32::neg_from(10));
    let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i32::from(1000));
    let amount_b = 300000000000;
    assert!(get_liquidity_from_b(sqrt_price_0, sqrt_price_1, amount_b, false) == 5795050123394, 0);

    // 18437523468038800957 19392480388906836277 18446744073709551615 356332688401932418314
    let sqrt_price_0 = tick_math::get_sqrt_price_at_tick(i32::neg_from(10));
    let sqrt_price_1 = tick_math::get_sqrt_price_at_tick(i32::from(1000));
    let amount_b = 18446744073709551615;
    assert!(
        get_liquidity_from_b(sqrt_price_0, sqrt_price_1, amount_b, false) == 356332688401932418314,
        0,
    );
}

#[test]
fun test_get_delta_a() {
    assert!(get_delta_a(4u128 << 64, 2u128 << 64, 4, true) == 1, 0);
    assert!(get_delta_a(4u128 << 64, 2u128 << 64, 4, false) == 1, 0);

    assert!(get_delta_a(4 << 64, 4 << 64, 4, true) == 0, 0);
    assert!(get_delta_a(4 << 64, 4 << 64, 4, false) == 0, 0);
}

#[test]
fun test_get_delta_b() {
    assert!(get_delta_b(4u128 << 64, 2u128 << 64, 4, true) == 8, 0);
    assert!(get_delta_b(4u128 << 64, 2u128 << 64, 4, false) == 8, 0);

    assert!(get_delta_b(4 << 64, 4 << 64, 4, true) == 0, 0);
    assert!(get_delta_b(4 << 64, 4 << 64, 4, false) == 0, 0);
}

#[test]
fun test_get_next_price_a_up() {
    let (sqrt_price, liquidity, amount) = (10u128 << 64, 200u128 << 64, 10000000u64);
    let r1 = get_next_sqrt_price_a_up(sqrt_price, liquidity, amount, true);
    let r2 = get_next_sqrt_price_a_up(sqrt_price, liquidity, amount, false);
    assert!(184467440737090516161u128 == r1, 0);
    assert!(184467440737100516161u128 == r2, 0);
}

#[test]
fun test_get_next_price_a_down() {
    let (sqrt_price, liquidity, amount, add) = (
        62058032627749460283664515388u128,
        56315830353026631512438212669420532741u128,
        10476203047244913035u64,
        true,
    );
    let r = get_next_sqrt_price_b_down(sqrt_price, liquidity, amount, add);
    assert!(62058032627749460283664515391u128 == r, 0);
}

#[test]
fun test_compute_swap_step() {
    let (current_sqrt_price, target_sqrt_price, liquidity, amount, fee_rate) = (
        1u128 << 64,
        2u128 << 64,
        1000u128 << 32,
        20000,
        1000u64,
    );
    let (amount_in, amount_out, next_sqrt_price, fee_amount) = compute_swap_step(
        current_sqrt_price,
        target_sqrt_price,
        liquidity,
        amount,
        fee_rate,
        false,
        false,
    );
    // 20001 20000 18446744159608897937 21
    assert!(amount_in == 20001, 0);
    assert!(amount_out == 20000, 0);
    assert!(next_sqrt_price == 18446744159608897937, 0);
    assert!(fee_amount == 21, 0);

    // 19980 19979 18446744159522998190 20
    let (amount_in, amount_out, next_sqrt_price, fee_amount) = compute_swap_step(
        current_sqrt_price,
        target_sqrt_price,
        liquidity,
        amount,
        fee_rate,
        false,
        true,
    );
    assert!(amount_in == 19980, 0);
    assert!(amount_out == 19979, 0);
    assert!(next_sqrt_price == 18446744159522998190, 0);
    assert!(fee_amount == 20, 0);
}

#[test]
fun test_get_amount_by_liquidity_with_little_liquidity() {
    let (amount_a, amount_b) = get_amount_by_liquidity(
        i32::neg_from(1),
        i32::from(1),
        i32::from(0),
        tick_math::get_sqrt_price_at_tick(i32::from(0)),
        1,
        true,
    );
    assert!(amount_a > 0 || amount_b > 0, 0);

    let (amount_a, amount_b) = get_amount_by_liquidity(
        i32::neg_from(1),
        i32::from(1),
        i32::from(200),
        tick_math::get_sqrt_price_at_tick(i32::from(200)),
        1,
        true,
    );
    assert!(amount_a > 0 || amount_b > 0, 0);

    let (amount_a, amount_b) = get_amount_by_liquidity(
        i32::neg_from(1),
        i32::from(1),
        i32::neg_from(200),
        tick_math::get_sqrt_price_at_tick(i32::neg_from(200)),
        1,
        true,
    );
    assert!(amount_a > 0 || amount_b > 0, 0);
}

#[test]
fun test_get_liquidity_by_amount_with_little_amount() {
    let (liquidity, amount_a, amount_b) = get_liquidity_by_amount(
        i32::neg_from(443636),
        i32::from(443636),
        i32::from(0),
        tick_math::get_sqrt_price_at_tick(i32::from(0)),
        1,
        true,
    );
    let (recv_amount_a, recv_amount_b) = get_amount_by_liquidity(
        i32::neg_from(443636),
        i32::from(443636),
        i32::from(0),
        tick_math::get_sqrt_price_at_tick(i32::from(0)),
        liquidity,
        false,
    );
    assert!(recv_amount_a <= amount_a, 0);
    assert!(recv_amount_b <= amount_b, 0);

    let (liquidity, amount_a, amount_b) = get_liquidity_by_amount(
        i32::neg_from(443636),
        i32::from(443636),
        i32::from(0),
        tick_math::get_sqrt_price_at_tick(i32::from(0)),
        1,
        false,
    );
    let (recv_amount_a, recv_amount_b) = get_amount_by_liquidity(
        i32::neg_from(443636),
        i32::from(443636),
        i32::from(0),
        tick_math::get_sqrt_price_at_tick(i32::from(0)),
        liquidity,
        false,
    );
    assert!(recv_amount_a <= amount_a, 0);
    assert!(recv_amount_b <= amount_b, 0);
}
