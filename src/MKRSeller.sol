/// flop.sol -- Debt auction

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.12;

import "./commonFunctions.sol";

interface CDPEngineContract {
    function move(address, address, uint256) external;
    function suck(address, address, uint256) external;
}

interface SimpleToken {
    function mint(address, uint256) external;
}

/*
   This thing creates MKR on demand in return for dai.

 - `mkrAmount` MKR for sale
 - `bid` dai paid
 - `gal` receives dai income
 - `ttl` single bid lifetime
 - `beg` minimum bid increase
 - `end` max auction duration
*/

contract MKRSeller is CommonFunctions {
    // --- Data ---
    struct Auction {
        uint256 daiAmount; //in dai
        uint256 mkrAmount;
        address highestBidder; // high bidder
        uint48 endTime; // this gets pushed back every time there is a new bid
        uint48 maxEndTime;
    }

    mapping(uint256 => Auction) public auctions;

    CDPEngineContract public CDPEngine;
    SimpleToken public MKRToken;

    uint256 constant ONE = 1.0e18;
    uint256 public minBidDecreaseMultiplier = 1.05e18; // 5% minimum daiAmount increase
    uint256 public mkrAmountMultiplierOnReopen = 1.5e18; // 50% mkrAmount increase for reopen
    uint48 public timeIncreasePerBid = 3 hours; // 3 hours bid lifetime
    uint48 public auctionLength = 2 days; // 2 days total auction length
    uint256 public auctionCount = 0;
    bool public DSRisActive;
    address public debtEngine; // not used until shutdown

    // --- Events ---
    event Kick(uint256 id, uint256 mkrAmount, uint256 bid, address indexed gal);

    // --- Init ---
    constructor(address CDPEngine_, address token_) public {
        authorizedAccounts[msg.sender] = true;
        CDPEngine = CDPEngineContract(CDPEngine_);
        MKRToken = SimpleToken(token_);
        DSRisActive = true;
    }

    // --- Math ---
    function safeAdd(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x);
    }

    function safeMul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Admin ---
    function setVariable(bytes32 variableName, uint256 data) external emitLog onlyOwners {
        if (variableName == "minBidDecreaseMultiplier") minBidDecreaseMultiplier = data;
        else if (variableName == "mkrAmountMultiplierOnReopen") mkrAmountMultiplierOnReopen = data;
        else if (variableName == "timeIncreasePerBid") timeIncreasePerBid = uint48(data);
        else if (variableName == "auctionLength") auctionLength = uint48(data);
        else revert("MKRSeller/file-unrecognized-param");
    }

    // --- Auction ---
    function newAuction(address bidder, uint256 mkrAmount, uint256 daiAmount)
        external
        onlyOwners
        returns (uint256 id)
    {
        require(DSRisActive == true, "MKRSeller/not-DSRisActive");
        require(auctionCount < uint256(-1), "MKRSeller/overflow");
        id = ++auctionCount;

        auctions[id].daiAmount = daiAmount;
        auctions[id].mkrAmount = mkrAmount;
        auctions[id].highestBidder = bidder;
        auctions[id].endTime = safeAdd(uint48(now), auctionLength);

        emit Kick(id, mkrAmount, daiAmount, bidder);
    }

    function reopenAuction(uint256 id) external emitLog {
        require(auctions[id].maxEndTime < now, "MKRSeller/not-finished");
        require(auctions[id].endTime == 0, "MKRSeller/bid-already-placed");
        auctions[id].mkrAmount = safeMul(mkrAmountMultiplierOnReopen, auctions[id].mkrAmount) / ONE;
        auctions[id].maxEndTime = safeAdd(uint48(now), auctionLength);
    }

    function bid(uint256 id, uint256 mkrAmount, uint256 daiAmount) external emitLog {
        require(DSRisActive == true, "MKRSeller/not-DSRisActive");
        require(auctions[id].highestBidder != address(0), "MKRSeller/highestBidder-not-set");
        require(auctions[id].endTime > now || auctions[id].endTime == 0, "MKRSeller/already-finished-tic");
        require(auctions[id].maxEndTime > now, "MKRSeller/already-finished-end");

        require(daiAmount == auctions[id].daiAmount, "MKRSeller/not-matrateAccumulatorng-bid");
        require(mkrAmount < auctions[id].mkrAmount, "MKRSeller/mkrAmount-not-lower");
        require(
            safeMul(minBidDecreaseMultiplier, mkrAmount) <= safeMul(auctions[id].mkrAmount, ONE),
            "MKRSeller/insufficient-decrease"
        );

        CDPEngine.move(msg.sender, auctions[id].highestBidder, daiAmount);

        auctions[id].highestBidder = msg.sender;
        auctions[id].mkrAmount = mkrAmount;
        auctions[id].endTime = safeAdd(uint48(now), timeIncreasePerBid);
    }

    function finalizeAuction(uint256 id) external emitLog {
        require(DSRisActive == true, "MKRSeller/not-DSRisActive");
        require(
            auctions[id].endTime != 0 && (auctions[id].endTime < now || auctions[id].maxEndTime < now),
            "MKRSeller/not-finished"
        );
        MKRToken.mint(auctions[id].highestBidder, auctions[id].mkrAmount);
        delete auctions[id];
    }

    // --- Shutdown ---
    function cage() external emitLog onlyOwners {
        DSRisActive = false;
        debtEngine = msg.sender;
    }

    function cancelAuction(uint256 id) external emitLog {
        require(DSRisActive == false, "MKRSeller/still-DSRisActive");
        require(auctions[id].highestBidder != address(0), "MKRSeller/highestBidder-not-set");
        CDPEngine.suck(debtEngine, auctions[id].highestBidder, auctions[id].daiAmount);
        delete auctions[id];
    }
}
