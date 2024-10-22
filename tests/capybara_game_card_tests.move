/*
#[test_only]
module capybara::capybara_tests {
    // uncomment this line to import the module
    // use capybara::capybara;

    const ENotImplemented: u64 = 0;

    #[test]
    fun test_capybara() {
        // pass
    }

    #[test, expected_failure(abort_code = ::capybara::capybara_tests::ENotImplemented)]
    fun test_capybara_fail() {
        abort ENotImplemented
    }
}
*/


#[test_only] 
module capybara::capybara_game_card_tests {
    use sui::test_scenario as ts;
    use std::debug;
    use std::string::{Self, utf8, String};
    use sui::event::{Self};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::sui::SUI;
    use sui::ecdsa_k1;
    use sui::package;
    use sui::display;
    use capybara::capybara_game_card::{Self, Treasury, Registry, NFTData, AdminCap};
    use capybara::capybara_dummy_portal::{Self};

    const ENotImplemented: u64 = 0;
    const DefaultSK: vector<u8> = x"9bf49a6a0755f953811fce125f2683d50429c3bb49e074147e0089a52eae155f";
    const DefaultPK: vector<u8> = x"029bef8d556d80e43ae7e0becb3a7e6838b95defe45896ed6075bb9035d06c9964";
    const SecondSK: vector<u8> = x"c5e26f9b31288c268c31217de8d2a783eec7647c2b8de48286f0a25a2dd6594b";
    const SecondPK: vector<u8> = x"027f5fc5283d80756a59b00ab26d2ea914f5d3d35deae839af8806e8f042dd0668";

    #[test_only]
    fun update_config(
        ts: &mut ts::Scenario,
        admin: address,
        new_fee: Option<u64>,
        new_pk: Option<vector<u8>>,
        new_leagues: Option<vector<String>>,
    ) {
        ts.next_tx(admin);

        {
            let admin_cap = ts::take_from_sender<AdminCap>(ts);
            if(new_fee.is_some()) {
                let value = option::destroy_some(new_fee);
                let mut treasury: Treasury = ts.take_shared();
                capybara_game_card::update_checkin_fee(
                    &mut treasury,
                    &admin_cap,
                    value,
                );
                ts::return_shared(treasury);
            } else if(new_pk.is_some()) {
                let value = option::destroy_some(new_pk);
                let mut registry: Registry = ts.take_shared();
                capybara_game_card::update_pk(
                    &mut registry,
                    &admin_cap,
                    value,
                );
                ts::return_shared(registry);
            } else if(new_leagues.is_some()) {
                let value = option::destroy_some(new_leagues);
                let mut registry: Registry = ts.take_shared();
                capybara_game_card::update_leagues(
                    &mut registry,
                    &admin_cap,
                    value,
                );
                ts::return_shared(registry);
            };
            ts.return_to_sender(admin_cap);
        };
    }

    #[test_only]
    fun withdraw(
        ts: &mut ts::Scenario,
        admin: address,
        amount: Option<u64>,
    ) {
        ts.next_tx(admin);

        {
            let mut treasury: Treasury = ts.take_shared();
            let admin_cap = ts::take_from_sender<AdminCap>(ts);
            let ctx = ts.ctx();
            capybara_game_card::withdraw(
                &mut treasury,
                &admin_cap,
                amount,
                ctx,
            );
            ts.return_to_sender(admin_cap);
            ts::return_shared(treasury);
        };
    }

    #[test_only]
    fun grant_portal<T>(
        ts: &mut ts::Scenario,
        admin: address,
    ) {
        ts.next_tx(admin);

        {
            let mut registry: Registry = ts.take_shared();
            let admin_cap = ts::take_from_sender<AdminCap>(ts);
            capybara_game_card::grant_treasurer_cap<T>(
                &admin_cap,
                &mut registry,
            );
            ts.return_to_sender(admin_cap);
            ts::return_shared(registry);
        };
    }

    #[test_only]
    fun claim(
        ts: &mut ts::Scenario,
        user: address,
        amount: u64,
    ) {
        ts.next_tx(user);

        {
            let mut registry: Registry = ts.take_shared();
            let mut nft = ts.take_from_address<NFTData>(user);
            capybara_dummy_portal::claim(
                &mut registry,
                &mut nft,
                amount,
            );
            ts::return_shared(registry);
            ts::return_to_address(user, nft);
        };
    }

    #[test_only]
    fun burn(ts: &mut ts::Scenario, user: address) {
        ts.next_tx(user);

        {
            let mut registry: Registry = ts.take_shared();
            let nft = ts.take_from_address<NFTData>(user);
            capybara_game_card::burn(
                &mut registry,
                nft,
            );
            ts::return_shared(registry);
        };
    }

    #[test_only]
    fun mint(ts: &mut ts::Scenario, user: address) {
        ts.next_tx(user);

        // mint
        {
            let mut registry: Registry = ts.take_shared();
            let ctx = ts.ctx();

            capybara_game_card::mint(
                &mut registry,
                user,
                ctx,
            );

            ts::return_shared(registry);
        };
    }

