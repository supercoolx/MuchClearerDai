/// join.sol -- Basic token adapters

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

interface TokenContract {
    function decimals() external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface DSTokenLike {
    function mint(address, uint256) external;
    function burn(address, uint256) external;
}

interface VaultContract {
    function slip(bytes32, address, int256) external;
    function move(address, address, uint256) external;
}

/*
    Here we provide *adapters* to connect the Vault to arbitrary external
    token implementations, creating a bounded context for the Vault. The
    adapters here are provided as working examples:

      - `ERC20Adapter`: For well behaved ERC20 tokens, with simple transfer
                   semantics.

      - `ETHAdapter`: For native Ether.

      - `DAITokenAdapter`: For connecting internal Dai balances to an external
                   `DSToken` implementation.

    In practice, adapter implementations will be varied and specific to
    individual collateral types, accounting for different transfer
    semantics and token standards.

    Adapters need to implement two basic methods:

      - `join`: enter collateral into the system
      - `exit`: remove collateral from the system

*/

contract ERC20Adapter is CommonFunctions {
    VaultContract public vault;
    bytes32 public collateralType;
    TokenContract public tokenCollateral;
    uint256 public dec;
    uint256 public live; // Access Flag

    constructor(address vault_, bytes32 collateralType_, address gem_) public {
        authorizedAccounts[msg.sender] = true;
        live = 1;
        vault = VaultContract(vault_);
        collateralType = collateralType_;
        tokenCollateral = TokenContract(gem_);
        dec = tokenCollateral.decimals();
    }

    function cage() external emitLog onlyOwners {
        live = 0;
    }

    function join(address usr, uint256 wad) external emitLog {
        require(live == 1, "ERC20Adapter/not-live");
        require(int256(wad) >= 0, "ERC20Adapter/overflow");
        vault.slip(collateralType, usr, int256(wad));
        require(tokenCollateral.transferFrom(msg.sender, address(this), wad), "ERC20Adapter/failed-transfer");
    }

    function exit(address usr, uint256 wad) external emitLog {
        require(wad <= 2 ** 255, "ERC20Adapter/overflow");
        vault.slip(collateralType, msg.sender, -int256(wad));
        require(tokenCollateral.transfer(usr, wad), "ERC20Adapter/failed-transfer");
    }
}

contract ETHAdapter is CommonFunctions {

    VaultContract public vault;
    bytes32 public collateralType;
    uint256 public live; // Access Flag

    constructor(address vault_, bytes32 collateralType_) public {
        authorizedAccounts[msg.sender] = true;
        live = 1;
        vault = VaultContract(vault_);
        collateralType = collateralType_;
    }

    function cage() external emitLog onlyOwners {
        live = 0;
    }

    function join(address usr) external payable emitLog {
        require(live == 1, "ETHAdapter/not-live");
        require(int256(msg.value) >= 0, "ETHAdapter/overflow");
        vault.slip(collateralType, usr, int256(msg.value));
    }

    function exit(address payable usr, uint256 wad) external emitLog {
        require(int256(wad) >= 0, "ETHAdapter/overflow");
        vault.slip(collateralType, msg.sender, -int256(wad));
        usr.transfer(wad);
    }
}

contract DAITokenAdapter is CommonFunctions {
    VaultContract public vault;
    DSTokenLike public dai;
    uint256 public live; // Access Flag

    constructor(address vault_, address dai_) public {
        authorizedAccounts[msg.sender] = true;
        live = 1;
        vault = VaultContract(vault_);
        dai = DSTokenLike(dai_);
    }

    function cage() external emitLog onlyOwners {
        live = 0;
    }

    uint256 constant ONE = 10 ** 27;

    function safeMul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function join(address usr, uint256 wad) external emitLog {
        vault.move(address(this), usr, safeMul(ONE, wad));
        dai.burn(msg.sender, wad);
    }

    function exit(address usr, uint256 wad) external emitLog {
        require(live == 1, "DAITokenAdapter/not-live");
        vault.move(msg.sender, address(this), safeMul(ONE, wad));
        dai.mint(usr, wad);
    }
}
