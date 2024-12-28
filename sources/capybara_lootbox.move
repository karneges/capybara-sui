/// Module: capybara
module capybara::capybara_lootbox {
    use std::string::{String, utf8};
    use std::vector;
    use capybara::capybara_game_card::AdminCap;
    use sui::address;
    use sui::balance;
    use sui::balance::Balance;
    use sui::clock::Clock;
    use sui::coin;
    use sui::coin::Coin;
    use sui::display;
    use sui::ecdsa_k1;
    use sui::event;
    use sui::object;
    use sui::object::UID;
    use sui::package;
    use sui::random::{Random, new_generator, generate_u8_in_range};
    use sui::sui::SUI;
    use sui::table;
    use sui::table::Table;
    use sui::transfer;
    use sui::tx_context::TxContext;

    use ob_utils::utils;
    use nft_protocol::tags;
    use nft_protocol::mint_event;
    use nft_protocol::royalty;
    use nft_protocol::creators;
    use nft_protocol::transfer_allowlist;
    use nft_protocol::p2p_list;
    use ob_utils::display as ob_display;
    use nft_protocol::collection;
    use nft_protocol::mint_cap::{Self, MintCap};
    use nft_protocol::royalty_strategy_bps;
    use ob_permissions::witness;

    use ob_request::transfer_request;
    use ob_request::borrow_request::{Self, BorrowRequest, ReturnPromise};
    use ob_kiosk::ob_kiosk;

    /// One-Time-Witness for the module.
    public struct CAPYBARA_LOOTBOX has drop {}
    /// Can be used for authorization of other actions post-creation. It is
    /// vital that this struct is not freely given to any contract, because it
    /// serves as an auth token.
    public struct Witness has drop {}
    /// Structs
    public struct LootBoxAdminCap has key, store { id: UID }
    public struct LootboxArgTBS has drop {
        user: String,
        uid: u64,
        valid_until: u64,
        count: u64,
    }

    public struct DataStorage has key {
        id: UID,
        total_lootbox: u64,
        total_lootbox_opened: u64,
        ids: Table<u64, bool>,
        pk: vector<u8>,
        check_signature: bool,
    }
    public struct NFTLootbox has key, store {
        id: UID,
        idx: u64,
    }

    // === Errors ===
    const ENotEnough: u64 = 100;
    const EInvalidSender: u64 = 102;
    const EAlreadyUsed: u64 = 103;
    const EInvalidSignature: u64 = 104;
    const EOutdatedNonce: u64 = 105;


    // === Events ===
    public struct MintLootbox has copy, drop {
        from: address,
        lootboxes: vector<ID>,
        lootbox_idxs: vector<u64>,
        random_id: u64,
    }
    public struct OpenLootbox has copy, drop {
        from: address,
        lootbox_id: ID,
        lootbox_idx: u64,
        reward: u64,
    }


