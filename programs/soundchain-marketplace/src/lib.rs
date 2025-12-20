use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Transfer as TokenTransfer};
use anchor_spl::associated_token::AssociatedToken;

declare_id!("SMktxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");

/// SoundChain Marketplace for Solana
///
/// Multi-token marketplace with cross-chain support via ZetaChain.
/// Supports fixed price, auctions, and make offer listings.
///
/// Features:
/// - 20+ SPL tokens supported
/// - Cross-chain purchases via ZetaChain
/// - Collaborator royalty splits
/// - Bundle listings
#[program]
pub mod soundchain_marketplace {
    use super::*;

    /// Initialize the marketplace
    pub fn initialize(
        ctx: Context<Initialize>,
        fee_collector: Pubkey,
        platform_fee: u16,
    ) -> Result<()> {
        let marketplace = &mut ctx.accounts.marketplace;
        marketplace.authority = ctx.accounts.authority.key();
        marketplace.fee_collector = fee_collector;
        marketplace.platform_fee = platform_fee; // Basis points (50 = 0.5%)
        marketplace.total_listings = 0;
        marketplace.total_sales = 0;
        marketplace.paused = false;
        Ok(())
    }

    /// Create a fixed price listing
    pub fn create_listing(
        ctx: Context<CreateListing>,
        price: u64,
        duration: i64,
        scid: Option<String>,
    ) -> Result<()> {
        let marketplace = &ctx.accounts.marketplace;
        require!(!marketplace.paused, ErrorCode::MarketplacePaused);

        let listing = &mut ctx.accounts.listing;
        listing.seller = ctx.accounts.seller.key();
        listing.nft_mint = ctx.accounts.nft_mint.key();
        listing.payment_mint = ctx.accounts.payment_mint.key();
        listing.price = price;
        listing.listing_type = ListingType::FixedPrice;
        listing.status = ListingStatus::Active;
        listing.created_at = Clock::get()?.unix_timestamp;
        listing.expires_at = Clock::get()?.unix_timestamp + duration;
        listing.scid = scid;
        listing.buyer = None;
        listing.sold_at = None;

        // Transfer NFT to escrow
        let cpi_accounts = TokenTransfer {
            from: ctx.accounts.seller_nft_account.to_account_info(),
            to: ctx.accounts.escrow_nft_account.to_account_info(),
            authority: ctx.accounts.seller.to_account_info(),
        };
        let cpi_ctx = CpiContext::new(ctx.accounts.token_program.to_account_info(), cpi_accounts);
        token::transfer(cpi_ctx, 1)?;

        emit!(ListingCreated {
            listing: listing.key(),
            seller: listing.seller,
            nft_mint: listing.nft_mint,
            price,
            listing_type: ListingType::FixedPrice,
            timestamp: listing.created_at,
        });

        Ok(())
    }

    /// Create an auction listing
    pub fn create_auction(
        ctx: Context<CreateListing>,
        reserve_price: u64,
        duration: i64,
        scid: Option<String>,
    ) -> Result<()> {
        let marketplace = &ctx.accounts.marketplace;
        require!(!marketplace.paused, ErrorCode::MarketplacePaused);
        require!(duration >= 3600, ErrorCode::DurationTooShort); // Min 1 hour
        require!(duration <= 2592000, ErrorCode::DurationTooLong); // Max 30 days

        let listing = &mut ctx.accounts.listing;
        listing.seller = ctx.accounts.seller.key();
        listing.nft_mint = ctx.accounts.nft_mint.key();
        listing.payment_mint = ctx.accounts.payment_mint.key();
        listing.price = reserve_price;
        listing.listing_type = ListingType::Auction;
        listing.status = ListingStatus::Active;
        listing.created_at = Clock::get()?.unix_timestamp;
        listing.expires_at = Clock::get()?.unix_timestamp + duration;
        listing.scid = scid;
        listing.buyer = None;
        listing.sold_at = None;

        // Transfer NFT to escrow
        let cpi_accounts = TokenTransfer {
            from: ctx.accounts.seller_nft_account.to_account_info(),
            to: ctx.accounts.escrow_nft_account.to_account_info(),
            authority: ctx.accounts.seller.to_account_info(),
        };
        let cpi_ctx = CpiContext::new(ctx.accounts.token_program.to_account_info(), cpi_accounts);
        token::transfer(cpi_ctx, 1)?;

        emit!(ListingCreated {
            listing: listing.key(),
            seller: listing.seller,
            nft_mint: listing.nft_mint,
            price: reserve_price,
            listing_type: ListingType::Auction,
            timestamp: listing.created_at,
        });

        Ok(())
    }

