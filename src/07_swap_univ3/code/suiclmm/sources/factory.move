module suiclmm::factory;


use std::type_name;
use sui::coin;
use move_stl::linked_table;
use sui::transfer::public_share_object;
use suiclmm::pool;
use suiclmm::position;

public struct Pools has key, store {
    id: UID,
    list: linked_table::LinkedTable<ID, PoolSimpleInfo>,
    index: u64,
}

public struct PoolSimpleInfo has copy, drop, store {
    pool_id: ID,
    coin_type_a: type_name::TypeName,
    coin_type_b: type_name::TypeName,
    tick_spacing: u32,
}

public struct FACTORY has drop {}

fun init(_wtn: FACTORY, ctx: &mut TxContext) {
    let pools = Pools {
        id: object::new(ctx),
        list: linked_table::new(ctx),
        index: 0,
    };
    public_share_object(pools);
}

public fun create_pool_with_liquidity<CoinTypeA, CoinTypeB>(
    pools: &mut Pools, 
    tick_spacing: u32, 
    initial_sqrt_price: u128, 
    tick_lower: u32, 
    tick_upper: u32,
    coin_a: coin::Coin<CoinTypeA>,
    coin_b: coin::Coin<CoinTypeB>,
    fix_amount_a: bool,
    ctx: &mut TxContext
 ):(position::Position, coin::Coin<CoinTypeA>, coin::Coin<CoinTypeB>){
    // 1. 创建池子
    let mut new_pool = pool::new<CoinTypeA, CoinTypeB>(tick_spacing, initial_sqrt_price, ctx);
    // 2. 开仓
    let mut position_nft = pool::open_position(&mut new_pool, tick_lower, tick_upper, ctx);
    let amount= if (fix_amount_a) {
        coin_a.value()
    } else {
        coin_b.value()
    };
    // 3. 计算需要的token 数量      
    let receipt = pool::add_liquidity_fix_coin(&mut new_pool, &mut position_nft, amount, fix_amount_a);
    
    let (required_a, required_b) = receipt.receipt_amount();
    
    // 4. 付款
    let mut balance_a = coin_a.into_balance();
    let mut balance_b = coin_b.into_balance();

    pool::repay_add_liquidity(&mut new_pool, 
    balance_a.split(required_a), 
    balance_b.split(required_b), 
    receipt);

    let pool_info  = PoolSimpleInfo {
        pool_id: new_pool.id(),
        coin_type_a: type_name::get<CoinTypeA>(),
        coin_type_b: type_name::get<CoinTypeB>(),
        tick_spacing,
     };

    linked_table::push_back(&mut pools.list, new_pool.id(), pool_info);

    transfer::public_share_object(new_pool);


    (position_nft, balance_a.into_coin(ctx), balance_b.into_coin(ctx))
}

public fun create_pool<CoinTypeA, CoinTypeB>(
    pools: &mut Pools,
    tick_spacing: u32,
    initial_sqrt_price: u128,
    ctx: &mut TxContext,
) {
    let pool = pool::new<CoinTypeA, CoinTypeB>(tick_spacing, initial_sqrt_price, ctx);
    let pool_info  = PoolSimpleInfo {
        pool_id: pool.id(),
        coin_type_a: type_name::get<CoinTypeA>(),
        coin_type_b: type_name::get<CoinTypeB>(),
        tick_spacing,
     };

    linked_table::push_back(&mut pools.list, pool.id(), pool_info);

    public_share_object(pool);
}

// key: (tokenA, tokenB, spacing)
// public fun new_pool_key<T0, T1>(tick_spacing: u32) : object::ID {
//     let mut v0 = type_name::get<T0>().into_string();
//     let mut v1 = *ascii::as_bytes(&v0);
//     let  mut v2 = type_name::get<T1>().into_string();
//     let mut v3 = *ascii::as_bytes(&v2);
//     let  mut i = 0;
//     let mut  v5 = false;
//     while (i < v3.length()) {
//         let v6 = v3[i];
//         let v7 = !v5 && i <vector::length<u8>(&v1);
//         let v8;
//         if (v7) {
//             let v9 = v1[i];
//             if (v9 < v6) {
//                 v8 = 6;
//                 abort v8
//             };
//             if (v9 > v6) {
//                 v5 = true;
//             };
//         };
//        vector::push_back<u8>(&mut v1, v6);
//         i = i + 1;
//         continue;
//         v8 = 6;
//         abort v8
//     };
//     if (!v5) {
//         if (vector::length<u8>(&v1) <vector::length<u8>(&v3)) {
//             abort 6
//         };
//         if (vector::length<u8>(&v1) ==vector::length<u8>(&v3)) {
//             abort 3
//         };
//     };
//     let mut b = bcs::to_bytes(&tick_spacing);
//     v1.append(b);
//     object::id_from_bytes(hash::blake2b256(&v1))
// }