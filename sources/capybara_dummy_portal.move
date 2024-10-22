/// Module: capybara
#[test_only]
module capybara::capybara_dummy_portal {
    use sui::event::{Self};
    use capybara::capybara_game_card::{Self, NFTData};

    // === Constants ===

    // === Types ===
    /// One-Time-Witness for the module.
    public struct CAPYBARA_DUMMY_PORTAL has drop {}

    // === Events ===
    public struct ClaimedPoints has copy, drop {
        amount: u64
    }

    // === Errors ===

    // === Functions ===
    fun init(_otw: CAPYBARA_DUMMY_PORTAL, _ctx: &mut TxContext) {
    }

    public fun claim(
        registry: &mut capybara_game_card::Registry,
        nft: &mut NFTData,
        amount: u64,
    ) {
        capybara_game_card::spend<CAPYBARA_DUMMY_PORTAL>(
            registry,
            nft,
            amount,
        );
        event::emit(ClaimedPoints {
            amount
        });
    }

    // === NFT Getter Functions ===

    // === Admin-only functionality ===

    // === Tests ===
    public fun init_for_testing(ctx: &mut TxContext) {
        init(CAPYBARA_DUMMY_PORTAL{}, ctx);
    }
}
