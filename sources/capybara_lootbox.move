/// Module: capybara
#[test_only]
module capybara::capybara_lootbox {
    use std::string::{String, utf8};
    use capybara::capybara_game_card::AdminCap;
    use sui::address;
    use sui::balance;
    use sui::balance::Balance;
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

    /// One-Time-Witness for the module.
    public struct CAPYBARA_LOOTBOX has drop {}
    /// Structs
    public struct LootBoxAdminCap has key, store { id: UID }
    public struct LootboxArgTBS has drop {
        user: address,
        uid: u64,
    }

    public struct DataStorage has key {
        id: UID,
        total_lootbox: u64,
        total_lootbox_opened: u64,
        total_fruit_minted: u64,
        total_fruit_exchanged: u64,
        total_capybara: u64,
        ids: Table<u64, bool>,
        pk: vector<u8>,
        check_signature: bool,
    }
    public struct NFTFruit has key, store {
        id: UID,
        idx: u64,
        fruit_type: String,
    }

    public struct NFTLootbox has key, store {
        id: UID,
        idx: u64,
    }

    public struct CapybaraNFT has key, store {
        id: UID,
        idx: u64,
    }
    // === Errors ===
    const ENotEnough: u64 = 100;
    const EInvalidSender: u64 = 102;
    const EAlreadyUsed: u64 = 103;
    const EInvalidSignature: u64 = 104;

    // === Events ===
    public struct MintLootbox has copy, drop {
        from: address,
        lootbox_id: ID,
        lootbox_idx: u64,
    }
    public struct OpenLootbox has copy, drop {
        from: address,
        lootbox_id: ID,
        lootbox_idx: u64,
        fruit_id: ID,
        fruit_idx: u64,
    }
    public struct AdminMintFruit has copy, drop {
        fruit_id: ID,
        fruit_idx: u64,
    }

    public struct MintCapybara has copy, drop {
        from: address,
        nft_id: ID,
        nft_idx: u64,
    }

