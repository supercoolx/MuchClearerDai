/// enableDSR.sol -- Basic token adapters

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

interface SimpleToken {
    function decimals() external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface DSTokenLike {
    function mint(address, uint256) external;
    function burn(address, uint256) external;
}

interface CDPEngineContract {
    function slip(bytes32, address, int256) external;
    function move(address, address, uint256) external;
}

/*
    Here we provide *adapters* to connect the CDPEngineInstance to arbitrary external
    token implementations, creating a bounded context for the CDPEngineInstance. The
    adapters here are provided as working examples:

      - `TokenAdapter`: For well behaved ERC20 tokens, with simple transfer
                   semantics.

      - `ETHAdapter`: For native Ether.

      - `DAItoTokenAdapter`: For connecting internal Dai balances to an external
                   `DSToken` implementation.

    In practice, adapter implementations will be varied and specific to
    individual collateral types, accounting for different transfer
    semantics and token standards.

    Adapters need to implement two basic methods:

      - `enableDSR`: enter collateral into the system
      - `disableDSR`: remove collateral from the system

*/

contract TokenAdapter is CommonFunctions {
    CDPEngineContract public CDPEngine;
    bytes32 public collateralType;
    SimpleToken public tokenCollateral;
    uint256 public dec;
    bool public DSRisActive; // Access Flag

    constructor(address CDPEngine_, bytes32 ilk_, address token_) public {
        authorizedAccounts[msg.sender] = true;
        DSRisActive = true;
        CDPEngine = CDPEngineContract(CDPEngine_);
        collateralType = ilk_;
        tokenCollateral = SimpleToken(token_);
        dec = tokenCollateral.decimals();
    }

    function cage() external emitLog onlyOwners {
        DSRisActive = false;
    }

    function enableDSR(address usr, uint256 amount) external emitLog {
        require(DSRisActive, "TokenAdapter/not-DSRisActive");
        require(int256(amount) >= 0, "TokenAdapter/overflow");
        CDPEngine.slip(collateralType, usr, int256(amount));
        require(tokenCollateral.transferFrom(msg.sender, address(this), amount), "TokenAdapter/failed-transfer");
    }

    function disableDSR(address usr, uint256 amount) external emitLog {
        require(amount <= 2 ** 255, "TokenAdapter/overflow");
        CDPEngine.slip(collateralType, msg.sender, -int256(amount));
        require(tokenCollateral.transfer(usr, amount), "TokenAdapter/failed-transfer");
    }
}

contract ETHAdapter is CommonFunctions {
    CDPEngineContract public CDPEngine;
    bytes32 public collateralType;
    bool public DSRisActive; // Access Flag

    constructor(address CDPEngine_, bytes32 ilk_) public {
        authorizedAccounts[msg.sender] = true;
        DSRisActive = true;
        CDPEngine = CDPEngineContract(CDPEngine_);
        collateralType = ilk_;
    }

    function cage() external emitLog onlyOwners {
        DSRisActive = false;
    }

    function enableDSR(address usr) external payable emitLog {
        require(DSRisActive, "ETHAdapter/not-DSRisActive");
        require(int256(msg.value) >= 0, "ETHAdapter/overflow");
        CDPEngine.slip(collateralType, usr, int256(msg.value));
    }

    function disableDSR(address payable usr, uint256 amount) external emitLog {
        require(int256(amount) >= 0, "ETHAdapter/overflow");
        CDPEngine.slip(collateralType, msg.sender, -int256(amount));
        usr.transfer(amount);
    }
}

contract DAItoTokenAdapter is CommonFunctions {
    CDPEngineContract public CDPEngine;
    DSTokenLike public dai;
    bool public DSRisActive; // Access Flag

    constructor(address CDPEngine_, address dai_) public {
        authorizedAccounts[msg.sender] = true;
        DSRisActive = true;
        CDPEngine = CDPEngineContract(CDPEngine_);
        dai = DSTokenLike(dai_);
    }

    function cage() external emitLog onlyOwners {
        DSRisActive = false;
    }

    uint256 constant ONE = 10 ** 27;

    function safeMul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function enableDSR(address usr, uint256 amount) external emitLog {
        CDPEngine.move(address(this), usr, safeMul(ONE, amount));
        dai.burn(msg.sender, amount);
    }

    function disableDSR(address usr, uint256 amount) external emitLog {
        require(DSRisActive, "DAItoTokenAdapter/not-DSRisActive");
        CDPEngine.move(msg.sender, address(this), safeMul(ONE, amount));
        dai.mint(usr, amount);
    }
}
