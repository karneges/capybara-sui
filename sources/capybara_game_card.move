/// Module: capybara
module capybara::capybara_game_card {
    use std::option::{Option};
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
    use sui::clock::Clock;
    use sui::display::{Display};
    use sui::package::Publisher;
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
        leagues: vector<u64>,
        pk: vector<u8>,
        items: Table<address, RegistryItem>,
        check_signature: bool,
    }

    public struct RegistryItem has store, drop {
        id: ID,
    }

    public struct NFTData has key {
        id: UID,
        owner: address,
        league: u64,
        points: u64,
    }

    public struct CheckinArgTBS has drop {
        valid_until: u64,
        points: Option<u64>,
        league: Option<u64>,
        user: String,
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
        points: u64,
        league: u64,
        nft_id: ID,
    }

    public struct DailyCheckin has copy, drop {
        nft_id: ID,
        new_points: Option<u64>,
        new_league: Option<u64>,
        fee: u64,
    }

    public struct UserEvt has copy, drop {
        user: String,
        signature: vector<u8>,
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
        leagues: vector<u64>,
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
            checkin_fee: 0,
        };
        let leagues: vector<u64> = vector[
            0,
            1,
            2,
            3,
            4,
        ];
        let registry = Registry {
            id: object::new(ctx),
            version: VERSION,
            leagues,
            pk: x"031d9cd3748b019a247773cae4c6e34abba70ba9fd25f86fff1595b012337d3150",
            items: table::new(ctx),
            check_signature: true,
        };

        let keys = vector[
            utf8(b"name"),
            utf8(b"description"),
            utf8(b"coins earned"),
            utf8(b"league"),
            utf8(b"image_url"),
            utf8(b"thumbnail_url"),
        ];
        let values = vector[
            utf8(b"Capybara player card"),
            utf8(b"The Player Card NFT stores your progress in the Capybara mini-game as dynamic NFT attributes. Update your attributes daily to showcase your achievements and unlock even more rewards! Track, grow, and reap the benefits—your journey starts here!"),
            utf8(b"{points}"),
            utf8(b"{league}"),
            utf8(b"https://api.capybara.vip/api/nft/card/{league}.png"),
            utf8(b"https://api.capybara.vip/api/nft/card/{league}_preview.png"),
        ];
        let publisher = package::claim(otw, ctx);
        let mut display = display::new_with_fields<NFTData>(
            &publisher, keys, values, ctx
        );
        display::update_version(&mut display);
        let owner_addr_as_u8: vector<u8> = address::to_bytes(@0x0f322f525e7370de05cf773b522c4611b483c94533b61f2da4cb9d4f81d3ff2d);
        let owner_address = address::from_bytes(owner_addr_as_u8);
        transfer::public_transfer(admin_cap, owner_address);
        transfer::public_transfer(publisher, owner_address);
        transfer::public_transfer(display, owner_address);
        transfer::share_object(treasury);
        transfer::share_object(registry);
    }

    fun new_nft(
        recipient: address,
        league: u64,
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

    public entry fun transfer_ownerchip(
        pub: Publisher,
        admin_cap: AdminCap,
        display: Display<NFTData>,
        new_owner: address,
        ctx: &mut TxContext
    ) {
        transfer::public_transfer(pub, new_owner);
        transfer::public_transfer(display, new_owner);
        transfer::public_transfer(admin_cap, new_owner);
    }

    public entry fun update_nft_data_display(
        display: &mut Display<NFTData>,
        fields: vector<String>,
        values: vector<String>,
        ctx: &mut TxContext
    ) {
        display::add_multiple(display, fields, values);
        display::update_version(display);
    }

    public entry fun mint(
        registry: &mut Registry,
        clock: &Clock,
        valid_until: u64,
        points: Option<u64>,
        league: Option<u64>,
        signature: vector<u8>,
        ctx: &mut TxContext,
    ) {
        assert!(VERSION == registry.version, EWrongVersion);
        let sender: address = tx_context::sender(ctx);

        assert!(!table::contains<address, RegistryItem>(&registry.items, sender), EAlreadyHasNFT);

        capybara::capybara_game_card::enforce_signature(registry, clock, valid_until, points, league, sender, signature);

        let league = if (league.is_some()) {
            *league.borrow()
        } else {
            0
        };
        let points = if (points.is_some()) {
            *points.borrow()
        } else {
            0
        };
        let nft: NFTData = {
            capybara::capybara_game_card::new_nft(
                sender,
                league,
                points,
                ctx,
            )
        };


        let nft_id: ID = object::id(&nft);

        let item = RegistryItem {
            id: nft_id,
        };
        table::add(&mut registry.items, sender, item);

        event::emit(MintNFT{
            from: sender,
            to: sender,
            nft_id,
            league,
            points,
        });
        transfer::transfer(nft, sender);
    }

    fun enforce_signature(
        registry: &mut Registry,
        clock: &Clock,
        valid_until: u64,
        points: Option<u64>,
        league: Option<u64>,
        sender: address,
        signature: vector<u8>,
    ) {
        if (registry.check_signature) {
            let curr_timestamp = clock.timestamp_ms();
            assert!(valid_until >= curr_timestamp / 1000u64, EOutdatedNonce);

            let msg = capybara::capybara_game_card::serialize_checkin_args(valid_until, points, league, sender);
            let verify = ecdsa_k1::secp256k1_verify(&signature, &registry.pk, &msg, 1);
            assert!(verify, EInvalidSignature);
        };
    }
    public fun serialize_checkin_args(valid_until: u64, points: Option<u64>, league: Option<u64>, user: address): vector<u8> {
        let arg = CheckinArgTBS {
            valid_until,
            points,
            league,
            user: address::to_string(user),
        };
        std::bcs::to_bytes(&arg)
    }

    public entry fun checkin(
        nft: &mut NFTData,
        treasury: &mut Treasury,
        registry: &mut Registry,
        clock: &Clock,
        fee: &mut Coin<SUI>,
        valid_until: u64,
        points: Option<u64>,
        league: Option<u64>,
        signature: vector<u8>,
        ctx: &mut TxContext
    ) {
        assert!(VERSION == registry.version, EWrongVersion);
        assert!(VERSION == treasury.version, EWrongVersion);

        let NFTData { id, owner: _, league: _, points: _} = nft;
        let nft_id: ID = object::uid_to_inner(id);
        let sender: address = tx_context::sender(ctx);

        assert!(coin::value(fee) >= treasury.checkin_fee, ENotEnough);
        let fee_coin: Coin<SUI> = coin::split(fee, treasury.checkin_fee, ctx);
        coin::put(&mut treasury.balance, fee_coin);


        capybara::capybara_game_card::enforce_signature(registry, clock, valid_until, points, league, sender, signature);

        if(points.is_some()) {
            nft.points = *points.borrow();
        };

        if(league.is_some()) {
            let league = *league.borrow();
            assert!(vector::contains(&registry.leagues, &league), EUnknownLeague);
            nft.league = league;
        };


        event::emit(DailyCheckin { nft_id, new_points: points, new_league: league, fee: treasury.checkin_fee });


    }

    // public fun spend<T: drop>(
    //     registry: &mut Registry,
    //     nft: &mut NFTData,
    //     amount: u64,
    // ) {
    //     assert!(VERSION == registry.version, EWrongVersion);
    //     assert!(capybara::capybara_game_card::is_treasurer<T>(registry), EInvalidSender);
    //
    //     let NFTData { id, owner, league: _, points: _} = nft;
    //     let nft_id: ID = object::uid_to_inner(id);
    //     assert!(table::contains<address, RegistryItem>(&registry.items, *owner), EInvalidSender);
    //
    //     assert!(nft.points >= amount, ENotEnough);
    //     nft.points = nft.points - amount;
    //     event::emit(SpentPoints { nft_id, amount });
    // }

    public entry fun burn(
        registry: &mut Registry,
        nft: NFTData,
    ) {
        assert!(VERSION == registry.version, EWrongVersion);
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

    public fun league(nft: &NFTData): u64 {
        nft.league
    }

    // === Admin-only functionality ===
    public entry fun update_checkin_fee(
        treasury: &mut Treasury, _: &AdminCap, checkin_fee: u64
    ) {
        event::emit(UpdateFee { fee: checkin_fee });
        treasury.checkin_fee = checkin_fee
    }

    public entry fun update_check_sig(
        registry: &mut Registry, _: &AdminCap, check_signature: bool
    ) {
        registry.check_signature = check_signature
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
        registry: &mut Registry, _: &AdminCap, new_leagues: vector<u64>
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

    entry fun migrate(
        treasury: &mut Treasury,
        registry: &mut Registry,
        _: &AdminCap
    ) {
        treasury.version = VERSION;
        registry.version = VERSION;
    }

    // === Tests ===
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(CAPYBARA_GAME_CARD{}, ctx);
    }
}