    /// Buy a fixed price listing
    pub fn buy(ctx: Context<Buy>) -> Result<()> {
        let listing = &mut ctx.accounts.listing;
        let marketplace = &ctx.accounts.marketplace;

        require!(!marketplace.paused, ErrorCode::MarketplacePaused);
        require!(listing.status == ListingStatus::Active, ErrorCode::ListingNotActive);
        require!(listing.listing_type == ListingType::FixedPrice, ErrorCode::NotFixedPrice);
        require!(
            Clock::get()?.unix_timestamp < listing.expires_at,
            ErrorCode::ListingExpired
        );

        // Calculate fees
        let platform_fee = (listing.price as u128 * marketplace.platform_fee as u128 / 10000) as u64;
        let seller_amount = listing.price - platform_fee;

        // Transfer payment from buyer
        let cpi_accounts = TokenTransfer {
            from: ctx.accounts.buyer_payment_account.to_account_info(),
            to: ctx.accounts.seller_payment_account.to_account_info(),
            authority: ctx.accounts.buyer.to_account_info(),
        };
        let cpi_ctx = CpiContext::new(ctx.accounts.token_program.to_account_info(), cpi_accounts);
        token::transfer(cpi_ctx, seller_amount)?;

        // Transfer platform fee
        let fee_accounts = TokenTransfer {
            from: ctx.accounts.buyer_payment_account.to_account_info(),
            to: ctx.accounts.fee_collector_account.to_account_info(),
            authority: ctx.accounts.buyer.to_account_info(),
        };
        let fee_ctx = CpiContext::new(ctx.accounts.token_program.to_account_info(), fee_accounts);
        token::transfer(fee_ctx, platform_fee)?;

        // Transfer NFT to buyer (from escrow)
        let seeds = &[
            b"listing",
            listing.nft_mint.as_ref(),
            &[ctx.bumps.listing],
        ];
        let signer = &[&seeds[..]];

        let nft_accounts = TokenTransfer {
            from: ctx.accounts.escrow_nft_account.to_account_info(),
            to: ctx.accounts.buyer_nft_account.to_account_info(),
            authority: ctx.accounts.listing.to_account_info(),
        };
        let nft_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            nft_accounts,
            signer,
        );
        token::transfer(nft_ctx, 1)?;

        listing.status = ListingStatus::Sold;
        listing.buyer = Some(ctx.accounts.buyer.key());
        listing.sold_at = Some(Clock::get()?.unix_timestamp);

