import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, Contract } from "ethers";
import { ethers } from "hardhat";
import {
  Soundchain721,
  Soundchain721__factory,
  SoundchainAuctionMock__factory,
} from "../typechain";

describe("Auction and Soundchain Token", () => {
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
    auction: Contract;

  beforeEach(async () => {
    [owner, minter, buyer, feeAddress, buyer2] = await ethers.getSigners();

    const SoundchainCollectible: Soundchain721__factory =
      await ethers.getContractFactory("Soundchain721");
    nft = await SoundchainCollectible.deploy();

    const AuctionFactory: SoundchainAuctionMock__factory =
      await ethers.getContractFactory("SoundchainAuctionMock");

    auction = await AuctionFactory.deploy(feeAddress.address, platformFee);

    await nft.safeMint(minter.address, tokenUri);
    await nft.safeMint(owner.address, tokenUri);
    await nft.safeMint(minter.address, tokenUri);
    await nft.connect(minter).setApprovalForAll(auction.address, true);
    await nft.connect(owner).setApprovalForAll(auction.address, true);
  });

  describe("Listing Item", () => {
    describe("validation", async () => {
      it("reverts if endTime is in the past", async () => {
        await auction.setNowOverride("12");
        await expect(
          auction
            .connect(minter)
            .createAuction(nft.address, firstTokenId, "1", "13", true, "10")
        ).to.be.revertedWith(
          "end time must be greater than start (by 5 minutes)"
        );
      });

      it("reverts if startTime less than now", async () => {
        await auction.setNowOverride("2");
        await expect(
          auction
            .connect(minter)
            .createAuction(nft.address, firstTokenId, "1", "1", true, "4000")
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
            true,
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
              true,
              "100000000000000"
            )
        ).to.be.revertedWith("auction already started");
      });

      it("reverts if token does not exist", async () => {
        await auction.setNowOverride("10");

        await expect(
          auction
            .connect(minter)
            .createAuction(nft.address, "99", "1", "1", true, "400")
        ).to.be.revertedWith("ERC721: owner query for nonexistent token");
      });

      it("reverts if contract is paused", async () => {
        await auction.setNowOverride("2");
        await auction.connect(owner).toggleIsPaused();
        await expect(
          auction
            .connect(minter)
            .createAuction(nft.address, firstTokenId, "1", "0", true, "400")
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
            true,
            "100000000000000"
          );

        expect(
          auction
            .connect(minter)
            .createAuction(nft.address, secondTokenId, "1", "1", true, "3")
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
            true,
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
          true,
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
          true,
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

    describe("withdrawBid", async () => {
      beforeEach(async () => {
        await auction.setNowOverride("1");
        await auction.connect(minter).createAuction(
          nft.address,
          firstTokenId,
          "1", // reserve
          "2", // start
          true,
          "400" // end
        );
        await auction.setNowOverride("3");
        await auction
          .connect(buyer)
          .placeBid(nft.address, firstTokenId, { value: 200000000000000000n });
      });

      it("reverts with withdrawing a bid which does not exist", async () => {
        await expect(
          auction.connect(buyer2).withdrawBid(nft.address, 999)
        ).to.be.revertedWith("you are not the highest bidder");
      });

      it("reverts with withdrawing a bid which you did not make", async () => {
        await expect(
          auction.connect(buyer2).withdrawBid(nft.address, firstTokenId)
        ).to.be.revertedWith("you are not the highest bidder");
      });

      it("reverts with withdrawing when lockout time not passed", async () => {
        await auction.updateBidWithdrawalLockTime("6");
        await auction.setNowOverride("5");
        await expect(
          auction.connect(buyer).withdrawBid(nft.address, firstTokenId)
        ).to.be.revertedWith(
          "can withdraw only after 12 hours (after auction ended)"
        );
      });

      it("reverts when withdrawing after auction end", async () => {
        await auction.setNowOverride("401");
        await auction.updateBidWithdrawalLockTime("0");
        await expect(
          auction.connect(buyer).withdrawBid(nft.address, firstTokenId)
        ).to.be.revertedWith(
          "can withdraw only after 12 hours (after auction ended)"
        );
      });

      it("reverts when the contract is paused", async () => {
        const { _bidder: originalBidder, _bid: originalBid } =
          await auction.getHighestBidder(nft.address, firstTokenId);
        expect(originalBid).to.be.equal(BigNumber.from(200000000000000000n));
        expect(originalBidder).to.equal(buyer.address);

        // remove the withdrawal lock time for the test
        await auction.updateBidWithdrawalLockTime("0");

        await auction.toggleIsPaused();
        await expect(
          auction.connect(buyer).withdrawBid(nft.address, firstTokenId)
        ).to.be.revertedWith("contract paused");
      });

      it("successfully withdraw the bid", async () => {
        const { _bidder: originalBidder, _bid: originalBid } =
          await auction.getHighestBidder(nft.address, firstTokenId);
        expect(originalBid).to.be.equal(BigNumber.from(200000000000000000n));
        expect(originalBidder).to.equal(buyer.address);

        // remove the withdrawal lock time for the test
        await auction.updateBidWithdrawalLockTime("0");
        await auction.setNowOverride("400000");

        await expect(() =>
          auction.connect(buyer).withdrawBid(nft.address, firstTokenId)
        ).to.changeEtherBalances([buyer], [200000000000000000n]);

        const { _bidder, _bid } = await auction.getHighestBidder(
          nft.address,
          firstTokenId
        );
        expect(_bid).to.be.equal(BigNumber.from(0));
        expect(_bidder).to.equal("0x0000000000000000000000000000000000000000");
      });
    });
  });
});