    fun init(otw: CAPYBARA_LOOTBOX, ctx: &mut TxContext) {
        // 1. Init Collection & MintCap with unlimited supply
        let (mut collection, mint_cap) = collection::create_with_mint_cap<CAPYBARA_LOOTBOX, NFTLootbox>(
            &otw, option::none(), ctx
        );
        // 2. Init Publisher & Delegated Witness
        let publisher = sui::package::claim(otw, ctx);
        let dw = witness::from_witness(Witness {});

        // 3. Init Display
        let tags = vector[tags::art(), tags::collectible()];

        let mut display = display::new<NFTLootbox>(&publisher, ctx);
        display::add(&mut display, utf8(b"name"), utf8(b"{name}"));
        display::add(&mut display, utf8(b"tags"), ob_display::from_vec(tags));
        display::add(&mut display, utf8(b"collection_id"), ob_display::id_to_string(&object::id(&collection)));
        display::update_version(&mut display);
        transfer::public_transfer(display, tx_context::sender(ctx));

        // === COLLECTION DOMAINS ===

        // 4. Add Creator metadata to the collection

        // Insert Creator addresses here
        let creators = vector[
            @0x0f322f525e7370de05cf773b522c4611b483c94533b61f2da4cb9d4f81d3ff2d
        ];

        collection::add_domain(
            dw,
            &mut collection,
            creators::new(utils::vec_set_from_vec(&creators)),
        );

        // 5. Setup royalty basis points
        // 2_000 BPS == 20%
        let shares = vector[10_000];
        let shares = utils::from_vec_to_map(creators, shares);

        royalty_strategy_bps::create_domain_and_add_strategy(
            dw, &mut collection, royalty::from_shares(shares, ctx), 100, ctx,
        );

        // === TRANSFER POLICIES ===

        // 6. Creates a new policy and registers an allowlist rule to it.
        // Therefore now to finish a transfer, the allowlist must be included
        // in the chain.
        let (mut transfer_policy,mut transfer_policy_cap) =
            transfer_request::init_policy<NFTLootbox>(&publisher, ctx);

        royalty_strategy_bps::enforce(&mut transfer_policy, &transfer_policy_cap);
        transfer_allowlist::enforce(&mut transfer_policy, &transfer_policy_cap);

        // 7. P2P Transfers are a separate transfer workflow and therefore require a
        // separate policy
        // let (p2p_policy, p2p_policy_cap) =
        //     transfer_request::init_policy<NFTLootbox>(&publisher, ctx);
        //
        // p2p_list::enforce(&mut p2p_policy, &p2p_policy_cap);

        /// lootbox display config
        let lootbox_keys = vector[
            utf8(b"name"),
            utf8(b"description"),
            utf8(b"image_url"),
            utf8(b"thumbnail_url"),
        ];
        let lootbox_values = vector[
            utf8(b"Money Bag"),
            utf8(b"Unlock the mystery! This Money Bag NFT contains a hidden number of in-game coins—open it to reveal your reward! The more you open, the more you can grow your coin balance. Start unlocking your Money Bags today!"),
            utf8(b"https://api.capybara.vip/api/nft/bag"),
            utf8(b"https://api.capybara.vip/api/nft/bag"),
        ];
        let mut lootbox_dispaly = display::new_with_fields<NFTLootbox>(
            &publisher, lootbox_keys, lootbox_values, ctx
        );
        display::update_version(&mut lootbox_dispaly);



        let owner_addr_as_u8: vector<u8> = address::to_bytes(@0x0f322f525e7370de05cf773b522c4611b483c94533b61f2da4cb9d4f81d3ff2d);
        let owner_address = address::from_bytes(owner_addr_as_u8);

        let data_storage = DataStorage {
            id: object::new(ctx),
            total_lootbox: 0,
            total_lootbox_opened: 0,
            ids: table::new(ctx),
            pk: x"031d9cd3748b019a247773cae4c6e34abba70ba9fd25f86fff1595b012337d3150",
            check_signature: true,
        };
        transfer::share_object(data_storage);
        transfer::public_transfer(publisher, owner_address);
        transfer::public_transfer(lootbox_dispaly, owner_address);


        transfer::public_transfer(mint_cap, owner_address);
        transfer::public_transfer(transfer_policy_cap, owner_address);
        // transfer::public_transfer(p2p_policy_cap, owner_address);
        transfer::public_share_object(collection);
        transfer::public_share_object(transfer_policy);
        // transfer::public_share_object(p2p_policy);


    }

    public fun update_storage(
        _: &AdminCap,
        pk: vector<u8>,
        check_signature: bool,
        data_storage: &mut DataStorage,
        ctx: &mut TxContext
    ) {
        data_storage.pk = pk;
        data_storage.check_signature = check_signature;
    }

    public fun serialize_lootbox_args(user: address, uid: u64, valid_until: u64, count: u64): vector<u8> {
        let arg = LootboxArgTBS {
            uid,
            user: address::to_string(user),
            valid_until,
            count
        };
        std::bcs::to_bytes(&arg)
    }

