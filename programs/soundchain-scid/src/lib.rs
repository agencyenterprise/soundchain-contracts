use anchor_lang::prelude::*;
use anchor_spl::token::{Token, TokenAccount};

declare_id!("SCidxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");

/// SoundChain SCid Registry for Solana
///
/// This program registers and manages SCids (SoundChain IDs) on Solana.
/// Integrates with ZetaChain via cross-chain messaging for omnichain support.
///
/// SCid Format: SC-[CHAIN]-[ARTIST_HASH]-[YEAR][SEQUENCE]
/// Example: SC-SOL-7B3A-2500001 (Solana chain, artist hash 7B3A, 2025, sequence 1)
#[program]
pub mod soundchain_scid {
    use super::*;

    /// Initialize the SCid registry
    pub fn initialize(ctx: Context<Initialize>, fee_collector: Pubkey) -> Result<()> {
        let registry = &mut ctx.accounts.registry;
        registry.authority = ctx.accounts.authority.key();
        registry.fee_collector = fee_collector;
        registry.registration_fee = 1_000_000; // 0.001 SOL (1 million lamports)
        registry.total_registrations = 0;
        registry.paused = false;
        Ok(())
    }

    /// Register a new SCid
    pub fn register(
        ctx: Context<Register>,
        scid: String,
        metadata_hash: String,
        token_id: u64,
        nft_mint: Pubkey,
    ) -> Result<()> {
        let registry = &mut ctx.accounts.registry;
        require!(!registry.paused, ErrorCode::RegistryPaused);
        require!(scid.len() >= 15 && scid.len() <= 25, ErrorCode::InvalidScidLength);
        require!(scid.starts_with("SC-SOL-"), ErrorCode::InvalidScidPrefix);

        // Parse SCid components
        let parts: Vec<&str> = scid.split('-').collect();
        require!(parts.len() == 4, ErrorCode::InvalidScidFormat);

        let artist_hash = parts[2].to_string();
        let year_seq = parts[3];
        require!(year_seq.len() == 7, ErrorCode::InvalidYearSequence);

        let year: u16 = year_seq[0..2].parse().map_err(|_| ErrorCode::InvalidYear)?;
        let sequence: u32 = year_seq[2..].parse().map_err(|_| ErrorCode::InvalidSequence)?;

        // Transfer registration fee
        let cpi_context = CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            anchor_lang::system_program::Transfer {
                from: ctx.accounts.owner.to_account_info(),
                to: ctx.accounts.fee_collector.to_account_info(),
            },
        );
        anchor_lang::system_program::transfer(cpi_context, registry.registration_fee)?;

        // Initialize SCid record
        let scid_record = &mut ctx.accounts.scid_record;
        scid_record.scid = scid.clone();
        scid_record.owner = ctx.accounts.owner.key();
        scid_record.token_id = token_id;
        scid_record.nft_mint = nft_mint;
        scid_record.metadata_hash = metadata_hash;
        scid_record.artist_hash = artist_hash;
        scid_record.year = year;
        scid_record.sequence = sequence;
        scid_record.registered_at = Clock::get()?.unix_timestamp;
        scid_record.active = true;
        scid_record.cross_chain_verified = false;

        registry.total_registrations += 1;

        emit!(ScidRegistered {
            scid,
            owner: ctx.accounts.owner.key(),
            nft_mint,
            token_id,
            timestamp: scid_record.registered_at,
        });

