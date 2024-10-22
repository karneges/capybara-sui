/// Module: capybara
module capybara::capybara_game_card {
    use std::option;
    use std::option::Option;
    use std::string::{utf8, String};
    use std::vector;
    use sui::event::{Self};
    use sui::coin::{Self, Coin};
    use sui::ecdsa_k1;
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table, drop};
    use sui::sui::SUI;
    use sui::dynamic_field as df;
    use sui::dynamic_object_field as dof;
    use sui::package;
    use sui::display;
    use sui::object;
    use sui::object::{UID, ID};
    use sui::transfer;
    use sui::tx_context;
    use sui::tx_context::TxContext;
    use sui::address;
    use sui::random::Random;
    #[test_only]
    use capybara::capybara_game_card::init;

    // === Constants ===
    const VERSION: u64 = 1;

    // === Types ===
    public struct AdminCap has key, store { id: UID }

    public struct TreasurerKey<phantom T> has copy, store, drop {}

    public struct TreasurerCap has store, drop {}

    public struct Treasury has key {
        id: UID,
        version: u64,
        balance: Balance<SUI>,
        checkin_fee: u64,
    }

    public struct Registry has key {
        id: UID,
        version: u64,
        leagues: vector<String>,
        pk: vector<u8>,
        items: Table<address, RegistryItem>,
    }

    public struct RegistryItem has store, drop {
        id: ID,
        nonce: u64,
    }

    public struct NFTData has key {
        id: UID,
        owner: address,
        league: String,
        points: u64,
    }

    public struct CheckinArgTBS has drop {
        nonce: u64,
        points: Option<u64>,
        league: Option<String>,
    }

    public struct CapybaraNft has key {
        id: UID
    }

    public struct NftAccessorie has key, store {
        id: UID,
        type_field: u8,
    }
    // struct AccessoryKey has copy, store, drop { type: String }

    /// One-Time-Witness for the module.
    public struct CAPYBARA_GAME_CARD has drop {}

    // === Events ===
    public struct MintNFT has copy, drop {
        from: address,
        to: address,
        nft_id: ID,
    }

    public struct DailyCheckin has copy, drop {
        nft_id: ID,
        new_points: Option<u64>,
        new_league: Option<String>,
    }

    public struct SpentPoints has copy, drop {
        nft_id: ID,
        amount: u64,
    }

    public struct BurnNFT has copy, drop {
        nft_id: ID,
    }

    public struct UpdateFee has copy, drop {
        fee: u64
    }

    public struct UpdatePublicKey has copy, drop {
        pk: vector<u8>,
    }

    public struct UpdateLeagues has copy, drop {
        leagues: vector<String>,
    }

    public struct WithdrawAmount has copy, drop {
        amount: u64
    }

    // === Errors ===
    const ENotEnough: u64 = 0;
    const EWrongVersion: u64 = 1;
    const EInvalidSender: u64 = 2;
    const EAlreadyHasNFT: u64 = 3;
    const EInvalidSignature: u64 = 4;
    const EOutdatedNonce: u64 = 5;
    const EUnknownLeague: u64 = 6;

    // === Functions ===
    fun init(otw: CAPYBARA_GAME_CARD, ctx: &mut TxContext) {
        let admin_cap = AdminCap { id: object::new(ctx) };
        let treasury = Treasury {
            id: object::new(ctx),
            version: VERSION,
            balance: balance::zero<SUI>(),
            checkin_fee: 300_000_000,
        };
        let leagues: vector<String> = vector[
            b"Starving".to_string(),
            b"Famished".to_string(),
            b"Hungry".to_string(),
            b"Full".to_string(),
            b"Nourished".to_string(),
        ];
        let registry = Registry {
            id: object::new(ctx),
            version: VERSION,
            leagues,
            pk: x"035229dff81f3e3f5a1526b92908752395d96bf6b41cc253b2ad5bebe503149cf2",
            items: table::new(ctx),
        };

        let keys = vector[
            utf8(b"name"),
            utf8(b"description"),
            utf8(b"league"),
            utf8(b"points"),
            utf8(b"image_url"),
            utf8(b"thumbnail_url"),
        ];
        let values = vector[
            utf8(b"Player card"),
            utf8(b"With {league} level and {points} points"),
            utf8(b"{league}"),
            utf8(b"{points}"),
            utf8(b"https://capybara_static.8gen.team/{league}.png"),
            utf8(b"https://capybara_static.8gen.team/{league}_preview.png"),
        ];
        let publisher = package::claim(otw, ctx);
        let mut display = display::new_with_fields<NFTData>(
            &publisher, keys, values, ctx
        );
        display::update_version(&mut display);
        let owner_addr_as_u8: vector<u8> = address::to_bytes(@0x3a1a0722453ff6da8a9695ef9588bd0ef57e60df8eee12f45cb792a170f179e1);
        let owner_address = address::from_bytes(owner_addr_as_u8);
        transfer::public_transfer(admin_cap, owner_address);
        transfer::public_transfer(publisher, owner_address);
        transfer::public_transfer(display, owner_address);
        transfer::share_object(treasury);
        transfer::share_object(registry);
    }

    fun new_nft(
        recipient: address,
        league: String,
        points: u64,
        ctx: &mut TxContext
    ): NFTData {
        NFTData {
            id: object::new(ctx),
            owner: recipient,
            points,
            league,
        }
    }

    public entry fun mint(
        registry: &mut Registry,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        assert!(VERSION == 1, EWrongVersion);
        let sender: address = tx_context::sender(ctx);
        assert!(!table::contains<address, RegistryItem>(&registry.items, recipient), EAlreadyHasNFT);

        let nft: NFTData = capybara::capybara_game_card::new_nft(
            recipient,
            utf8(b"Starving"),
            0,
            ctx,
        );

        let nft_id: ID = object::id(&nft);

        let item = RegistryItem {
            id: nft_id,
            nonce: 0,
        };
        table::add(&mut registry.items, recipient, item);

        event::emit(MintNFT{ from: sender, to: recipient, nft_id: nft_id });
        transfer::transfer(nft, recipient);
    }

    public fun serialize_checkin_args(nonce: u64, points: Option<u64>, league: Option<String>): vector<u8> {
        let arg = CheckinArgTBS {
            nonce,
            points,
            league,
        };
        std::bcs::to_bytes(&arg)
    }

    public entry fun checkin(
        nft: &mut NFTData,
        treasury: &mut Treasury,
        registry: &mut Registry,
        fee: &mut Coin<SUI>,
        nonce: u64,
        points: Option<u64>,
        league: Option<String>,
        signature: vector<u8>,
        ctx: &mut TxContext
    ) {
        assert!(VERSION == 1, EWrongVersion);
        let NFTData { id, owner: _, league: _, points: _} = nft;
        let nft_id: ID = object::uid_to_inner(id);
        let sender: address = tx_context::sender(ctx);

        assert!(coin::value(fee) >= treasury.checkin_fee, ENotEnough);
        let fee_coin: Coin<SUI> = coin::split(fee, treasury.checkin_fee, ctx);
        coin::put(&mut treasury.balance, fee_coin);

        let msg = capybara::capybara_game_card::serialize_checkin_args(nonce, points, league);
        let verify = ecdsa_k1::secp256k1_verify(&signature, &registry.pk, &msg, 1);
        assert!(verify, EInvalidSignature);
        let item: &mut RegistryItem = table::borrow_mut(&mut registry.items, sender);
        assert!(item.nonce == nonce, EOutdatedNonce);
        item.nonce = item.nonce + 1;


        if(points.is_some()) {
            nft.points = *points.borrow();
        };

        if(league.is_some()) {
            let league = *league.borrow();
            assert!(vector::contains(&registry.leagues, &league), EUnknownLeague);
            nft.league = league;
        };


        event::emit(DailyCheckin { nft_id, new_points: points, new_league: league });


    }

    public entry fun spend<T>(
        registry: &mut Registry,
        nft: &mut NFTData,
        amount: u64,
    ) {
        assert!(capybara::capybara_game_card::is_treasurer<T>(registry), EInvalidSender);
        let NFTData { id, owner, league: _, points: _} = nft;
        let nft_id: ID = object::uid_to_inner(id);
        assert!(table::contains<address, RegistryItem>(&registry.items, *owner), EInvalidSender);

        let item: &mut RegistryItem = table::borrow_mut(&mut registry.items, *owner);
        item.nonce = item.nonce + 1;
        assert!(nft.points >= amount, ENotEnough);
        nft.points = nft.points - amount;
        event::emit(SpentPoints { nft_id, amount });
    }

    public entry fun burn(
        registry: &mut Registry,
        nft: NFTData,
    ) {
        assert!(VERSION == 1, EWrongVersion);
        let NFTData { id, owner, league: _, points: _} = nft;
        let nft_id: ID = object::uid_to_inner(&id);
        table::remove(&mut registry.items, owner);
        object::delete(id);
        event::emit(BurnNFT { nft_id: nft_id });
    }

    // === NFT Getter Functions ===
    public fun owner(nft: &NFTData): address {
        nft.owner
    }

    public fun points(nft: &NFTData): u64 {
        nft.points
    }

    public fun league(nft: &NFTData): String {
        nft.league
    }

    // === Admin-only functionality ===
    public entry fun update_checkin_fee(
        treasury: &mut Treasury, _: &AdminCap, checkin_fee: u64
    ) {
        event::emit(UpdateFee { fee: checkin_fee });
        treasury.checkin_fee = checkin_fee
    }

    public fun is_treasurer<T>(registry: &Registry): bool {
        df::exists_<TreasurerKey<T>>(&registry.id, TreasurerKey {})
    }

    public entry fun grant_treasurer_cap<T>(_: &AdminCap, registry: &mut Registry) {
        df::add(&mut registry.id, TreasurerKey<T> {}, TreasurerCap {});
    }
    public entry fun revoke_treasurer_cap<T>(_: &AdminCap, registry: &mut Registry) {
        df::remove<TreasurerKey<T>, TreasurerCap>(&mut registry.id, TreasurerKey<T> {});
    }

    public entry fun update_pk(
        registry: &mut Registry, _: &AdminCap, new_pk: vector<u8>
    ) {
        event::emit(UpdatePublicKey { pk: new_pk });
        registry.pk = new_pk;
    }

    public entry fun update_leagues(
        registry: &mut Registry, _: &AdminCap, new_leagues: vector<String>
    ) {
        event::emit(UpdateLeagues { leagues: new_leagues });
        registry.leagues = new_leagues;
    }


    public entry fun withdraw(
        treasury: &mut Treasury, _: &AdminCap, amount: Option<u64>, ctx: &mut TxContext
    ) {
        let amount = if (option::is_some(&amount)) {
            let amt = option::destroy_some(amount);
            assert!(amt <= balance::value(&treasury.balance), ENotEnough);
            amt
        } else {
            balance::value(&treasury.balance)
        };
        let withdraw_coin: Coin<SUI> = coin::take(&mut treasury.balance, amount, ctx);
        event::emit(WithdrawAmount { amount: amount});
        transfer::public_transfer(withdraw_coin, tx_context::sender(ctx))
    }

    // === Tests ===
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(CAPYBARA_GAME_CARD{}, ctx);
    }
}