    public  fun mint_lootbox(
        data_storage: &mut DataStorage,
        clock: &Clock,
        uid: u64,
        valid_until: u64,
        count: u64,
        signature: vector<u8>,
        // user_kiosk:&mut sui::kiosk::Kiosk,
        ctx: &mut TxContext
    ) {
        let sender: address = tx_context::sender(ctx);

        if (data_storage.check_signature) {
            let curr_timestamp = clock.timestamp_ms();
            assert!(valid_until >= curr_timestamp / 1000u64, EOutdatedNonce);
            assert!(!table::contains<u64, bool>(&data_storage.ids, uid), EAlreadyUsed);

            let msg = capybara::capybara_lootbox::serialize_lootbox_args(sender, uid, valid_until, count);
            let verify = ecdsa_k1::secp256k1_verify(&signature, &data_storage.pk, &msg, 1);
            assert!(verify, EInvalidSignature);
        };

        table::add(&mut data_storage.ids, uid, true);
        let mut count = count;
        let mut lootboxes = vector::empty();
        let mut lootbox_ids = vector::empty();
        while (count > 0) {
            data_storage.total_lootbox = data_storage.total_lootbox + 1;
            let lootbox = capybara::capybara_lootbox::new_lootbox(ctx, data_storage.total_lootbox);

            lootboxes.push_back(object::id(&lootbox));
            lootbox_ids.push_back(lootbox.idx);
            // if (user_kiosk.is_some()) {
            //     ob_kiosk::deposit<NFTLootbox>(user_kiosk.borrow(), lootbox, ctx);
            // } else {
                let (mut v0,_) = ob_kiosk::new_for_address(sender, ctx);
                ob_kiosk::deposit<NFTLootbox>(&mut v0, lootbox, ctx);
                transfer::public_share_object<sui::kiosk::Kiosk>(v0);
            // };
            // ob_kiosk::deposit<NFTLootbox>(user_kiosk, lootbox, ctx);


            count = count - 1;
        };

        event::emit(MintLootbox {
            from: sender,
            lootboxes,
            lootbox_idxs: lootbox_ids,
            random_id: uid,
        });


    }

    fun new_lootbox(ctx: &mut TxContext, idx: u64): NFTLootbox {
        NFTLootbox {
            id: object::new(ctx),
            idx
        }
    }

    public entry fun open_lootbox(
        data_storage: &mut DataStorage,
        r: &Random,
        lootbox: NFTLootbox,
        ctx: &mut TxContext
    ) {
        let sender: address = tx_context::sender(ctx);
        let lootboxID = object::id(&lootbox);
        let NFTLootbox {
            id: lootbox_id,
            idx: lootbox_idx
        } = lootbox;
        object::delete(lootbox_id);
        data_storage.total_lootbox_opened = data_storage.total_lootbox_opened + 1;
        let reward = capybara::capybara_lootbox::get_random_reward(r, ctx);

        event::emit(OpenLootbox {
            from: sender,
            lootbox_id: lootboxID,
            lootbox_idx,
            reward
        });
    }

    fun get_random_reward(r: &Random, ctx: &mut TxContext): u64 {
        //transfer
        let mut generator = new_generator(r, ctx);
        let random_value = generate_u8_in_range(&mut generator, 0, 100);

        let mut reward = 0;
        if (random_value <= 10) {
            reward = 15_000_000;
        };

        if (random_value > 10 && random_value <= 25) {
            reward = 7_500_000;
        };

        if (random_value > 25 && random_value <= 55) {
            reward = 6_000_000;
        };

        if (random_value > 55 && random_value <= 80) {
            reward = 5_000_000;
        };

        if (random_value > 80 && random_value <= 100) {
            reward = 4_000_000;
        };
        return reward
    }

}
