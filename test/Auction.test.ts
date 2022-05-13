import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import {
  ERC20,
  Soundchain721,
  Soundchain721__factory,
  SoundchainAuctionMock,
  SoundchainAuctionMock__factory
} from "../typechain-types";

describe("auction", () => {
  const firstTokenId = "0";
  const secondTokenId = "1";
  const platformFee: any = "250"; // auction platform fee: 2.5%
  const tokenUri = "ipfs";
  const rewardRate = "1000"; // reward rate: 10%

  let owner: SignerWithAddress,
    minter: SignerWithAddress,
    buyer: SignerWithAddress,
    buyer2: SignerWithAddress,
    nft: Soundchain721,
    OGUN: ERC20,
    feeAddress: SignerWithAddress,
    auction: SoundchainAuctionMock;

  beforeEach(async () => {
    [owner, minter, buyer, feeAddress, buyer2] = await ethers.getSigners();

    const SoundchainCollectible: Soundchain721__factory =
      await ethers.getContractFactory("Soundchain721");
    nft = await SoundchainCollectible.deploy();

    const AuctionFactory: SoundchainAuctionMock__factory =
      await ethers.getContractFactory("SoundchainAuctionMock");

    const token = await ethers.getContractFactory("SoundchainOGUN20");
    OGUN = await token.deploy();

    auction = await AuctionFactory.deploy(
      feeAddress.address, 
      OGUN.address, 
      platformFee,
      rewardRate
      );

    await nft.safeMint(minter.address, tokenUri, 10);
    await nft.safeMint(owner.address, tokenUri, 10);
    await nft.safeMint(minter.address, tokenUri, 10);
    await nft.connect(minter).setApprovalForAll(auction.address, true);
    await nft.connect(owner).setApprovalForAll(auction.address, true);

    await OGUN.transfer(buyer2.address, "1000000000000000000000000");
    await OGUN.transfer(buyer.address, "1000000000000000000000000");
    await OGUN.transfer(auction.address, "1000000000000000000000000");
  });

  describe("create auction", () => {
    describe("validation", async () => {
      it("reverts if endTime is in the past", async () => {
        await auction.setNowOverride("12");
        await expect(
          auction
            .connect(minter)
            .createAuction(nft.address, firstTokenId, "1", false, "13", "10" as any)
        ).to.be.revertedWith(
          "end time must be greater than start (by 5 minutes)"
        );
      });

      it("reverts if startTime less than now", async () => {
        await auction.setNowOverride("2");
        await expect(
          auction
            .connect(minter)
            .createAuction(nft.address, firstTokenId, "1", false, "1", "4000" as any)
        ).to.be.revertedWith("invalid start time");
      });

      it("reverts if nft already has auction in play", async () => {
        await auction
          .connect(minter)
          .createAuction(
            nft.address,
            firstTokenId,
            "1", 
            false,
            "10000000000000",
            "100000000000000" as any
          );

        expect(
          auction
            .connect(minter)
            .createAuction(
              nft.address,
              firstTokenId,
              "1",
              false,
              "10000000000000",
              "100000000000000" as any
            )
        ).to.be.revertedWith("auction already started");
      });

      it("reverts if token does not exist", async () => {
        await auction.setNowOverride("10");

        await expect(
          auction
            .connect(minter)
            .createAuction(nft.address, "99", "1", false, "1", "400" as any)
        ).to.be.revertedWith("ERC721: owner query for nonexistent token");
      });

      it("reverts if contract is paused", async () => {
        await auction.setNowOverride("2");
        await auction.connect(owner).toggleIsPaused();
        await expect(
          auction
            .connect(minter)
            .createAuction(nft.address, firstTokenId, "1", false, "0", "400" as any)
        ).to.be.revertedWith("contract paused");
      });

      it("reverts if you don't own the nft", async () => {
        await auction
          .connect(minter)
          .createAuction(
            nft.address,
            firstTokenId,
            "1",
            false,
            "10000000000000",
            "100000000000000" as any
          );

        expect(
          auction
            .connect(minter)
            .createAuction(nft.address, secondTokenId, "1", false, "1", "3" as any)
        ).to.be.revertedWith("not owner and or contract not approved");
      });
    });

    describe("successful creation", async () => {
      it("token retains in the ownership of the auction creator", async () => {
        await auction
          .connect(minter)
          .createAuction(
            nft.address,
            firstTokenId,
            "1",
            false,
            "10000000000000",
            "100000000000000" as any
          );

        const owner = await nft.ownerOf(firstTokenId);
        expect(owner).to.be.equal(minter.address);
      });
    });
  });

  describe("placeBid", async () => {
    describe("validation", () => {
      beforeEach(async () => {
        await auction.setNowOverride("2");

        await auction.connect(minter).createAuction(
          nft.address,
          firstTokenId,
          "1", // reserve
          false,
          "3", // start
          "400" as any // end
        );
      });

      it("reverts with 721 token not on auction", async () => {
        await expect(
          auction.connect(buyer).placeBid(nft.address, 999, false, "0", { value: 1 })
        ).to.be.revertedWith("bidding outside of the auction window");
      });

      it("reverts with valid token but no auction", async () => {
        await expect(
          auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
            value: 1,
          })
        ).to.be.revertedWith("bidding outside of the auction window");
      });

      it("reverts when auction finished", async () => {
        await auction.setNowOverride("500");
        await expect(
          auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
            value: 1,
          })
        ).to.be.revertedWith("bidding outside of the auction window");
      });

      it("reverts when contract is paused", async () => {
        await auction.connect(owner).toggleIsPaused();
        await expect(
          auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
            value: 10000000,
          })
        ).to.be.revertedWith("contract paused");
      });

      it("reverts when outbidding someone by less than the increment", async () => {
        await auction.setNowOverride("4");
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
          value: 20000000,
        });

        await expect(
          auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0",{
            value: 20000000,
          })
        ).to.be.revertedWith("failed to outbid highest bidder");
      });
    });

    describe("successfully places bid with MATIC", () => {
      beforeEach(async () => {
        await auction.setNowOverride("1");
        await auction.connect(minter).createAuction(
          nft.address,
          firstTokenId,
          "1", // reserve
          false,
          "2", // start
          "400" as any // end
        );
      });

      it("places bid and you are the top owner", async () => {
        await auction.setNowOverride("2");
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
          value: BigNumber.from(200000000000000000n),
        });

        const { _bidder, _bid } = await auction.getHighestBidder(
          nft.address,
          firstTokenId
        );
        expect(_bid).to.be.equal(BigNumber.from(200000000000000000n));
        expect(_bidder).to.equal(buyer.address);
        const { _reservePrice, _startTime, _endTime, _resulted } =
          await auction.getAuction(nft.address, firstTokenId);
        expect(_reservePrice).to.be.equal("1");
        expect(_startTime).to.be.equal("2");
        expect(_endTime).to.be.equal("400");
        expect(_resulted).to.be.equal(false);
      });

      it("will refund the top bidder if found", async () => {
        await auction.setNowOverride("2");
        await auction
          .connect(buyer)
          .placeBid(nft.address, firstTokenId, false, "0", { value: "200000000000000000" });

        const { _bidder: originalBidder, _bid: originalBid } =
          await auction.getHighestBidder(nft.address, firstTokenId);
        expect(originalBid).to.be.equal(200000000000000000n);
        expect(originalBidder).to.equal(buyer.address);

        // make a new bid, out bidding the previous bidder
        await expect(() =>
          auction.connect(buyer2).placeBid(nft.address, firstTokenId, false, "0", {
            value: "400000000000000000",
          })
        ).to.changeEtherBalances(
          [buyer, buyer2],
          [200000000000000000n, -400000000000000000n]
        );

        const { _bidder, _bid } = await auction.getHighestBidder(
          nft.address,
          firstTokenId
        );
        expect(_bid).to.be.equal(400000000000000000n);
        expect(_bidder).to.equal(buyer2.address);
      });

      it("increases bid", async () => {
        await auction.setNowOverride("2");

        await expect(() =>
          auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
            value: "200000000000000000",
          })
        ).to.changeEtherBalances([buyer], [-200000000000000000n]);

        const { _bidder, _bid } = await auction.getHighestBidder(
          nft.address,
          firstTokenId
        );
        expect(_bid).to.be.equal(200000000000000000n);
        expect(_bidder).to.equal(buyer.address);

        await expect(() =>
          auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
            value: "1000000000000000000",
          })
        ).to.changeEtherBalances(
          [buyer],
          [-1000000000000000000n + 200000000000000000n]
        );

        const { _bidder: newBidder, _bid: newBid } =
          await auction.getHighestBidder(nft.address, firstTokenId);
        expect(newBid).to.be.equal(1000000000000000000n);
        expect(newBidder).to.equal(buyer.address);
      });

      it("outbid bidder", async () => {
        await auction.setNowOverride("2");

        // Bidder 1 makes first bid
        await expect(() =>
          auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
            value: "200000000000000000",
          })
        ).to.changeEtherBalances([buyer], [-200000000000000000n]);

        const { _bidder, _bid } = await auction.getHighestBidder(
          nft.address,
          firstTokenId
        );
        expect(_bid).to.be.equal(200000000000000000n);
        expect(_bidder).to.equal(buyer.address);

        // Bidder 2 outbids bidder 1
        await expect(() =>
          auction.connect(buyer2).placeBid(nft.address, firstTokenId, false, "0", {
            value: "1000000000000000000",
          })
        ).to.changeEtherBalances(
          [buyer, buyer2],
          [200000000000000000n, -1000000000000000000n]
        );

        const { _bidder: newBidder, _bid: newBid } =
          await auction.getHighestBidder(nft.address, firstTokenId);
        expect(newBid).to.be.equal(1000000000000000000n);
        expect(newBidder).to.equal(buyer2.address);
      });
    });

    describe("successfully places bid with OGUN", () => {
      beforeEach(async () => {
        await auction.setNowOverride("1");
        await auction.connect(minter).createAuction(
          nft.address,
          firstTokenId,
          "1", // reserve
          true,
          "2", // start
          "400" as any // end
        );
      });

      it("places bid and you are the top owner", async () => {
        await auction.setNowOverride("2");
        await OGUN.connect(buyer).approve(auction.address, BigNumber.from(200000000000000000n));
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, true, "200000000000000000");

        const { _bidder, _bid } = await auction.getHighestBidder(
          nft.address,
          firstTokenId
        );
        expect(_bid).to.be.equal(BigNumber.from(200000000000000000n));
        expect(_bidder).to.equal(buyer.address);
        const { _reservePrice, _startTime, _endTime, _resulted } =
          await auction.getAuction(nft.address, firstTokenId);
        expect(_reservePrice).to.be.equal("1");
        expect(_startTime).to.be.equal("2");
        expect(_endTime).to.be.equal("400");
        expect(_resulted).to.be.equal(false);
      });

      it("will refund the top bidder if found", async () => {
        await auction.setNowOverride("2");
        await OGUN.connect(buyer).approve(auction.address, "200000000000000000");
        await OGUN.connect(buyer2).approve(auction.address, "400000000000000000");
        await auction
          .connect(buyer)
          .placeBid(nft.address, firstTokenId, true, "200000000000000000");

        const { _bidder: originalBidder, _bid: originalBid } =
          await auction.getHighestBidder(nft.address, firstTokenId);
        expect(originalBid).to.be.equal(200000000000000000n);
        expect(originalBidder).to.equal(buyer.address);
        
        // make a new bid, out bidding the previous bidder  
        await auction.connect(buyer2).placeBid(nft.address, firstTokenId, true, "400000000000000000");

        const buyerBalance = await OGUN.balanceOf(buyer.address);

        const { _bidder, _bid } = await auction.getHighestBidder(
          nft.address,
          firstTokenId
        );
        expect(buyerBalance).to.be.equal(1000000000000000000000000n);
        expect(_bid).to.be.equal(400000000000000000n);
        expect(_bidder).to.equal(buyer2.address);
      });

      it("increases bid", async () => {
        await OGUN.connect(buyer).approve(auction.address, "1200000000000000000");
        await auction.setNowOverride("2");

        await auction.connect(buyer).placeBid(nft.address, firstTokenId, true, "200000000000000000");

        let buyerBalance = await OGUN.balanceOf(buyer.address);
        expect(buyerBalance).to.be.equal(999999800000000000000000n);

        const { _bidder, _bid } = await auction.getHighestBidder(
          nft.address,
          firstTokenId
        );
        expect(_bid).to.be.equal(200000000000000000n); //-2
        expect(_bidder).to.equal(buyer.address);

        await auction.connect(buyer).placeBid(nft.address, firstTokenId, true, "1000000000000000000");
        buyerBalance = await OGUN.balanceOf(buyer.address);
        expect(buyerBalance).to.be.equal(999999000000000000000000n); //+2 reimbursed , -10 from new bid

        const { _bidder: newBidder, _bid: newBid } =
          await auction.getHighestBidder(nft.address, firstTokenId);
        expect(newBid).to.be.equal(1000000000000000000n);
        expect(newBidder).to.equal(buyer.address);
      });

      it("outbid bidder", async () => {
        await OGUN.connect(buyer).approve(auction.address, "1000000000000000000");
        await OGUN.connect(buyer2).approve(auction.address, "1000000000000000000");
        await auction.setNowOverride("2");

        // Bidder 1 makes first bid
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, true, "200000000000000000");
        const { _bidder, _bid } = await auction.getHighestBidder(
          nft.address,
          firstTokenId
        );

        expect(_bid).to.be.equal(200000000000000000n);
        expect(_bidder).to.equal(buyer.address);

        // Bidder 2 outbids bidder 1
        await auction.connect(buyer2).placeBid(nft.address, firstTokenId, true, "1000000000000000000");

        const { _bidder: newBidder, _bid: newBid } =
          await auction.getHighestBidder(nft.address, firstTokenId);
        expect(newBid).to.be.equal(1000000000000000000n);
        expect(newBidder).to.equal(buyer2.address);
      });
    });
  });

  describe("result auction", async () => {
    describe("validation", () => {
      beforeEach(async () => {
        await auction.setNowOverride("2");
        await auction
          .connect(minter)
          .createAuction(nft.address, firstTokenId, "2", false, "3", "400" as any);
      });

      it("reverts if it's not the owner", async () => {
        await auction.setNowOverride("4");
        await auction.connect(buyer2).placeBid(nft.address, firstTokenId, false, "0", {
          value: 2000000000000n,
        });
        await auction.setNowOverride("40000");
        await expect(
          auction.connect(buyer).resultAuction(nft.address, firstTokenId)
        ).to.be.revertedWith("sender must be item owner or winner");
      });

      it("reverts if auction has not ended", async () => {
        await expect(
          auction.connect(minter).resultAuction(nft.address, firstTokenId)
        ).to.be.revertedWith("auction not ended");
      });

      it("reverts if the auction has no winner", async () => {
        await auction.setNowOverride("40000");
        await expect(
          auction.connect(minter).resultAuction(nft.address, firstTokenId)
        ).to.be.revertedWith("no open bids");
      });

      it("reverts if the auction if its already resulted", async () => {
        await auction.setNowOverride("4");
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
          value: 1000000000000n,
        });
        await auction.setNowOverride("40000");

        await auction.connect(minter).resultAuction(nft.address, firstTokenId);

        await expect(
          auction.connect(minter).resultAuction(nft.address, firstTokenId)
        ).to.be.revertedWith("sender must be item owner");
      });
    });

    describe("successfully resulting an OGUN auction", async () => {
      beforeEach(async () => {
        await auction.setNowOverride("2");
        await auction
          .connect(minter)
          .createAuction(nft.address, firstTokenId, "1", true, "3", "400" as any);
        await auction.setNowOverride("4");
        await OGUN.connect(buyer).approve(auction.address, BigNumber.from(1000000000000000000n));
      });


      it("transfer token to the winner using OGUN", async () => {
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, true, "2000000000000");
        await auction.setNowOverride("40000");

        expect(await nft.ownerOf(firstTokenId)).to.be.equal(minter.address);

        await auction.connect(minter).resultAuction(nft.address, firstTokenId);

        expect(await nft.ownerOf(firstTokenId)).to.be.equal(buyer.address);
      });

      it("transfer OGUN funds to the token creator and platform", async () => {
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, true, "1000000000000000000");
        await auction.setNowOverride("40000");

        await auction.connect(minter).resultAuction(nft.address, firstTokenId);

        const minterBalance = await OGUN.balanceOf(minter.address);
        const feeAddressBalance = await OGUN.balanceOf(feeAddress.address);

        expect(minterBalance).to.be.equal(1075000000000000000n); // 975000000000000000n + reward
        expect(feeAddressBalance).to.be.equal(25000000000000000n);
      });

      it("buyer can result the OGUN auction", async () => {
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, true, "1000000000000000000");
        await auction.setNowOverride("40000");

        await auction.connect(buyer).resultAuction(nft.address, firstTokenId);

        const minterBalance = await OGUN.balanceOf(minter.address);
        const feeAddressBalance = await OGUN.balanceOf(feeAddress.address);

        expect(minterBalance).to.be.equal(1075000000000000000n); //975000000000000000n + reward
        expect(feeAddressBalance).to.be.equal(25000000000000000n);
      });
    });
    
    describe("successfully resulting an auction", async () => {
      beforeEach(async () => {
        await auction.setNowOverride("2");
        await auction
          .connect(minter)
          .createAuction(nft.address, firstTokenId, "1", false, "3", "400" as any);
        await auction.setNowOverride("4");
      });

      it("transfer token to the winner", async () => {
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
          value: 2000000000000n,
        });
        await auction.setNowOverride("40000");

        expect(await nft.ownerOf(firstTokenId)).to.be.equal(minter.address);

        await auction.connect(minter).resultAuction(nft.address, firstTokenId);

        expect(await nft.ownerOf(firstTokenId)).to.be.equal(buyer.address);
      });

      it("transfer funds to the token creator and platform", async () => {
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
          value: 1000000000000000000n,
        });
        await auction.setNowOverride("40000");

        await expect(() =>
          auction.connect(minter).resultAuction(nft.address, firstTokenId)
        ).to.changeEtherBalances(
          [minter, feeAddress],
          [975000000000000000n, 25000000000000000n]
        );
      });

      it("buyer can result the auction", async () => {
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
          value: 1000000000000000000n,
        });
        await auction.setNowOverride("40000");

        await expect(() =>
          auction.connect(buyer).resultAuction(nft.address, firstTokenId)
        ).to.changeEtherBalances(
          [minter, feeAddress],
          [975000000000000000n, 25000000000000000n]
        );
      });
    });
  });

  describe("cancel auction", async () => {
    beforeEach(async () => {
      await auction.setNowOverride("2");
      await auction
        .connect(minter)
        .createAuction(nft.address, firstTokenId, "1", false, "3", "400" as any);
      await auction.setNowOverride("3");
    });

    describe("validation", async () => {
      it("reverts if not an admin", async () => {
        await expect(
          auction.connect(buyer).cancelAuction(nft.address, firstTokenId)
        ).to.be.revertedWith("sender must be owner");
      });

      it("reverts if auction already cancelled", async () => {
        await auction.connect(minter).cancelAuction(nft.address, firstTokenId);

        await expect(
          auction.connect(minter).cancelAuction(nft.address, firstTokenId)
        ).to.be.revertedWith("sender must be owner");
      });

      it("reverts if auction already resulted", async () => {
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
          value: 20000000n,
        });
        await auction.setNowOverride("40000");

        await auction.connect(minter).resultAuction(nft.address, firstTokenId);

        await expect(
          auction.connect(minter).cancelAuction(nft.address, firstTokenId)
        ).to.be.revertedWith("sender must be owner");
      });

      it("cancel clears down auctions and top bidder", async () => {
        await auction.connect(minter).cancelAuction(nft.address, firstTokenId);

        const { _reservePrice, _startTime, _endTime, _resulted } =
          await auction.getAuction(nft.address, firstTokenId);
        expect(_reservePrice).to.be.equal("0");
        expect(_startTime).to.be.equal("0");
        expect(_endTime).to.be.equal("0");
        expect(_resulted).to.be.equal(false);

        const { _bidder, _bid } = await auction.getHighestBidder(
          nft.address,
          firstTokenId
        );
        expect(_bid).to.be.equal("0");
        expect(_bidder).to.equal("0x0000000000000000000000000000000000000000");
      });
    });
  });

  describe("update auction", async () => {
    beforeEach(async () => {
      await auction.setNowOverride("2");
      await auction.connect(minter).createAuction(
        nft.address,
        firstTokenId, // ID
        "1", // reserve
        false,
        "3", // start
        "400" as any // end
      );
      await auction.setNowOverride("4");
    });

    it("reverts if there is a bid already", async () => {
      await auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
        value: 200000000n,
      });

      await expect(
        auction
          .connect(minter)
          .updateAuction(nft.address, firstTokenId, "2", false, "3000", "300000" as any)
      ).to.be.revertedWith("can not update if auction has a bid already");
    });

    it("successfully update auction", async () => {
      await auction
        .connect(minter)
        .updateAuction(nft.address, firstTokenId, "2", false, "3000", "300000" as any);

      const { _reservePrice, _startTime, _endTime, _resulted } =
        await auction.getAuction(nft.address, firstTokenId);
      expect(_reservePrice).to.be.equal("2");
      expect(_startTime).to.be.equal("3000");
      expect(_endTime).to.be.equal("300000");
      expect(_resulted).to.be.equal(false);
    });
  });

  describe("update OGUN auction", async () => {
    beforeEach(async () => {
      await auction.setNowOverride("2");
      await auction.connect(minter).createAuction(
        nft.address,
        firstTokenId, // ID
        "1", // reserve
        true,
        "3", // start
        "400" as any // end
      );
      await auction.setNowOverride("4");
      await OGUN.connect(buyer).approve(auction.address, BigNumber.from(1000000000000000000n));
    });

    it("reverts if there is a bid already", async () => {
      await auction.connect(buyer).placeBid(nft.address, firstTokenId, true, "200000000");

      await expect(
        auction
          .connect(minter)
          .updateAuction(nft.address, firstTokenId, "2", true, "3000", "300000" as any)
      ).to.be.revertedWith("can not update if auction has a bid already");
    });

    it("successfully update OGUN auction to MATIC auction", async () => {
      await auction
        .connect(minter)
        .updateAuction(nft.address, firstTokenId, "2", false, "3000", "300000" as any);

      const { _reservePrice, _isPaymentOGUN, _startTime, _endTime, _resulted } =
        await auction.getAuction(nft.address, firstTokenId);
      expect(_reservePrice).to.be.equal("2");
      expect(_startTime).to.be.equal("3000");
      expect(_endTime).to.be.equal("300000");
      expect(_isPaymentOGUN).to.be.equal(false);
      expect(_resulted).to.be.equal(false);
    });
  });

  describe("create, cancel and re-create an auction", async () => {
    beforeEach(async () => {
      await auction.setNowOverride("2");
      await auction.connect(minter).createAuction(
        nft.address,
        firstTokenId, // ID
        "1", // reserve
        false,
        "3", // start
        "400" as any // end
      );
      await auction.setNowOverride("4");
    });

    it("once created and then cancelled, can be created and resulted properly", async () => {
      await auction.connect(minter).cancelAuction(nft.address, firstTokenId);

      const { _reservePrice, _startTime, _endTime, _resulted } =
        await auction.getAuction(nft.address, firstTokenId);
      expect(_reservePrice).to.be.equal("0");
      expect(_startTime).to.be.equal("0");
      expect(_endTime).to.be.equal("0");
      expect(_resulted).to.be.equal(false);

      await auction.connect(minter).createAuction(
        nft.address,
        firstTokenId, // ID
        "1", // reserve
        false,
        "5", // start
        "401" as any // end
      );

      const {
        _reservePrice: newReservePrice,
        _startTime: newStartTime,
        _endTime: newEndTime,
        _resulted: newResulted,
      } = await auction.getAuction(nft.address, firstTokenId);
      expect(newReservePrice).to.be.equal("1");
      expect(newStartTime).to.be.equal("5");
      expect(newEndTime).to.be.equal("401");
      expect(newResulted).to.be.equal(false);

      await auction.setNowOverride("6");

      await auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
        value: 200000000n,
      });

      await auction.setNowOverride("4000");

      await auction.connect(minter).resultAuction(nft.address, firstTokenId);
    });
  });

  describe("create, cancel and re-create an OGUN auction", async () => {
    beforeEach(async () => {
      await auction.setNowOverride("2");
      await auction.connect(minter).createAuction(
        nft.address,
        firstTokenId, // ID
        "1", // reserve
        true,
        "3", // start
        "400" as any // end
      );
      await auction.setNowOverride("4");
      await OGUN.connect(buyer).approve(auction.address, BigNumber.from(1000000000000000000n));
    });

    it("once created and then cancelled, can be created and resulted properly", async () => {
      await auction.connect(minter).cancelAuction(nft.address, firstTokenId);

      const { _reservePrice, _isPaymentOGUN, _startTime, _endTime, _resulted } =
        await auction.getAuction(nft.address, firstTokenId);
      expect(_reservePrice).to.be.equal("0");
      expect(_isPaymentOGUN).to.be.equal(false);
      expect(_startTime).to.be.equal("0");
      expect(_endTime).to.be.equal("0");
      expect(_resulted).to.be.equal(false);

      await auction.connect(minter).createAuction(
        nft.address,
        firstTokenId, // ID
        "1", // reserve
        true,
        "5", // start
        "401" as any // end
      );

      const {
        _reservePrice: newReservePrice,
        _isPaymentOGUN: newIsPaymentOGUN,
        _startTime: newStartTime,
        _endTime: newEndTime,
        _resulted: newResulted,
      } = await auction.getAuction(nft.address, firstTokenId);
      expect(newReservePrice).to.be.equal("1");
      expect(newIsPaymentOGUN).to.be.equal(true);
      expect(newStartTime).to.be.equal("5");
      expect(newEndTime).to.be.equal("401");
      expect(newResulted).to.be.equal(false);

      await auction.setNowOverride("6");

      await auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
        value: 200000000n,
      });

      await auction.setNowOverride("4000");

      await auction.connect(minter).resultAuction(nft.address, firstTokenId);
    });
  });

  describe("royalties", () => {
    beforeEach(async () => {
      nft.connect(minter).setApprovalForAll(auction.address, true);
    });

    it("successfully transfer royalties", async () => {
      await nft
        .connect(minter)
        .setApprovalForAll(auction.address, true);
      await nft.connect(buyer).setApprovalForAll(auction.address, true);

      await auction.setNowOverride("2");
      await auction.connect(minter).createAuction(
        nft.address,
        firstTokenId, // ID
        "1", // reserve
        false,
        "3", // start
        "400" as any // end
      );
      await auction.setNowOverride("4");

      await auction.connect(buyer).placeBid(nft.address, firstTokenId, false, "0", {
        value: 200000000n,
      });

      await auction.setNowOverride("4000");

      await auction.connect(buyer).resultAuction(nft.address, firstTokenId)


      await auction.setNowOverride("2");
      await auction.connect(buyer).createAuction(
        nft.address,
        firstTokenId, // ID
        "1", // reserve
        false,
        "3", // start
        "400" as any // end
      );
      await auction.setNowOverride("4");

      await auction.connect(buyer2).placeBid(nft.address, firstTokenId, false, "0", {
        value: 1000000000000000000n,
      });

      await auction.setNowOverride("4000");

      await expect(() =>
        auction.connect(buyer2).resultAuction(nft.address, firstTokenId)
      ).to.changeEtherBalances(
        [feeAddress, buyer, minter],
        [25000000000000000n, 877500000000000000n, 97500000000000000n]
      );
    });
  });

  describe("royalties using OGUN", () => {
    beforeEach(async () => {
      nft.connect(minter).setApprovalForAll(auction.address, true);
      await OGUN.connect(buyer).approve(auction.address, BigNumber.from(1000000000000000000n));
      await OGUN.connect(buyer2).approve(auction.address, BigNumber.from(1000000000000000000n));
    });

    it("successfully transfer royalties using OGUN", async () => {
      await nft
        .connect(minter)
        .setApprovalForAll(auction.address, true);
      await nft.connect(buyer).setApprovalForAll(auction.address, true);

      await auction.setNowOverride("2");
      await auction.connect(minter).createAuction(
        nft.address,
        firstTokenId, // ID
        "1", // reserve
        true, // payment is OGUN
        "3", // start
        "400" as any // end
      );
      await auction.setNowOverride("4");

      await auction.connect(buyer).placeBid(nft.address, firstTokenId, true, "200000000");
      // Fee 5000000
      // seller/minter Fee 195000000
      // Buyer Balance 999999999999999800000000

      await auction.setNowOverride("4000");

      await auction.connect(buyer).resultAuction(nft.address, firstTokenId);

      const feeAddressBalance1 = await OGUN.balanceOf(feeAddress.address);
      const buyerBalance1 = await OGUN.balanceOf(buyer.address);
      const minterBalance1 = await OGUN.balanceOf(minter.address);

      console.log('1feeAddressBalance: ', feeAddressBalance1);
      console.log('1buyerBalance: ', buyerBalance1);
      console.log('1minterBalance: ', minterBalance1);


      await auction.setNowOverride("2");
      await auction.connect(buyer).createAuction(
        nft.address,
        firstTokenId, // ID
        "1", // reserve
        true, // payment is OGUN
        "3", // start
        "400" as any // end
      );
      await auction.setNowOverride("4");

      await auction.connect(buyer2).placeBid(nft.address, firstTokenId, true, "1000000000000000000");

      await auction.setNowOverride("4000");

      await auction.connect(buyer2).resultAuction(nft.address, firstTokenId);

      const feeAddressBalance = await OGUN.balanceOf(feeAddress.address);
      const buyerBalance = await OGUN.balanceOf(buyer.address);
      const minterBalance = await OGUN.balanceOf(minter.address);
      const buyer2Balance = await OGUN.balanceOf(buyer2.address);
      //Fee 25000000000000000 + 5000000 (Previous auction)
      // seller(buyer1) balance 877500000000000000 + 999999999999999800000000 (Previous auction)
      // Minter balance 97500000000000000 + 195000000 (Previous auction)

      expect(feeAddressBalance).to.be.equal(25000000005000000n);
      expect(buyerBalance).to.be.equal(1000000977499999820000000n);//1000000877499999800000000n + reward
      expect(minterBalance).to.be.equal(97500000215000000n); //97500000195000000 + reward
      expect(buyer2Balance).to.be.equal(999999100000000000000000n); // + reward
    });
  });
});
