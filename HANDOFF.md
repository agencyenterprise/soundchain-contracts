# SoundChain Contracts - HANDOFF

**Priority: HIGH - Blockchain Optimization Phase**
**Last Updated: January 2, 2026**
**Status: StreamingRewardsDistributor Ready for Deployment**

---

## ECOSYSTEM MERKLE TREE

```
soundchain/
├── MASTER_HANDOFF.md ────────────── Root ecosystem handoff (this links all)
├── HANDOFF.md ───────────────────── Main development handoff
│
├── web/ ─────────────────────────── Frontend (Next.js)
│   ├── HANDOFF.md ───────────────── Frontend-specific handoff
│   └── HANDOFF_TO_CLAUDE_CODE.md ── Claude Code integration notes
│
├── api/ ─────────────────────────── Backend (NestJS/GraphQL)
│   └── (inline in main HANDOFF)
│
├── soundchain-contracts/ ────────── Smart Contracts (This file)
│   └── HANDOFF.md ───────────────── Contract deployment & AWS config
│
└── soundchain-agent/ ────────────── AI Agent
    └── HANDOFF_2025-12-07.md ────── Agent development notes
```

---

## AWS INFRASTRUCTURE

### KMS Keys (us-east-1)

| Key ID | Purpose | Type |
|--------|---------|------|
| `267075a7-2547-48a8-a737-49d13ddd1146` | **PROD-KEY** - Production Ethereum signing | ECC_SECG_P256K1 |
| `0e454c9f-34a2-4d22-8684-5d787e358886` | Backup Ethereum signing | ECC_SECG_P256K1 |

### IAM User
```
Account: 271937159223
User: frank-chavez
ARN: arn:aws:iam::271937159223:user/frank-chavez
```

### RPC Endpoints

| Network | URL |
|---------|-----|
| Polygon Mainnet | `https://polygon-mainnet.g.alchemy.com/v2/-6cS3AFE-iS1ZCnh-bNLQGRM1Gif9t-8` |
| Polygon Mumbai | `https://polygon-mumbai.g.alchemy.com/v2/aMF793l_JpVtk7RaER-KZZW4vH7vWXiH` |

### API Keys
```
POLYGONSCAN_API_KEY=YIX26G28GVEREYG43W391ZSBYQIME2VYD5
```

---

## DEPLOYED CONTRACTS (Polygon Mainnet)

| Contract | Address | Status |
|----------|---------|--------|
| OGUN Token | `0x99Db69EEe7637101FA216Ab4A3276eBedC63e146` | LIVE |
| Marketplace | `0x...` | LIVE |
| StreamingRewardsDistributor | **PENDING DEPLOYMENT** | Ready |

---

## STREAMING REWARDS DISTRIBUTOR (NEW - Jan 2, 2026)

### Contract Features

```solidity
// Distribution Functions
submitReward(user, scid, amount, isNft)                    // Single recipient
submitRewardWithListenerSplit(creator, listener, ...)      // 50/50 split
submitRewardWithCollaborators(creator, collaborators[], ...)  // Collaborator splits
submitRewardFull(creator, listener, collaborators[], ...)  // Full split

// Admin Functions
setProtocolFee(feeBps, feeRecipient)   // Set 0.05% fee (5 bps)
setListenerSplit(listenerBps)           // Default 50% (5000 bps)
authorizeDistributor(address)           // Authorize backend service
```

### Reward Flow
```
Stream Event (30+ seconds)
         ↓
   [Total Reward: 0.5 OGUN (NFT) / 0.05 OGUN (non-NFT)]
         ↓
   [0.05% Protocol Fee → SoundChain Treasury]
         ↓
   [99.95% splits:]
   ├── 50% → Listener (streamer)
   └── 50% → Creator pool
               ├── Collaborator 1 (royalty %)
               ├── Collaborator 2 (royalty %)
               └── Primary Creator (remainder)
```

### Environment Setup (.env)
```bash
# AWS KMS for Ethereum signing
AWS_KMS_KEY_ID=267075a7-2547-48a8-a737-49d13ddd1146

# Polygon Mainnet
POLYGON_ALCHEMY_URL=https://polygon-mainnet.g.alchemy.com/v2/-6cS3AFE-iS1ZCnh-bNLQGRM1Gif9t-8

# OGUN Token
OGUN_TOKEN_ADDRESS=0x99Db69EEe7637101FA216Ab4A3276eBedC63e146

# Verification
POLYGONSCAN_API_KEY=YIX26G28GVEREYG43W391ZSBYQIME2VYD5
```

### Deployment Command
```bash
cd soundchain-contracts
npx hardhat run scripts/deployStreamingRewards.ts --network polygon
```

