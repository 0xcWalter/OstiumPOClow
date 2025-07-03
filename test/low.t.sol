// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

contract WalterTest is Test {
    address bob          = address(10);
    address PRICE_UPKEEP = 0x52B2a78E12b09B66C6c8ce291D653D40bAb77f0c;
    address TRADES_UPKEEP = 0x959Da1452238F71F17f7DA5dbA2e9c04FEf57324;
    address usdc         = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    Trading trading      = Trading(0x6D0bA1f9996DBD8885827e1b2e8f6593e7702411);
    StorageT storageT    = StorageT(0xcCd5891083A8acD2074690F65d3024E7D13d66E7);
    TradingCallback tc   = TradingCallback(0x7720fC8c8680bF4a1Af99d44c6c265a74e9742a9);
    PairInfos pi         = PairInfos(0x3890243A8fc091C626ED26c087A028B46Bc9d66C);
    pairStorage ps       = pairStorage(0x260E349F643f12797fDc6f8c9d3df211D5577823);

    address vault        = 0x20D419a8e12C45f88fDA7c5760bb6923Cee27F98;
    uint256 startingBalance = 1_000_000_000e6;

    function setUp() public {
        vm.createSelectFork("https://arbitrum.drpc.org");

        // Next line will revert if past block passed,please insert latest block. (this is because arbitrum precompile foundry bug)
        uint256 currentBlock = getBlock();                 // workaround InvalidFEOpcode
        vm.chainId(4216138);                               // workaround InvalidFEOpcode
        vm.roll(currentBlock);                             // workaround InvalidFEOpcode
        deal(usdc,bob,startingBalance);
        deal(usdc,address(this),startingBalance);
        ERC20(usdc).approve(address(storageT),type(uint256).max);
        vm.startPrank(bob);
        ERC20(usdc).approve(address(storageT),type(uint256).max);
        vm.stopPrank();
    }

    function getBlock()internal view returns(uint256){
        string memory res = vm.readFile("test/currentBlock");
        uint256 blockNumber = stringToUint(res);
        return blockNumber;
    }

    function stringToUint(string memory s) public pure returns (uint256 result) {
        bytes memory b = bytes(s);
        for (uint i = 0; i < b.length; i++) {
            require(b[i] >= 0x30 && b[i] <= 0x39, "Invalid character: not a digit");
            result = result * 10 + (uint8(b[i]) - 48);
        }
    }

    function test_IncorrectFeesTaken()external{
        uint32 leverage = 4026;
        uint256 amount = 8092132613;

        vm.startPrank(bob);
        vm.recordLogs();
        Trading.OpenOrderType orderType = Trading.OpenOrderType.MARKET;
        Trading.Trade memory trade = Trading.Trade(
            amount,              // Collateral
            100e18,             // Price
            0,                  // Take profit
            0,                  // Stop loss
            address(this),      // Trader
            leverage,              // Leverage [0-20000]
            0,                  // Pair index
            0,                  // Index
            true                // Buying?
        );
        trading.openTrade(trade,orderType,100);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 orderId = uint256(logs[1].topics[1]);
        vm.stopPrank();
        
        vm.startPrank(PRICE_UPKEEP);
        TradingCallback.PriceUpKeepAnswer memory upKeepAnswer = TradingCallback.PriceUpKeepAnswer(
            orderId,                    // Order trade id
            100e18,                     // Market price
            100e18-1,                   // Bid (buying)
            100e18+1,                   // Ask (selling)      
            true                        // Trading closed
        );

        tc.openTradeMarketCallback(upKeepAnswer);
        vm.stopPrank();
    
        (uint256 collateral,,,,,,,,) = storageT.openTrades(bob, 0, 0);
        require(collateral!=0);


        uint256 totalInitialPosition = amount*uint256(leverage)/100;
        uint256 maxFees = totalInitialPosition*10/10_000;
        uint256 effectiveFee = amount-collateral;
        console.log("the maxFees are: ",maxFees);
        console.log("current fees taken: ",effectiveFee);
        vm.assertGt(effectiveFee,maxFees);   
    }
}
interface PairInfos{
    struct PairOpeningFees {
        uint32 makerFeeP; // PRECISION_6 (%)
        uint32 takerFeeP; // PRECISION_6 (%)
        uint32 usageFeeP; // PRECISION_6 (%)
        uint16 utilizationThresholdP; // PRECISION_2 (%)
        uint16 makerMaxLeverage; // PRECISION_2
        uint8 vaultFeePercent;
    }
    struct PairFundingFeesV2 {
        int256 accPerOiLong; // PRECISION_18 (but USDC)
        int256 accPerOiShort; // PRECISION_18 (but USDC)
        int64 lastFundingRate; // PRECISION_18
        int64 hillInflectionPoint; // PRECISION_18
        uint64 maxFundingFeePerBlock; // PRECISION_18
        uint64 springFactor; // PRECISION_18
        uint32 lastUpdateBlock;
        uint16 hillPosScale; // PRECISION_2
        uint16 hillNegScale; // PRECISION_2
        uint16 sFactorUpScaleP; // PRECISION_2
        uint16 sFactorDownScaleP; // PRECISION_2
        int256 lastOiDelta; // PRECISION_6
    }
    function pairOpeningFees(uint16 pairIndex)external returns(PairOpeningFees memory);
    function getPendingAccFundingFees(uint16 pairIndex)external view returns (int256, int256, int64, int256);
    function getPendingAccRolloverFees(uint16)external view returns(uint256);
}

