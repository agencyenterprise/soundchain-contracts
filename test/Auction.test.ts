import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import {
  Soundchain721,
  Soundchain721__factory,
  SoundchainAuctionMock,
  SoundchainAuctionMock__factory,
} from "../typechain-types";

describe("auction", () => {
  const firstTokenId = "0";
  const secondTokenId = "1";
  const platformFee = "25"; // marketplace platform fee: 2.5%
  const tokenUri = "ipfs";

  let owner: SignerWithAddress,
    minter: SignerWithAddress,
    buyer: SignerWithAddress,
    buyer2: SignerWithAddress,
    nft: Soundchain721,
    feeAddress: SignerWithAddress,
    auction: SoundchainAuctionMock;

  beforeEach(async () => {
    [owner, minter, buyer, feeAddress, buyer2] = await ethers.getSigners();

    const SoundchainCollectible: Soundchain721__factory =
      await ethers.getContractFactory("Soundchain721");
    nft = await SoundchainCollectible.deploy();

    const AuctionFactory: SoundchainAuctionMock__factory =
      await ethers.getContractFactory("SoundchainAuctionMock");
    auction = await AuctionFactory.deploy(feeAddress.address, platformFee);

    await nft.safeMint(minter.address, tokenUri, 10);
    await nft.safeMint(owner.address, tokenUri, 10);
    await nft.safeMint(minter.address, tokenUri, 10);
    await nft.connect(minter).setApprovalForAll(auction.address, true);
    await nft.connect(owner).setApprovalForAll(auction.address, true);
  });

  describe("create auction", () => {
    describe("validation", async () => {
      it("reverts if endTime is in the past", async () => {
        await auction.setNowOverride("12");
        await expect(
          auction
            .connect(minter)
            .createAuction(nft.address, firstTokenId, "1", "13", "10")
        ).to.be.revertedWith(
          "end time must be greater than start (by 5 minutes)"
        );
      });

      it("reverts if startTime less than now", async () => {
        await auction.setNowOverride("2");
        await expect(
          auction
            .connect(minter)
            .createAuction(nft.address, firstTokenId, "1", "1", "4000")
        ).to.be.revertedWith("invalid start time");
      });

      it("reverts if nft already has auction in play", async () => {
        await auction
          .connect(minter)
          .createAuction(
            nft.address,
            firstTokenId,
            "1",
            "10000000000000",
            "100000000000000"
          );

        expect(
          auction
            .connect(minter)
            .createAuction(
              nft.address,
              firstTokenId,
              "1",
              "10000000000000",
              "100000000000000"
            )
        ).to.be.revertedWith("auction already started");
      });

      it("reverts if token does not exist", async () => {
        await auction.setNowOverride("10");

        await expect(
          auction
            .connect(minter)
            .createAuction(nft.address, "99", "1", "1", "400")
        ).to.be.revertedWith("ERC721: owner query for nonexistent token");
      });

      it("reverts if contract is paused", async () => {
        await auction.setNowOverride("2");
        await auction.connect(owner).toggleIsPaused();
        await expect(
          auction
            .connect(minter)
            .createAuction(nft.address, firstTokenId, "1", "0", "400")
        ).to.be.revertedWith("contract paused");
      });

      it("reverts if you don't own the nft", async () => {
        await auction
          .connect(minter)
          .createAuction(
            nft.address,
            firstTokenId,
            "1",
            "10000000000000",
            "100000000000000"
          );

        expect(
          auction
            .connect(minter)
            .createAuction(nft.address, secondTokenId, "1", "1", "3")
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
            "10000000000000",
            "100000000000000"
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
          "3", // start
          "400" // end
        );
      });

      it("reverts with 721 token not on auction", async () => {
        await expect(
          auction.connect(buyer).placeBid(nft.address, 999, { value: 1 })
        ).to.be.revertedWith("bidding outside of the auction window");
      });

      it("reverts with valid token but no auction", async () => {
        await expect(
          auction.connect(buyer).placeBid(nft.address, firstTokenId, {
            value: 1,
          })
        ).to.be.revertedWith("bidding outside of the auction window");
      });

      it("reverts when auction finished", async () => {
        await auction.setNowOverride("500");
        await expect(
          auction.connect(buyer).placeBid(nft.address, firstTokenId, {
            value: 1,
          })
        ).to.be.revertedWith("bidding outside of the auction window");
      });

      it("reverts when contract is paused", async () => {
        await auction.connect(owner).toggleIsPaused();
        await expect(
          auction.connect(buyer).placeBid(nft.address, firstTokenId, {
            value: 10000000,
          })
        ).to.be.revertedWith("contract paused");
      });

      it("reverts when outbidding someone by less than the increment", async () => {
        await auction.setNowOverride("4");
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, {
          value: 20000000,
        });

        await expect(
          auction.connect(buyer).placeBid(nft.address, firstTokenId, {
            value: 20000000,
          })
        ).to.be.revertedWith("failed to outbid highest bidder");
      });
    });

    describe("successfully places bid", () => {
      beforeEach(async () => {
        await auction.setNowOverride("1");
        await auction.connect(minter).createAuction(
          nft.address,
          firstTokenId,
          "1", // reserve
          "2", // start
          "400" // end
        );
      });

      it("places bid and you are the top owner", async () => {
        await auction.setNowOverride("2");
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, {
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
          .placeBid(nft.address, firstTokenId, { value: "200000000000000000" });

        const { _bidder: originalBidder, _bid: originalBid } =
          await auction.getHighestBidder(nft.address, firstTokenId);
        expect(originalBid).to.be.equal(200000000000000000n);
        expect(originalBidder).to.equal(buyer.address);

        // make a new bid, out bidding the previous bidder
        await expect(() =>
          auction.connect(buyer2).placeBid(nft.address, firstTokenId, {
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
          auction.connect(buyer).placeBid(nft.address, firstTokenId, {
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
          auction.connect(buyer).placeBid(nft.address, firstTokenId, {
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
          auction.connect(buyer).placeBid(nft.address, firstTokenId, {
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
          auction.connect(buyer2).placeBid(nft.address, firstTokenId, {
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
  });

  describe("result auction", async () => {
    describe("validation", () => {
      beforeEach(async () => {
        await auction.setNowOverride("2");
        await auction
          .connect(minter)
          .createAuction(nft.address, firstTokenId, "2", "3", "400");
      });

      it("reverts if it's not the owner", async () => {
        await auction.setNowOverride("4");
        await auction.connect(buyer2).placeBid(nft.address, firstTokenId, {
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
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, {
          value: 1000000000000n,
        });
        await auction.setNowOverride("40000");

        await auction.connect(minter).resultAuction(nft.address, firstTokenId);

        await expect(
          auction.connect(minter).resultAuction(nft.address, firstTokenId)
        ).to.be.revertedWith("sender must be item owner");
      });
    });

    describe("successfully resulting an auction", async () => {
      beforeEach(async () => {
        await auction.setNowOverride("2");
        await auction
          .connect(minter)
          .createAuction(nft.address, firstTokenId, "1", "3", "400");
        await auction.setNowOverride("4");
      });

      it("transfer token to the winner", async () => {
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, {
          value: 2000000000000n,
        });
        await auction.setNowOverride("40000");

        expect(await nft.ownerOf(firstTokenId)).to.be.equal(minter.address);

        await auction.connect(minter).resultAuction(nft.address, firstTokenId);

        expect(await nft.ownerOf(firstTokenId)).to.be.equal(buyer.address);
      });

      it("transfer funds to the token creator and platform", async () => {
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, {
          value: 4000000000000n,
        });
        await auction.setNowOverride("40000");

        await expect(() =>
          auction.connect(minter).resultAuction(nft.address, firstTokenId)
        ).to.changeEtherBalances(
          [minter, feeAddress],
          [3900000000001n, 99999999999n]
        );
      });

      it("buyer can result the auction", async () => {
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, {
          value: 4000000000000n,
        });
        await auction.setNowOverride("40000");

        await expect(() =>
          auction.connect(buyer).resultAuction(nft.address, firstTokenId)
        ).to.changeEtherBalances(
          [minter, feeAddress],
          [3900000000001n, 99999999999n]
        );
      });
    });
  });

  describe("cancel auction", async () => {
    beforeEach(async () => {
      await auction.setNowOverride("2");
      await auction
        .connect(minter)
        .createAuction(nft.address, firstTokenId, "1", "3", "400");
      await auction.setNowOverride("3");
    });

    describe("validation", async () => {
      it("reverts if not an admin", async () => {
        await expect(
          auction.connect(buyer).cancelAuction(nft.address, firstTokenId)
        ).to.be.revertedWith("sender must be owner");
      });

      it("reverts if auction already cancelled", async () => {
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, {
          value: 20000000n,
        });
        await auction.setNowOverride("12");

        await auction.connect(minter).cancelAuction(nft.address, firstTokenId);

        await expect(
          auction.connect(minter).cancelAuction(nft.address, firstTokenId)
        ).to.be.revertedWith("sender must be owner");
      });

      it("reverts if auction already resulted", async () => {
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, {
          value: 20000000n,
        });
        await auction.setNowOverride("40000");

        await auction.connect(minter).resultAuction(nft.address, firstTokenId);

        await expect(
          auction.connect(minter).cancelAuction(nft.address, firstTokenId)
        ).to.be.revertedWith("sender must be owner");
      });

      it("cancel clears down auctions and top bidder", async () => {
        // Stick a bid on it
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, {
          value: 20000000n,
        });

        // Cancel it
        await auction.connect(minter).cancelAuction(nft.address, firstTokenId);

        // Check auction cleaned up
        const { _reservePrice, _startTime, _endTime, _resulted } =
          await auction.getAuction(nft.address, firstTokenId);
        expect(_reservePrice).to.be.equal("0");
        expect(_startTime).to.be.equal("0");
        expect(_endTime).to.be.equal("0");
        expect(_resulted).to.be.equal(false);

        // Check auction cleaned up
        const { _bidder, _bid } = await auction.getHighestBidder(
          nft.address,
          firstTokenId
        );
        expect(_bid).to.be.equal("0");
        expect(_bidder).to.equal("0x0000000000000000000000000000000000000000");
      });

      it("funds are sent back to the highest bidder if found", async () => {
        // Stick a bid on it
        await auction.connect(buyer).placeBid(nft.address, firstTokenId, {
          value: 20000000n,
        });

        // const bidderTracker = await balance.tracker(bidder);

        //cancel it
        await auction.connect(minter).cancelAuction(nft.address, firstTokenId);

        // Funds sent back
        // const changes = await bidderTracker.delta("wei");
        // expect(changes).to.be.bignumber.equal(ether("0.2"));
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
        "3", // start
        "400" // end
      );
      await auction.setNowOverride("4");
    });

    it("reverts if there is a bid already", async () => {
      await auction.connect(buyer).placeBid(nft.address, firstTokenId, {
        value: 200000000n,
      });

      await expect(
        auction
          .connect(minter)
          .updateAuction(nft.address, firstTokenId, "2", "3000", "300000")
      ).to.be.revertedWith("can not update if auction has a bid already");
    });

    it("successfully update auction", async () => {
      await auction
        .connect(minter)
        .updateAuction(nft.address, firstTokenId, "2", "3000", "300000");

      const { _reservePrice, _startTime, _endTime, _resulted } =
        await auction.getAuction(nft.address, firstTokenId);
      expect(_reservePrice).to.be.equal("2");
      expect(_startTime).to.be.equal("3000");
      expect(_endTime).to.be.equal("300000");
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
        "3", // start
        "400" // end
      );
      await auction.setNowOverride("4");
    });

    it("once created and then cancelled, can be created and resulted properly", async () => {
      // Stick a bid on it
      await auction.connect(buyer).placeBid(nft.address, firstTokenId, {
        value: 200000000n,
      });

      // const bidderTracker = await balance.tracker(bidder);

      // Cancel it
      await auction.connect(minter).cancelAuction(nft.address, firstTokenId);

      // Funds sent back to bidder
      // const changes = await bidderTracker.delta("wei");
      // expect(changes).to.be.bignumber.equal(ether("0.2"));

      // Check auction cleaned up
      const { _reservePrice, _startTime, _endTime, _resulted } =
        await auction.getAuction(nft.address, firstTokenId);
      expect(_reservePrice).to.be.equal("0");
      expect(_startTime).to.be.equal("0");
      expect(_endTime).to.be.equal("0");
      expect(_resulted).to.be.equal(false);

      // Crate new one
      await auction.connect(minter).createAuction(
        nft.address,
        firstTokenId, // ID
        "1", // reserve
        "5", // start
        "401" // end
      );

      // Check auction newly setup
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

      // Stick a bid on it
      await auction.connect(buyer).placeBid(nft.address, firstTokenId, {
        value: 200000000n,
      });

      await auction.setNowOverride("4000");

      // Result it
      await auction.connect(minter).resultAuction(nft.address, firstTokenId);
    });
  });
});
