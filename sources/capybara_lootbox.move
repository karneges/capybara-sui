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
    use sui::transfer_policy;
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


    use sui::kiosk::KioskOwnerCap;

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
    /// Max value for the `amount_bp`.
    const MAX_BPS: u16 = 10_000;
    /// The Rule Witness to authorize the policy
    public struct Rule has drop {}
    /// Configuration for the Rule
    public struct Config has store, drop {
        /// Percentage of the transfer amount to be paid as royalty fee
        amount_bp: u16,
        /// This is used as royalty fee if the calculated fee is smaller than `min_amount`
        min_amount: u64,
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
        let publisher = package::claim(otw, ctx);

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
        let (mut tp,tp_cap) = transfer_policy::new<NFTLootbox>(&publisher,ctx);
        transfer_policy::add_rule(Rule {}, &mut tp, &tp_cap, Config { amount_bp: 1000, min_amount: 100_000 });
        transfer::share_object(data_storage);
        transfer::public_transfer(publisher, owner_address);
        transfer::public_transfer(lootbox_dispaly, owner_address);
        transfer::public_transfer(tp, owner_address);
        transfer::public_transfer(tp_cap, owner_address);




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
        user_kiosk:&mut sui::kiosk::Kiosk,
        cap: &KioskOwnerCap,
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
            sui::kiosk::place<capybara::capybara_lootbox::NFTLootbox>(user_kiosk, cap, lootbox);
            // transfer::public_transfer(lootbox, sender);

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