    #[test_only]
    fun checkin(
        ts: &mut ts::Scenario,
        user: address,
        fee: u64,
        valid_signature: bool,
        nonce: u64,
        new_points: Option<u64>,
        new_league: Option<String>,
        sk: vector<u8>,
    ) {
        ts.next_tx(user);

        {
            let mut treasury: Treasury = ts.take_shared();
            let mut registry: Registry = ts.take_shared();
            let mut nft = ts.take_from_address<NFTData>(user);
            let ctx = ts.ctx();
            let mut coin = coin::mint_for_testing<SUI>(fee, ctx);
            let msg = capybara_game_card::serialize_checkin_args(nonce, new_points, new_league);
            let mut signature = ecdsa_k1::secp256k1_sign(&sk, &msg, 1, false);
            if(!valid_signature) {
                vector::reverse(&mut signature);
            };
            capybara_game_card::checkin(
                &mut nft,
                &mut treasury,
                &mut registry,
                &mut coin,
                nonce,
                new_points,
                new_league,
                signature,
                ctx
            );
            coin::burn_for_testing(coin);
            ts::return_shared(treasury);
            ts::return_shared(registry);
            ts::return_to_address(user, nft);
        };
    }

    #[test]
    #[expected_failure(abort_code = capybara_game_card::EAlreadyHasNFT)]
    fun test_twice_mint() {
        let (admin, player1) = (@0x2, @0x3);


        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
        };


        // mint
        mint(&mut scenario, player1);

        // mint second time, should fail
        mint(&mut scenario, player1);


