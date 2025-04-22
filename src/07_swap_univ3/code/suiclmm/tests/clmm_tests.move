#[test_only]
module suiclmm::suiclmm_tests;

use std::debug;
use sui::coin;
use sui::balance;
use sui::test_scenario;
use sui::transfer::{public_share_object, public_transfer};
use suiclmm::pool;

const Alice: address = @0xA11CE;

#[test_only]
public struct CoinA {}
// public struct CoinA has key,store {}

#[test_only]
public struct CoinB {}

#[test]
fun test_create_pool() {
    let mut scenario = test_scenario::begin(Alice);
    let ctx = test_scenario::ctx(&mut scenario);


    // 1. create pool -> pool, priceSqrtX64 = 18446744073709551616, tickspace=2,
    let init_price_sqrt  = 36893488147419103232; // price=4
    let mut new_pool = pool::new<CoinA, CoinB>(2, init_price_sqrt, ctx);

    // 2. open_position -> position_nft
    let mut my_position = pool::open_position<CoinA,CoinB>(&mut new_pool, 2, 6, ctx);
    // 3. add_liquidity_fix_amount -> receipt
    let  receipt = pool::add_liquidity_fix_coin(&mut new_pool, &mut my_position, 100, false);
    debug::print(&receipt);
    // 4. pay_receipt -> done
    let conA = coin::mint_for_testing<CoinA>(0, ctx);
    let conB = coin::mint_for_testing<CoinB>(100, ctx);
    pool::repay_add_liquidity(&mut new_pool, coin::into_balance(conA), coin::into_balance(conB), receipt);

    debug::print(&new_pool);
    debug::print(&my_position);


    public_share_object(new_pool);
    public_transfer(my_position, Alice);
    test_scenario::end(scenario);
}


#[test]
fun test_swap() {

    let mut scenario = test_scenario::begin(Alice);
    let ctx = test_scenario::ctx(&mut scenario);

    // 1. create pool -> pool, priceSqrtX64 = 18446744073709551616, tickspace=2,
    let init_price_sqrt  = 36893488147419103232; // price=4
    let mut new_pool = pool::new<CoinA, CoinB>(2, init_price_sqrt, ctx);
    // 2. open_position -> position_nft
    let mut my_position = pool::open_position<CoinA,CoinB>(&mut new_pool, 2, 6, ctx);
    
    // 3. add_liquidity_fix_amount -> receipt
    let  receipt = pool::add_liquidity_fix_coin(&mut new_pool, &mut my_position, 100, false);
    // debug::print(&receipt);
    // 4. pay_receipt -> done
    let conB = coin::mint_for_testing<CoinB>(100, ctx);
    pool::repay_add_liquidity(&mut new_pool, 
    balance::zero<CoinA>(), coin::into_balance(conB), receipt);

    // === swap ===
    let conA = coin::mint_for_testing<CoinA>(10, ctx);
    let amount_in = 10;
    let is_a2b = true;
    let is_by_amount_in = true;
    let sqrt_price_limit = 0;

    let (swap_amount_in, swap_amount_out, receipt) = pool::flash_swap<CoinA, CoinB>(
        &mut new_pool, 
        is_a2b, is_by_amount_in, 
        amount_in, 
        sqrt_price_limit
        );
    // debug::print(&receipt);

    // 5. repay_flash_swap -> done
    
    pool::repay_flash_swap(&mut new_pool, coin::into_balance(conA), balance::zero<CoinB>(), receipt);


    // done
    public_share_object(new_pool);
    public_transfer(my_position, Alice);
    
    balance::destroy_zero(swap_amount_in);
    let swaped_coin_b = coin::from_balance(swap_amount_out, ctx);
    public_transfer(swaped_coin_b, Alice);

    test_scenario::end(scenario);
}