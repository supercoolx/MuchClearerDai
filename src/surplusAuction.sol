/// flap.sol -- Surplus auction

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

interface VaultContract {
    function move(address, address, uint256) external;
}

interface TokenContract {
    function move(address, address, uint256) external;
    function burn(address, uint256) external;
}

/*
   This thing lets you sell some dai in return for gems.

 - `lot` dai for sale
 - `bid` gems paid
 - `ttl` single bid lifetime
 - `beg` minimum bid increase
 - `end` max auction duration
*/

contract SurplusAuction is CommonFunctions {
    // --- Data ---
    struct Bid {
        uint256 bid;
        uint256 lot;
        address guy; // high bidder
        uint48 tic; // expiry time
        uint48 end;
    }

    mapping(uint256 => Bid) public bids;

    VaultContract public vault;
    TokenContract public tokenCollateral;

    uint256 constant ONE = 1.0e18;
    uint256 public beg = 1.05e18; // 5% minimum bid increase
    uint48 public ttl = 3 hours; // 3 hours bid duration
    uint48 public tau = 2 days; // 2 days total auction length
    uint256 public kicks = 0;
    uint256 public live;

    // --- Events ---
    event Kick(uint256 id, uint256 lot, uint256 bid);

    // --- Init ---
    constructor(address vault_, address gem_) public {
        authorizedAccounts[msg.sender] = true;
        vault = VaultContract(vault_);
        tokenCollateral = TokenContract(gem_);
        live = 1;
    }

    // --- Math ---
    function safeAdd(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x);
    }

    function safeMul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Admin ---
    function file(bytes32 what, uint256 data) external emitLog onlyOwners {
        if (what == "beg") beg = data;
        else if (what == "ttl") ttl = uint48(data);
        else if (what == "tau") tau = uint48(data);
        else revert("SurplusAuction/file-unrecognized-param");
    }

    // --- Auction ---
    function kick(uint256 lot, uint256 bid) external onlyOwners returns (uint256 id) {
        require(live == 1, "SurplusAuction/not-live");
        require(kicks < uint256(-1), "SurplusAuction/overflow");
        id = ++kicks;

        bids[id].bid = bid;
        bids[id].lot = lot;
        bids[id].guy = msg.sender; // configurable??
        bids[id].end = safeAdd(uint48(now), tau);

        vault.move(msg.sender, address(this), lot);

        emit Kick(id, lot, bid);
    }

    function tick(uint256 id) external emitLog {
        require(bids[id].end < now, "SurplusAuction/not-finished");
        require(bids[id].tic == 0, "SurplusAuction/bid-already-placed");
        bids[id].end = safeAdd(uint48(now), tau);
    }

    function tend(uint256 id, uint256 lot, uint256 bid) external emitLog {
        require(live == 1, "SurplusAuction/not-live");
        require(bids[id].guy != address(0), "SurplusAuction/guy-not-set");
        require(bids[id].tic > now || bids[id].tic == 0, "SurplusAuction/already-finished-tic");
        require(bids[id].end > now, "SurplusAuction/already-finished-end");

        require(lot == bids[id].lot, "SurplusAuction/lot-not-matching");
        require(bid > bids[id].bid, "SurplusAuction/bid-not-higher");
        require(safeMul(bid, ONE) >= safeMul(beg, bids[id].bid), "SurplusAuction/insufficient-increase");

        tokenCollateral.move(msg.sender, bids[id].guy, bids[id].bid);
        tokenCollateral.move(msg.sender, address(this), bid - bids[id].bid);

        bids[id].guy = msg.sender;
        bids[id].bid = bid;
        bids[id].tic = safeAdd(uint48(now), ttl);
    }

    function deal(uint256 id) external emitLog {
        require(live == 1, "SurplusAuction/not-live");
        require(bids[id].tic != 0 && (bids[id].tic < now || bids[id].end < now), "SurplusAuction/not-finished");
        vault.move(address(this), bids[id].guy, bids[id].lot);
        tokenCollateral.burn(address(this), bids[id].bid);
        delete bids[id];
    }

    function cage(uint256 rad) external emitLog onlyOwners {
        live = 0;
        vault.move(address(this), msg.sender, rad);
    }

    function yank(uint256 id) external emitLog {
        require(live == 0, "SurplusAuction/still-live");
        require(bids[id].guy != address(0), "SurplusAuction/guy-not-set");
        tokenCollateral.move(address(this), bids[id].guy, bids[id].bid);
        delete bids[id];
    }
}
