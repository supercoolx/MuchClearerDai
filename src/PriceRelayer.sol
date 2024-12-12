/// spot.sol -- Spotter

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

pragma solidity 0.5.12;

import "./commonFunctions.sol";

contract CDPEngineContract {
    function file(bytes32, bytes32, uint256) external;
}

contract PriceOracleContract {
    function getPrice() external returns (bytes32, bool);
}

contract PriceRelayer is CommonFunctions {
    // --- Data ---
    struct CDPInfo {
        PriceOracleContract priceOracle;
        uint256 liquidationRatio;
    }

    mapping(bytes32 => CDPInfo) public cdpInfos;

    CDPEngineContract public CDPEngine;
    uint256 public targetRatio; // ref per dai

    bool public DSRisActive;

    // --- Events ---
    event UpdatePrice(bytes32 cdpType, bytes32 price, uint256 priceWithSafetyMargin);

    // --- Init ---
    constructor(address CDPEngine_) public {
        authorizedAccounts[msg.sender] = true;
        CDPEngine = CDPEngineContract(CDPEngine_);
        targetRatio = ONE;
        DSRisActive = true;
    }

    // --- Math ---
    uint256 constant ONE = 10 ** 27;

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = mul(x, ONE) / y;
    }

    // --- Administration ---
    function setVariable(bytes32 cdpType, bytes32 variableName, address priceOracleAddr) external emitLog onlyOwners {
        require(DSRisActive == true, "PriceRelayer/not-DSRisActive");
        if (variableName == "priceOracleAddr") cdpInfos[cdpType].priceOracle = PriceOracleContract(priceOracleAddr);
        else revert("PriceRelayer/file-unrecognized-param");
    }

    function setVariable(bytes32 variableName, uint256 _targetRatio) external emitLog onlyOwners {
        require(DSRisActive == true, "PriceRelayer/not-DSRisActive");
        if (variableName == "targetRatio") targetRatio = _targetRatio;
        else revert("PriceRelayer/file-unrecognized-param");
    }

    function setVariable(bytes32 cdpType, bytes32 variableName, uint256 liquidationRatio) external emitLog onlyOwners {
        require(DSRisActive == true, "PriceRelayer/not-DSRisActive");
        if (variableName == "liquidationRatio") cdpInfos[cdpType].liquidationRatio = liquidationRatio;
        else revert("PriceRelayer/file-unrecognized-param");
    }

    // --- Update value ---
    function updatePrice(bytes32 cdpType) external {
        (bytes32 price, bool has) = cdpInfos[cdpType].priceOracle.getPrice();
        uint256 priceWithSafetyMargin =
            has ? rdiv(rdiv(mul(uint256(price), 10 ** 9), targetRatio), cdpInfos[cdpType].liquidationRatio) : 0;
        CDPEngine.file(cdpType, "spot", priceWithSafetyMargin);
        emit UpdatePrice(cdpType, price, priceWithSafetyMargin);
    }

    function cage() external emitLog onlyOwners {
        DSRisActive = false;
    }
}