interface Trading{
    function executeAutomationOrder(
        LimitOrder orderType,
        address trader,
        uint16 pairIndex,
        uint8 index,
        uint256 priceTimestamp
    ) external;
    enum CancelReason {
        NONE,
        PAUSED,
        MARKET_CLOSED,
        SLIPPAGE,
        TP_REACHED,
        SL_REACHED,
        EXPOSURE_LIMITS,
        PRICE_IMPACT,
        MAX_LEVERAGE,
        NO_TRADE,
        UNDER_LIQUIDATION,
        NOT_HIT,
        GAIN_LOSS,
        DAY_TRADE_NOT_ALLOWED,
        CLOSE_DAY_TRADE_NOT_ALLOWED
    }
     event AutomationCloseOrderCanceled(
        uint256 indexed orderId,
        uint256 indexed tradeId,
        address indexed trader,
        uint256 pairIndex,
        LimitOrder orderType,
        CancelReason cancelReason
    );
    enum LimitOrder {
        TP,
        SL,
        LIQ,
        OPEN,
        CLOSE_DAY_TRADE,
        REMOVE_COLLATERAL
    }
    event MarketOpenOrderInitiated(address indexed user, uint256 amount, bytes data);
    enum OpenOrderType {
        MARKET,
        LIMIT,
        STOP
    }
    struct Trade {
        uint256 collateral; // PRECISION_6
        uint192 openPrice; // PRECISION_18
        uint192 tp; // PRECISION_18
        uint192 sl; // PRECISION_18
        address trader;
        uint32 leverage; // PRECISION_2
        uint16 pairIndex;
        uint8 index;
        bool buy;
    }
    function closeTradeMarket(uint16 pairIndex, uint8 index, uint16 closePercentage) external;
    function removeCollateral(uint16 pairIndex, uint8 index, uint256 removeAmount)external;
    function topUpCollateral(uint16 pairIndex, uint8 index, uint256 topUpAmount) external;
    function openTrade(
        Trade calldata t,
        OpenOrderType orderType,
        uint256 slippageP
    ) external;
     function updateSl(uint16 pairIndex, uint8 index, uint192 newSl) external;
}

interface StorageT{
        struct PendingAutomationOrder {
        address trader;
        uint16 pairIndex;
        uint8 index;
        Trading.LimitOrder orderType;
    }
    function handleOpeningFees(
        uint16 _pairIndex,
        uint256 latestPrice,
        uint256 _leveragedPositionSize,
        uint32 leverage,
        bool isBuy
    ) external returns (uint256 devFee, uint256 vaultFee);
    function openInterest(uint16 pairIndex,uint256 index)external returns(uint256);
    function reqID_pendingAutomationOrder(uint256 orderId)external returns(PendingAutomationOrder memory);
    function openTrades(
        address trader,
        uint16 pairIndex,
        uint8 tradeIndex
    )external returns(uint256 collateral,uint192 openPrice,uint192 tp ,uint192 sl ,address traderAddr,uint32 leverage,uint16 pairI,uint8 index,bool buy);
}

interface pairStorage{
    function groupCollateral(uint16,bool)external view returns(uint256);
}

interface ArbSys {
    /**
     * @notice Get Arbitrum block number (distinct from L1 block number; Arbitrum genesis block has block number 0)
     * @return block number as int
     */
    function arbBlockNumber() external view returns (uint256);
}

interface TradingCallback{
    struct PriceUpKeepAnswer {
        uint256 orderId;
        int192 price;
        int192 bid;
        int192 ask;
        bool isDayTradingClosed;
    }
    function executeAutomationCloseOrderCallback(PriceUpKeepAnswer calldata a) external;
    function executeAutomationOpenOrderCallback(PriceUpKeepAnswer calldata a) external;
    function closeTradeMarketCallback(PriceUpKeepAnswer calldata a) external;
    function handleRemoveCollateral(PriceUpKeepAnswer calldata a) external;
    function openTradeMarketCallback(PriceUpKeepAnswer calldata a) external;
}