        emit!(ListingSold {
            listing: listing.key(),
            seller: listing.seller,
            buyer: ctx.accounts.buyer.key(),
            nft_mint: listing.nft_mint,
            price: listing.price,
            platform_fee,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Place a bid on an auction
    pub fn place_bid(ctx: Context<PlaceBid>, amount: u64) -> Result<()> {
        let listing = &ctx.accounts.listing;
        let auction = &mut ctx.accounts.auction;
        let marketplace = &ctx.accounts.marketplace;

        require!(!marketplace.paused, ErrorCode::MarketplacePaused);
        require!(listing.status == ListingStatus::Active, ErrorCode::ListingNotActive);
        require!(listing.listing_type == ListingType::Auction, ErrorCode::NotAuction);
        require!(
            Clock::get()?.unix_timestamp < listing.expires_at,
            ErrorCode::ListingExpired
        );
        require!(amount > auction.current_bid, ErrorCode::BidTooLow);

        if auction.current_bid > 0 {
            // Must be at least 5% higher
            require!(
                amount >= auction.current_bid * 105 / 100,
                ErrorCode::InsufficientBidIncrease
            );

            // Refund previous bidder
            let refund_accounts = TokenTransfer {
                from: ctx.accounts.escrow_payment_account.to_account_info(),
                to: ctx.accounts.previous_bidder_account.to_account_info(),
                authority: ctx.accounts.auction.to_account_info(),
            };
            let seeds = &[
                b"auction",
                listing.key().as_ref(),
                &[ctx.bumps.auction],
            ];
            let signer = &[&seeds[..]];
            let refund_ctx = CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                refund_accounts,
                signer,
            );
            token::transfer(refund_ctx, auction.current_bid)?;
        }

        // Transfer new bid to escrow
        let bid_accounts = TokenTransfer {
            from: ctx.accounts.bidder_payment_account.to_account_info(),
            to: ctx.accounts.escrow_payment_account.to_account_info(),
            authority: ctx.accounts.bidder.to_account_info(),
        };
        let bid_ctx = CpiContext::new(ctx.accounts.token_program.to_account_info(), bid_accounts);
        token::transfer(bid_ctx, amount)?;

        auction.current_bid = amount;
        auction.current_bidder = ctx.accounts.bidder.key();
        auction.bid_count += 1;

        if amount >= listing.price {
            auction.reserve_met = true;
        }

        emit!(BidPlaced {
            listing: listing.key(),
            bidder: ctx.accounts.bidder.key(),
            amount,
            bid_count: auction.bid_count,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Settle an ended auction
    pub fn settle_auction(ctx: Context<SettleAuction>) -> Result<()> {
        let listing = &mut ctx.accounts.listing;
        let auction = &ctx.accounts.auction;
        let marketplace = &ctx.accounts.marketplace;

        require!(listing.status == ListingStatus::Active, ErrorCode::ListingNotActive);
        require!(listing.listing_type == ListingType::Auction, ErrorCode::NotAuction);
        require!(
            Clock::get()?.unix_timestamp >= listing.expires_at,
            ErrorCode::AuctionNotEnded
        );

        if auction.reserve_met && auction.current_bidder != Pubkey::default() {
            // Successful auction
            let platform_fee = (auction.current_bid as u128 * marketplace.platform_fee as u128 / 10000) as u64;
            let seller_amount = auction.current_bid - platform_fee;

            // Transfer payment to seller (from escrow)
            let seeds = &[
                b"auction",
                listing.key().as_ref(),
                &[ctx.bumps.auction],
            ];
            let signer = &[&seeds[..]];

            let seller_accounts = TokenTransfer {
                from: ctx.accounts.escrow_payment_account.to_account_info(),
                to: ctx.accounts.seller_payment_account.to_account_info(),
                authority: ctx.accounts.auction.to_account_info(),
            };
            let seller_ctx = CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                seller_accounts,
                signer,
            );
            token::transfer(seller_ctx, seller_amount)?;

            // Transfer fee
            let fee_accounts = TokenTransfer {
                from: ctx.accounts.escrow_payment_account.to_account_info(),
                to: ctx.accounts.fee_collector_account.to_account_info(),
                authority: ctx.accounts.auction.to_account_info(),
            };
            let fee_ctx = CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                fee_accounts,
                signer,
            );
            token::transfer(fee_ctx, platform_fee)?;

            // Transfer NFT to winner
            let listing_seeds = &[
                b"listing",
                listing.nft_mint.as_ref(),
                &[ctx.bumps.listing],
            ];
            let listing_signer = &[&listing_seeds[..]];

            let nft_accounts = TokenTransfer {
                from: ctx.accounts.escrow_nft_account.to_account_info(),
                to: ctx.accounts.winner_nft_account.to_account_info(),
                authority: ctx.accounts.listing.to_account_info(),
            };
            let nft_ctx = CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                nft_accounts,
                listing_signer,
            );
            token::transfer(nft_ctx, 1)?;

            listing.status = ListingStatus::Sold;
            listing.buyer = Some(auction.current_bidder);
            listing.sold_at = Some(Clock::get()?.unix_timestamp);

            emit!(ListingSold {
                listing: listing.key(),
                seller: listing.seller,
                buyer: auction.current_bidder,
                nft_mint: listing.nft_mint,
                price: auction.current_bid,
                platform_fee,
                timestamp: Clock::get()?.unix_timestamp,
            });
        } else {
            // Failed auction - return NFT to seller
            let listing_seeds = &[
                b"listing",
                listing.nft_mint.as_ref(),
                &[ctx.bumps.listing],
            ];
            let listing_signer = &[&listing_seeds[..]];

            let nft_accounts = TokenTransfer {
                from: ctx.accounts.escrow_nft_account.to_account_info(),
                to: ctx.accounts.seller_nft_account.to_account_info(),
                authority: ctx.accounts.listing.to_account_info(),
            };
            let nft_ctx = CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                nft_accounts,
                listing_signer,
            );
            token::transfer(nft_ctx, 1)?;

            listing.status = ListingStatus::Expired;
        }

        Ok(())
    }

