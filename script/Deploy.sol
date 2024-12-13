// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.2;

import {Script, console} from "forge-std/Script.sol";
import {CDPEngineInstance} from "../src/CDPEngine.sol";
import {CollateralAuction} from "../src/collateralAuction.sol";
import {DaiSavingsRateContract} from "../src/daiSavingsRate.sol";
import {Dai} from "../src/DAITokenCode.sol";
import {DebtAuction} from "../src/debtAuction.sol";
import {DebtEngine} from "../src/debtEngine.sol";
import {GlobalSettlement} from "../src/globalSettlement.sol";
import {Liquidations} from "../src/liquidations.sol";
import {MKRSeller} from "../src/MKRSeller.sol";
import {Oracle} from "../src/oracle.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {PriceRelayer} from "../src/PriceRelayer.sol";
import {Savings} from "../src/savings.sol";
import {Jug} from "../src/stabilityFees.sol";
import {SurplusAuction} from "../src/surplusAuction.sol";
import {ERC20Adapter} from "../src/tokenAdapters.sol";
import {Vault} from "../src/vault.sol";

contract DeployScript is Script {
    CDPEngineInstance public cdpEngineInstance;
    CollateralAuction public collateralAuction;
    DaiSavingsRateContract public daiSavingsRateContract;
    Dai public dai;
    DebtAuction public debtAuction;
    DebtEngine public debtEngine;
    GlobalSettlement public globalSettlement;
    Liquidations public liquidations;
    MKRSeller public mkrSeller;
    Oracle public oracle;
    PriceOracle public priceOracle;
    PriceRelayer public priceRelayer;
    Savings public savings;
    Jug public jug;
    SurplusAuction public surplusAuction;
    ERC20Adapter public adapter;
    Vault public vault;

    function run() public {
        vm.startBroadcast();
        cdpEngineInstance = new CDPEngineInstance();
        vault = new Vault();
        globalSettlement = new GlobalSettlement();
        priceOracle = new PriceOracle();
        daiSavingsRateContract = new DaiSavingsRateContract(address(cdpEngineInstance));
        liquidations = new Liquidations(address(vault));
        oracle = new Oracle(address(vault));
        priceRelayer = new PriceRelayer(address(cdpEngineInstance));
        savings = new Savings(address(vault));
        jug = new Jug(address(cdpEngineInstance));
        dai = new Dai(5777);
        debtAuction = new DebtAuction(address(vault), address(dai));
        surplusAuction = new SurplusAuction(address(vault), address(dai));
        debtEngine = new DebtEngine(address(cdpEngineInstance), address(surplusAuction), address(debtAuction));
        mkrSeller = new MKRSeller(address(cdpEngineInstance), address(dai));
        collateralAuction = new CollateralAuction(address(vault), keccak256(abi.encodePacked("ETH-A")));
        adapter = new ERC20Adapter(address(vault), keccak256(abi.encodePacked("ETH-A")), address(dai));

        vm.stopBroadcast();
    }
}