### Post-Deployment Steps
```bash
# 1. Set protocol fee (0.05% = 5 bps)
cast send $CONTRACT "setProtocolFee(uint256,address)" 5 $TREASURY_ADDRESS

# 2. Authorize backend service
cast send $CONTRACT "authorizeDistributor(address)" $BACKEND_WALLET

# 3. Fund contract with OGUN from Trading Fee Rewards treasury
cast send $OGUN_TOKEN "transfer(address,uint256)" $CONTRACT $AMOUNT
```

---

## TOKEN DISTRIBUTION TREASURY

From [GitBook](https://soundchain.gitbook.io/soundchain/token/ogun):

| Allocation | % | OGUN | Purpose |
|------------|---|------|---------|
| Trading Fee Rewards | 20% | 200,000,000 | **← STREAMING REWARDS SOURCE** |
| Staking Rewards | 20% | 200,000,000 | Staking incentives |
| Treasury (Dev Team) | 10% | 100,000,000 | Operations |
| Founding Team | 20% | 200,000,000 | Team allocation |
| Airdrop | 15% | 150,000,000 | Community |
| Liquidity Pool Rewards | 10% | 100,000,000 | LP incentives |
| Strategic Partnerships | 3% | 30,000,000 | Partners |
| Initial Liquidity | 2% | 20,000,000 | DEX liquidity |

---

## OMNICHAIN INFRASTRUCTURE

### Contracts Ready for Deployment

| Contract | Purpose | Status |
|----------|---------|--------|
| `OmnichainRouter.sol` | Grand Central Station - routes ALL cross-chain operations | Compiled |
| `ChainConnector.sol` | Lightweight relay per chain (spoke contracts) | Compiled |
| `TokenListingProxy.sol` | Multi-token NFT listings (32+ tokens) | Compiled |
| `BundleListingProxy.sol` | Bundle listings with 6 tiers | Compiled |
| `SweepProxy.sol` | Floor sweep, batch operations, airdrops | Compiled |
| `MultiTokenMarketplace.sol` | Marketplace with collaborator royalties | Compiled |
| `SCidRegistry.sol` | On-chain SCid registration | Compiled |
| `SoundchainFeeCollector.sol` | Fee collection and Gnosis Safe routing | Compiled |

### 23 Supported Chains

| Chain | Native Token | RPC Status |
|-------|--------------|------------|
| Ethereum | ETH | Ready |
| Polygon | MATIC | Ready |
| Base | ETH | Ready |
| Arbitrum | ETH | Ready |
| Optimism | ETH | Ready |
| BSC | BNB | Ready |
| Avalanche | AVAX | Ready |
| ZetaChain | ZETA | Ready |
| Blast | ETH | Ready |
| Linea | ETH | Ready |
| Scroll | ETH | Ready |
| zkSync | ETH | Ready |
| Mantle | MNT | Ready |
| Manta | ETH | Ready |
| Mode | ETH | Ready |
| Celo | CELO | Ready |
| Gnosis | xDAI | Ready |
| Moonbeam | GLMR | Ready |
| Aurora | ETH | Ready |
| Cronos | CRO | Ready |
| Kava | KAVA | Ready |
| Metis | METIS | Ready |
| Solana | SOL | Ready |

---

## GIT COMMITS (Jan 2, 2026)

```
4fce64a feat: Add listener rewards, collaborator splits, and protocol fee
ce03329 feat: Add StreamingRewardsDistributor contract
```

---

## LINKED HANDOFFS

| File | Location | Purpose |
|------|----------|---------|
| Main HANDOFF | `/soundchain/HANDOFF.md` | Primary development handoff |
| Web HANDOFF | `/soundchain/web/HANDOFF.md` | Frontend notes |
| Agent HANDOFF | `/soundchain/soundchain-agent/HANDOFF_2025-12-07.md` | AI agent notes |
| This File | `/soundchain-contracts/HANDOFF.md` | Blockchain & contracts |

---

## QUICK COMMANDS

```bash
# Compile contracts
npx hardhat compile

# Deploy streaming rewards
npx hardhat run scripts/deployStreamingRewards.ts --network polygon

# Verify contract
npx hardhat verify --network polygon $ADDRESS $OGUN_TOKEN_ADDRESS

# Check AWS identity
aws sts get-caller-identity

# List KMS keys
aws kms list-keys --region us-east-1
```

---

## SECURITY CHECKLIST

- [ ] All private keys stored in AWS KMS (not in code)
- [ ] Gnosis Safe wallets use hardware wallet signers
- [ ] 2-of-3 threshold on all Safes
- [ ] Contracts verified on block explorers
- [ ] Fee recipient addresses double-checked
- [ ] Test on Amoy testnet before mainnet

---

*Updated: January 2, 2026 - StreamingRewardsDistributor with listener/collaborator splits ready for deployment*