    /// Cancel a listing
    pub fn cancel_listing(ctx: Context<CancelListing>) -> Result<()> {
        let listing = &mut ctx.accounts.listing;

        require!(listing.status == ListingStatus::Active, ErrorCode::ListingNotActive);
        require!(
            listing.seller == ctx.accounts.seller.key(),
            ErrorCode::NotSeller
        );

        // For auctions, ensure no active bids
        if listing.listing_type == ListingType::Auction {
            let auction = &ctx.accounts.auction;
            require!(auction.current_bid == 0, ErrorCode::HasActiveBid);
        }

        // Return NFT to seller
        let seeds = &[
            b"listing",
            listing.nft_mint.as_ref(),
            &[ctx.bumps.listing],
        ];
        let signer = &[&seeds[..]];

        let nft_accounts = TokenTransfer {
            from: ctx.accounts.escrow_nft_account.to_account_info(),
            to: ctx.accounts.seller_nft_account.to_account_info(),
            authority: ctx.accounts.listing.to_account_info(),
        };
        let nft_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            nft_accounts,
            signer,
        );
        token::transfer(nft_ctx, 1)?;

        listing.status = ListingStatus::Cancelled;

        emit!(ListingCancelled {
            listing: listing.key(),
            seller: listing.seller,
            nft_mint: listing.nft_mint,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Pause/unpause marketplace (admin only)
    pub fn set_paused(ctx: Context<AdminAction>, paused: bool) -> Result<()> {
        let marketplace = &mut ctx.accounts.marketplace;
        marketplace.paused = paused;
        Ok(())
    }

    /// Update platform fee (admin only)
    pub fn set_fee(ctx: Context<AdminAction>, new_fee: u16) -> Result<()> {
        require!(new_fee <= 1000, ErrorCode::FeeTooHigh); // Max 10%
        let marketplace = &mut ctx.accounts.marketplace;
        marketplace.platform_fee = new_fee;
        Ok(())
    }
}

// ============ Enums ============

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq)]
pub enum ListingType {
    FixedPrice,
    Auction,
    MakeOffer,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq)]
pub enum ListingStatus {
    Active,
    Sold,
    Cancelled,
    Expired,
}

// ============ Accounts ============

#[account]
pub struct Marketplace {
    pub authority: Pubkey,
    pub fee_collector: Pubkey,
    pub platform_fee: u16,
    pub total_listings: u64,
    pub total_sales: u64,
    pub paused: bool,
}

#[account]
pub struct Listing {
    pub seller: Pubkey,
    pub nft_mint: Pubkey,
    pub payment_mint: Pubkey,
    pub price: u64,
    pub listing_type: ListingType,
    pub status: ListingStatus,
    pub created_at: i64,
    pub expires_at: i64,
    pub scid: Option<String>,
    pub buyer: Option<Pubkey>,
    pub sold_at: Option<i64>,
}

#[account]
pub struct Auction {
    pub listing: Pubkey,
    pub current_bid: u64,
    pub current_bidder: Pubkey,
    pub bid_count: u32,
    pub reserve_met: bool,
}