        scenario.end();
    }

    #[test]
    fun test_mint() {
        let (admin, player1) = (@0x2, @0x3);


        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
        };

        let prev_tx = scenario.next_tx(player1);

        let created_ids = prev_tx.created();
        let shared_ids = prev_tx.shared();
        let sent_ids = prev_tx.transferred_to_account();
        let events_num = prev_tx.num_user_events();

        assert!(created_ids.length() == 5, 0);
        assert!(shared_ids.length() == 2, 1);
        assert!(sent_ids.size() == 3, 2);
        assert!(events_num == 2, 3);

        mint(&mut scenario, player1);

        scenario.next_tx(player1);

        {
            let nft = scenario.take_from_sender<NFTData>();
            assert!(capybara_game_card::points(&nft) == 0);
            assert!(capybara_game_card::league(&nft) == utf8(b"Starving"));
            scenario.return_to_sender(nft);
        };

        scenario.end();
    }

    #[test]
    fun test_checkin_with_valid_signature() {
        let (admin, player1) = (@0x2, @0x3);


        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
        };


        mint(&mut scenario, player1);

        checkin(&mut scenario, player1, 300_000_000, true, 0, option::some(1), option::none(), DefaultSK);

        scenario.next_tx(player1);
        {
            let nft = scenario.take_from_sender<NFTData>();
            assert!(capybara_game_card::points(&nft) == 1);
            assert!(capybara_game_card::league(&nft) == utf8(b"Starving"));
            scenario.return_to_sender(nft);
        };

        checkin(&mut scenario, player1, 300_000_000, true, 1, option::some(2), option::some(b"Full".to_string()), DefaultSK);

        scenario.next_tx(player1);
        {
            let nft = scenario.take_from_sender<NFTData>();
            assert!(capybara_game_card::points(&nft) == 2);
            assert!(capybara_game_card::league(&nft) == utf8(b"Full"));
            scenario.return_to_sender(nft);
        };


        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = capybara_game_card::ENotEnough)]
    fun test_checkin_with_lower_fee() {
        let (admin, player1) = (@0x2, @0x3);


        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
        };


        mint(&mut scenario, player1);

        checkin(&mut scenario, player1, 300_000_000 - 1, true, 0, option::some(1), option::none(), DefaultSK);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = capybara_game_card::EInvalidSignature)]
    fun test_checkin_with_invalid_signature() {
        let (admin, player1) = (@0x2, @0x3);


        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
        };

        mint(&mut scenario, player1);

        checkin(&mut scenario, player1, 300_000_000, false, 0, option::some(1), option::none(), DefaultSK);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = capybara_game_card::EInvalidSender)]
    fun test_spend_points_with_wrong_grant() {
        let (admin, player1) = (@0x2, @0x3);

        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
            capybara_dummy_portal::init_for_testing(scenario.ctx());
        };


        mint(&mut scenario, player1);

        checkin(&mut scenario, player1, 300_000_000, true, 0, option::some(1), option::none(), DefaultSK);

        grant_portal<capybara_game_card::CAPYBARA_GAME_CARD>(&mut scenario, admin);

        claim(&mut scenario, player1, 1);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = capybara_game_card::EInvalidSender)]
    fun test_spend_points_without_grant() {
        let (admin, player1) = (@0x2, @0x3);

        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
            capybara_dummy_portal::init_for_testing(scenario.ctx());
        };


        mint(&mut scenario, player1);

        checkin(&mut scenario, player1, 300_000_000, true, 0, option::some(1), option::none(), DefaultSK);

        claim(&mut scenario, player1, 1);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = capybara_game_card::EInvalidSender)]
    fun test_spend_points_direct() {
        let (admin, player1) = (@0x2, @0x3);

        // deploy
        let mut ts = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(ts.ctx());
            capybara_dummy_portal::init_for_testing(ts.ctx());
        };


        mint(&mut ts, player1);

        checkin(&mut ts, player1, 300_000_000, true, 0, option::some(1), option::none(), DefaultSK);
        
        ts.next_tx(player1);

        {
            let mut registry: Registry = ts.take_shared();
            let mut nft = ts.take_from_address<NFTData>(player1);
            capybara_game_card::spend<capybara_dummy_portal::CAPYBARA_DUMMY_PORTAL>(
                &mut registry,
                &mut nft,
                1,
            );
            ts::return_shared(registry);
            ts::return_to_address(player1, nft);
        };

        ts.end();
    }

    #[test]
    fun test_spend_points_from_dummy_portal() {
        let (admin, player1) = (@0x2, @0x3);

        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
            capybara_dummy_portal::init_for_testing(scenario.ctx());
        };


        mint(&mut scenario, player1);

        checkin(&mut scenario, player1, 300_000_000, true, 0, option::some(1), option::none(), DefaultSK);

        grant_portal<capybara_dummy_portal::CAPYBARA_DUMMY_PORTAL>(&mut scenario, admin);

        claim(&mut scenario, player1, 1);

        scenario.end();
    }

    #[test]
    fun test_change_fee() {
        let (admin, player1) = (@0x2, @0x3);


        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
            capybara_dummy_portal::init_for_testing(scenario.ctx());
        };


        update_config(&mut scenario, admin, option::some(100_000_000), option::none(), option::none());

        mint(&mut scenario, player1);

        checkin(&mut scenario, player1, 100_000_000, true, 0, option::some(1), option::none(), DefaultSK);

        scenario.end();
    }

    #[test]
    fun test_change_pk() {
        let (admin, player1) = (@0x2, @0x3);


        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
            capybara_dummy_portal::init_for_testing(scenario.ctx());
        };


        update_config(&mut scenario, admin, option::none(), option::some(SecondPK), option::none());

        mint(&mut scenario, player1);

        checkin(&mut scenario, player1, 300_000_000, true, 0, option::some(1), option::none(), SecondSK);

        scenario.end();
    }

    #[test]
    fun test_change_leagues() {
        let (admin, player1) = (@0x2, @0x3);

        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
        };


        let leagues: vector<String> = vector[
            b"XXX".to_string()
        ];
        update_config(&mut scenario, admin, option::none(), option::none(), option::some(leagues));

        mint(&mut scenario, player1);

        checkin(&mut scenario, player1, 300_000_000, true, 0, option::none(), option::some(b"XXX".to_string()), DefaultSK);

        scenario.end();
    }

    #[test]
    fun test_burn_and_mint_again() {
        let (admin, player1) = (@0x2, @0x3);


        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
        };

        mint(&mut scenario, player1);

        checkin(&mut scenario, player1, 300_000_000, true, 0, option::some(1), option::none(), DefaultSK);

        burn(&mut scenario, player1);

        mint(&mut scenario, player1);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = capybara_game_card::EOutdatedNonce)]
    fun test_checkin_with_outdated_nonce() {
        let (admin, player1) = (@0x2, @0x3);


        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
        };

        mint(&mut scenario, player1);

        checkin(&mut scenario, player1, 300_000_000, true, 0, option::some(1), option::none(), DefaultSK);

        checkin(&mut scenario, player1, 300_000_000, true, 0, option::some(1), option::none(), DefaultSK);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = capybara_game_card::EOutdatedNonce)]
    fun test_try_to_cheet_using_checkin_after_claim() {
        let (admin, player1) = (@0x2, @0x3);


        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
            capybara_dummy_portal::init_for_testing(scenario.ctx());
        };


        mint(&mut scenario, player1);

        checkin(&mut scenario, player1, 300_000_000, true, 0, option::some(1), option::none(), DefaultSK);

        grant_portal<capybara_dummy_portal::CAPYBARA_DUMMY_PORTAL>(&mut scenario, admin);

        claim(&mut scenario, player1, 1);

        checkin(&mut scenario, player1, 300_000_000, true, 1, option::some(2), option::none(), DefaultSK);

        scenario.end();
    }

    #[test]
    fun test_withdraw_by_admin() {
        let (admin, player1) = (@0x2, @0x3);


        // deploy
        let mut scenario = ts::begin(admin);
        {
            capybara_game_card::init_for_testing(scenario.ctx());
            capybara_dummy_portal::init_for_testing(scenario.ctx());
        };


        mint(&mut scenario, player1);

        checkin(&mut scenario, player1, 300_000_000, true, 0, option::some(1), option::none(), DefaultSK);

        withdraw(&mut scenario, admin, option::none());

        scenario.end();
    }
}