    fun init(otw: CAPYBARA_LOOTBOX, ctx: &mut TxContext) {
        let publisher = package::claim(otw, ctx);

        /// fruits display config
        let fruits_keys = vector[
            utf8(b"name"),
            utf8(b"image_url"),
            utf8(b"thumbnail_url"),
        ];
        let fruits_values = vector[
            utf8(b"Capybara NFT {fruit_type} fruit"),
            utf8(b"https://capybara_static.8gen.team/{fruit_type}.png"),
            utf8(b"https://capybara_static.8gen.team/{fruit_type}_preview.png"),
        ];

        let mut fruits_dispaly = display::new_with_fields<NFTFruit>(
            &publisher, fruits_keys, fruits_values, ctx
        );
        display::update_version(&mut fruits_dispaly);

        /// lootbox display config
        let lootbox_keys = vector[
            utf8(b"name"),
            utf8(b"image_url"),
            utf8(b"thumbnail_url"),
        ];
        let lootbox_values = vector[
            utf8(b"Capybara NFT Lootbox number {idx}"),
            utf8(b"https://capybara_static.8gen.team/lootbox.png"),
            utf8(b"https://capybara_static.8gen.team/lootbox_preview.png"),
        ];
        let mut lootbox_dispaly = display::new_with_fields<NFTLootbox>(
            &publisher, lootbox_keys, lootbox_values, ctx
        );
        display::update_version(&mut lootbox_dispaly);

        /// Capybara display config
        let capybara_keys = vector[
            utf8(b"name"),
            utf8(b"image_url"),
            utf8(b"thumbnail_url"),
        ];
        let capybara_values = vector[
            utf8(b"Capybara NFT {idx}"),
            utf8(b"https://capybara_static.8gen.team/capybara.png"),
            utf8(b"https://capybara_static.8gen.team/capybara_preview.png"),
        ];
        let mut capybara_dispaly = display::new_with_fields<CapybaraNFT>(
            &publisher, capybara_keys, capybara_values, ctx
        );
        display::update_version(&mut capybara_dispaly);
        let owner_addr_as_u8: vector<u8> = address::to_bytes(@0x3a1a0722453ff6da8a9695ef9588bd0ef57e60df8eee12f45cb792a170f179e1);
        let owner_address = address::from_bytes(owner_addr_as_u8);

        let data_storage = DataStorage {
            id: object::new(ctx),
            total_lootbox: 0,
            total_lootbox_opened: 0,
            total_fruit_minted: 0,
            total_fruit_exchanged: 0,
            total_capybara: 0,
            ids: table::new(ctx),
            pk: x"035229dff81f3e3f5a1526b92908752395d96bf6b41cc253b2ad5bebe503149cf2",
            check_signature: false,
        };
        let admin_cap = LootBoxAdminCap {
            id: object::new(ctx),
        };
        transfer::share_object(data_storage);
        transfer::public_transfer(admin_cap, owner_address);
        transfer::public_transfer(publisher, owner_address);
        transfer::public_transfer(fruits_dispaly, owner_address);
        transfer::public_transfer(lootbox_dispaly, owner_address);
        transfer::public_transfer(capybara_dispaly, owner_address);
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

    public fun serialize_lootbox_args(user: address, uid: u64): vector<u8> {
        let arg = LootboxArgTBS {
            uid,
            user
        };
        std::bcs::to_bytes(&arg)
    }

    public entry fun mint_lootbox(
        data_storage: &mut DataStorage,
        uid: u64,
        signature: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender: address = tx_context::sender(ctx);

        if (data_storage.check_signature) {
            assert!(!table::contains<u64, bool>(&data_storage.ids, uid), EAlreadyUsed);

            let msg = capybara::capybara_lootbox::serialize_lootbox_args(sender, uid);
            let verify = ecdsa_k1::secp256k1_verify(&signature, &data_storage.pk, &msg, 1);
            assert!(verify, EInvalidSignature);
        };

        data_storage.total_lootbox = data_storage.total_lootbox + 1;
        let lootbox = capybara::capybara_lootbox::new_lootbox(ctx, data_storage.total_lootbox);

        table::add(&mut data_storage.ids, uid, true);
        event::emit(MintLootbox {
            from: sender,
            lootbox_id: object::id(&lootbox),
            lootbox_idx: lootbox.idx,
        });
        transfer::public_transfer(lootbox, sender);
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
        data_storage.total_fruit_minted = data_storage.total_fruit_minted + 1;
        let fruit = capybara::capybara_lootbox::get_random_fruit(r,data_storage.total_fruit_minted, ctx);

        event::emit(OpenLootbox {
            from: sender,
            lootbox_id: lootboxID,
            lootbox_idx: lootbox_idx,
            fruit_id: object::id(&fruit),
            fruit_idx: fruit.idx,
        });
        transfer::public_transfer(fruit, sender);
    }

    fun get_random_fruit(r: &Random, fruit_idx: u64, ctx: &mut TxContext): NFTFruit {
        //transfer
        let mut generator = new_generator(r, ctx);
        let random_value = generate_u8_in_range(&mut generator, 0, 200);

        let mut fruit_type = b"";
        if (random_value <= 3) {
            fruit_type = b"Mushroom";
        };

        if (random_value > 3 && random_value <= 20) {
            fruit_type = b"Watermelon";
        };

        if (random_value > 20 && random_value <= 50) {
            fruit_type = b"Banana";
        };

        if (random_value > 50 && random_value <= 100) {
            fruit_type = b"Strawberry";
        };

        if (random_value > 100 && random_value <= 200) {
            fruit_type = b"Lemon";
        };



        NFTFruit {
            id: object::new(ctx),
            idx: fruit_idx,
            fruit_type: fruit_type.to_string(),
        }
    }

    public fun mint_fruit_by_admin(
        _: &AdminCap,
        data_storage: &mut DataStorage,
        fruit_types: vector<String>,
        ctx: &mut TxContext
    ) {
        let sender: address = tx_context::sender(ctx);

        let mut i = 0;
        while (i < fruit_types.length()) {
            data_storage.total_fruit_minted = data_storage.total_fruit_minted + 1;
            let fruit = NFTFruit {
                id: object::new(ctx),
                idx: data_storage.total_fruit_minted,
                fruit_type: fruit_types[i],
            };
            event::emit(AdminMintFruit {
                fruit_id: object::id(&fruit),
                fruit_idx: fruit.idx,
            });
            transfer::public_transfer(fruit, sender);
            i = i + 1;
        }
        // let fruit = NFTFruit {
        //     id: object::new(ctx),
        //     idx: data_storage.total_fruit_minted,
        //     fruit_type,
        // };
        // transfer::public_transfer(fruit, sender);
    }
    public fun exchange_fruits_to_capybara(
        data_storage: &mut DataStorage,
        lemon: NFTFruit,
        strawberry: NFTFruit,
        banana: NFTFruit,
        watermelon: NFTFruit,
        mushroom: NFTFruit,
        ctx: &mut TxContext
    ) {
        let sender: address = tx_context::sender(ctx);
        let NFTFruit {
            id: lemon_id,
            fruit_type: lemon_type,
            idx: _
        } = lemon;
        assert!(lemon_type == std::string::utf8(b"Lemon"), 3);

        let NFTFruit {
            id: strawberry_id,
            fruit_type: strawberry_type,
            idx: _
        } = strawberry;
        assert!(strawberry_type == std::string::utf8(b"Strawberry"), 3);

        let NFTFruit {
            id: banana_id,
            fruit_type: banana_type,
            idx: _
        } = banana;
        assert!(banana_type == std::string::utf8(b"Banana"), 3);

        let NFTFruit {
            id: watermelon_id,
            fruit_type: watermelon_type,
            idx: _
        } = watermelon;
        assert!(watermelon_type == std::string::utf8(b"Watermelon"), 3);

        let NFTFruit {
            id: mushroom_id,
            fruit_type: mushroom_type,
            idx: _
        } = mushroom;

        assert!(mushroom_type == std::string::utf8(b"Mushroom"), 3);



        object::delete(lemon_id);
        object::delete(strawberry_id);
        object::delete(banana_id);
        object::delete(watermelon_id);
        object::delete(mushroom_id);
        //
        data_storage.total_fruit_exchanged = data_storage.total_fruit_exchanged + 5;
        data_storage.total_capybara = data_storage.total_capybara + 1;
        let capybara = CapybaraNFT {
            id: object::new(ctx),
            idx: data_storage.total_capybara,
        };
        event::emit(MintCapybara {
            from: sender,
            nft_id: object::id(&capybara),
            nft_idx: capybara.idx,
        });
        transfer::public_transfer(capybara, sender);

    }

}