        Ok(())
    }

    /// Transfer SCid ownership
    pub fn transfer(ctx: Context<Transfer>, new_owner: Pubkey) -> Result<()> {
        let scid_record = &mut ctx.accounts.scid_record;
        require!(scid_record.active, ErrorCode::ScidInactive);
        require!(
            scid_record.owner == ctx.accounts.owner.key(),
            ErrorCode::NotOwner
        );

        let old_owner = scid_record.owner;
        scid_record.owner = new_owner;

        emit!(ScidTransferred {
            scid: scid_record.scid.clone(),
            from: old_owner,
            to: new_owner,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Verify cross-chain registration (called by ZetaChain connector)
    pub fn verify_cross_chain(
        ctx: Context<VerifyCrossChain>,
        source_chain: u16,
        source_tx_hash: [u8; 32],
    ) -> Result<()> {
        let scid_record = &mut ctx.accounts.scid_record;
        require!(scid_record.active, ErrorCode::ScidInactive);

        scid_record.cross_chain_verified = true;
        scid_record.source_chain = source_chain;
        scid_record.source_tx_hash = source_tx_hash;

        emit!(CrossChainVerified {
            scid: scid_record.scid.clone(),
            source_chain,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Revoke SCid (owner or admin only)
    pub fn revoke(ctx: Context<Revoke>) -> Result<()> {
        let scid_record = &mut ctx.accounts.scid_record;
        let registry = &ctx.accounts.registry;

        let is_owner = scid_record.owner == ctx.accounts.authority.key();
        let is_admin = registry.authority == ctx.accounts.authority.key();
        require!(is_owner || is_admin, ErrorCode::NotAuthorized);

        scid_record.active = false;

        emit!(ScidRevoked {
            scid: scid_record.scid.clone(),
            by: ctx.accounts.authority.key(),
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Update registration fee (admin only)
    pub fn set_fee(ctx: Context<AdminAction>, new_fee: u64) -> Result<()> {
        let registry = &mut ctx.accounts.registry;
        registry.registration_fee = new_fee;
        Ok(())
    }

    /// Pause/unpause registry (admin only)
    pub fn set_paused(ctx: Context<AdminAction>, paused: bool) -> Result<()> {
        let registry = &mut ctx.accounts.registry;
        registry.paused = paused;
        Ok(())
    }
}

// ============ Accounts ============

#[account]
pub struct Registry {
    pub authority: Pubkey,
    pub fee_collector: Pubkey,
    pub registration_fee: u64,
    pub total_registrations: u64,
    pub paused: bool,
}

#[account]
pub struct ScidRecord {
    pub scid: String,           // Max 25 chars
    pub owner: Pubkey,
    pub token_id: u64,
    pub nft_mint: Pubkey,
    pub metadata_hash: String,  // Max 64 chars (IPFS hash)
    pub artist_hash: String,    // 4 chars
    pub year: u16,
    pub sequence: u32,
    pub registered_at: i64,
    pub active: bool,
    pub cross_chain_verified: bool,
    pub source_chain: u16,
    pub source_tx_hash: [u8; 32],
}

// ============ Contexts ============

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 32 + 8 + 8 + 1,
        seeds = [b"registry"],
        bump
    )]
    pub registry: Account<'info, Registry>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(scid: String)]
pub struct Register<'info> {
    #[account(mut, seeds = [b"registry"], bump)]
    pub registry: Account<'info, Registry>,
    #[account(
        init,
        payer = owner,
        space = 8 + 28 + 32 + 8 + 32 + 68 + 8 + 2 + 4 + 8 + 1 + 1 + 2 + 32,
        seeds = [b"scid", scid.as_bytes()],
        bump
    )]
    pub scid_record: Account<'info, ScidRecord>,
    #[account(mut)]
    pub owner: Signer<'info>,
    /// CHECK: Fee collector account
    #[account(mut)]
    pub fee_collector: AccountInfo<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Transfer<'info> {
    #[account(mut)]
    pub scid_record: Account<'info, ScidRecord>,
    pub owner: Signer<'info>,
}

#[derive(Accounts)]
pub struct VerifyCrossChain<'info> {
    #[account(seeds = [b"registry"], bump)]
    pub registry: Account<'info, Registry>,
    #[account(mut)]
    pub scid_record: Account<'info, ScidRecord>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct Revoke<'info> {
    #[account(seeds = [b"registry"], bump)]
    pub registry: Account<'info, Registry>,
    #[account(mut)]
    pub scid_record: Account<'info, ScidRecord>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct AdminAction<'info> {
    #[account(mut, seeds = [b"registry"], bump, has_one = authority)]
    pub registry: Account<'info, Registry>,
    pub authority: Signer<'info>,
}

// ============ Events ============

#[event]
pub struct ScidRegistered {
    pub scid: String,
    pub owner: Pubkey,
    pub nft_mint: Pubkey,
    pub token_id: u64,
    pub timestamp: i64,
}

#[event]
pub struct ScidTransferred {
    pub scid: String,
    pub from: Pubkey,
    pub to: Pubkey,
    pub timestamp: i64,
}

#[event]
pub struct CrossChainVerified {
    pub scid: String,
    pub source_chain: u16,
    pub timestamp: i64,
}

#[event]
pub struct ScidRevoked {
    pub scid: String,
    pub by: Pubkey,
    pub timestamp: i64,
}

// ============ Errors ============

#[error_code]
pub enum ErrorCode {
    #[msg("Registry is paused")]
    RegistryPaused,
    #[msg("Invalid SCid length")]
    InvalidScidLength,
    #[msg("SCid must start with SC-SOL-")]
    InvalidScidPrefix,
    #[msg("Invalid SCid format")]
    InvalidScidFormat,
    #[msg("Invalid year/sequence format")]
    InvalidYearSequence,
    #[msg("Invalid year")]
    InvalidYear,
    #[msg("Invalid sequence")]
    InvalidSequence,
    #[msg("SCid is inactive")]
    ScidInactive,
    #[msg("Not the owner")]
    NotOwner,
    #[msg("Not authorized")]
    NotAuthorized,
}