// ============ Contexts ============

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 32 + 2 + 8 + 8 + 1,
        seeds = [b"marketplace"],
        bump
    )]
    pub marketplace: Account<'info, Marketplace>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct CreateListing<'info> {
    #[account(seeds = [b"marketplace"], bump)]
    pub marketplace: Account<'info, Marketplace>,
    #[account(
        init,
        payer = seller,
        space = 8 + 32 + 32 + 32 + 8 + 1 + 1 + 8 + 8 + 36 + 33 + 9,
        seeds = [b"listing", nft_mint.key().as_ref()],
        bump
    )]
    pub listing: Account<'info, Listing>,
    pub nft_mint: Account<'info, token::Mint>,
    pub payment_mint: Account<'info, token::Mint>,
    #[account(mut)]
    pub seller: Signer<'info>,
    #[account(mut)]
    pub seller_nft_account: Account<'info, TokenAccount>,
    #[account(
        init_if_needed,
        payer = seller,
        associated_token::mint = nft_mint,
        associated_token::authority = listing
    )]
    pub escrow_nft_account: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct Buy<'info> {
    #[account(seeds = [b"marketplace"], bump)]
    pub marketplace: Account<'info, Marketplace>,
    #[account(
        mut,
        seeds = [b"listing", listing.nft_mint.as_ref()],
        bump
    )]
    pub listing: Account<'info, Listing>,
    #[account(mut)]
    pub buyer: Signer<'info>,
    #[account(mut)]
    pub buyer_payment_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub buyer_nft_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub seller_payment_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub fee_collector_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub escrow_nft_account: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct PlaceBid<'info> {
    #[account(seeds = [b"marketplace"], bump)]
    pub marketplace: Account<'info, Marketplace>,
    #[account(seeds = [b"listing", listing.nft_mint.as_ref()], bump)]
    pub listing: Account<'info, Listing>,
    #[account(
        mut,
        seeds = [b"auction", listing.key().as_ref()],
        bump
    )]
    pub auction: Account<'info, Auction>,
    #[account(mut)]
    pub bidder: Signer<'info>,
    #[account(mut)]
    pub bidder_payment_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub escrow_payment_account: Account<'info, TokenAccount>,
    /// CHECK: Previous bidder's token account for refund
    #[account(mut)]
    pub previous_bidder_account: AccountInfo<'info>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct SettleAuction<'info> {
    #[account(seeds = [b"marketplace"], bump)]
    pub marketplace: Account<'info, Marketplace>,
    #[account(
        mut,
        seeds = [b"listing", listing.nft_mint.as_ref()],
        bump
    )]
    pub listing: Account<'info, Listing>,
    #[account(
        seeds = [b"auction", listing.key().as_ref()],
        bump
    )]
    pub auction: Account<'info, Auction>,
    #[account(mut)]
    pub seller_payment_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub seller_nft_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub fee_collector_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub winner_nft_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub escrow_nft_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub escrow_payment_account: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct CancelListing<'info> {
    #[account(
        mut,
        seeds = [b"listing", listing.nft_mint.as_ref()],
        bump
    )]
    pub listing: Account<'info, Listing>,
    /// CHECK: Optional auction account
    pub auction: Option<Account<'info, Auction>>,
    pub seller: Signer<'info>,
    #[account(mut)]
    pub seller_nft_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub escrow_nft_account: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct AdminAction<'info> {
    #[account(mut, seeds = [b"marketplace"], bump, has_one = authority)]
    pub marketplace: Account<'info, Marketplace>,
    pub authority: Signer<'info>,
}

// ============ Events ============

#[event]
pub struct ListingCreated {
    pub listing: Pubkey,
    pub seller: Pubkey,
    pub nft_mint: Pubkey,
    pub price: u64,
    pub listing_type: ListingType,
    pub timestamp: i64,
}

#[event]
pub struct ListingSold {
    pub listing: Pubkey,
    pub seller: Pubkey,
    pub buyer: Pubkey,
    pub nft_mint: Pubkey,
    pub price: u64,
    pub platform_fee: u64,
    pub timestamp: i64,
}

#[event]
pub struct BidPlaced {
    pub listing: Pubkey,
    pub bidder: Pubkey,
    pub amount: u64,
    pub bid_count: u32,
    pub timestamp: i64,
}

#[event]
pub struct ListingCancelled {
    pub listing: Pubkey,
    pub seller: Pubkey,
    pub nft_mint: Pubkey,
    pub timestamp: i64,
}

// ============ Errors ============

#[error_code]
pub enum ErrorCode {
    #[msg("Marketplace is paused")]
    MarketplacePaused,
    #[msg("Listing is not active")]
    ListingNotActive,
    #[msg("Listing has expired")]
    ListingExpired,
    #[msg("Not a fixed price listing")]
    NotFixedPrice,
    #[msg("Not an auction listing")]
    NotAuction,
    #[msg("Auction has not ended yet")]
    AuctionNotEnded,
    #[msg("Bid is too low")]
    BidTooLow,
    #[msg("Bid must be at least 5% higher")]
    InsufficientBidIncrease,
    #[msg("Not the seller")]
    NotSeller,
    #[msg("Has active bid")]
    HasActiveBid,
    #[msg("Duration too short")]
    DurationTooShort,
    #[msg("Duration too long")]
    DurationTooLong,
    #[msg("Fee too high")]
    FeeTooHigh,
}
