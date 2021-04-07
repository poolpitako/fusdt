// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {
    BaseStrategy
} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "../interfaces/ICurveFi.sol";
import "../interfaces/IMasterchef.sol";
import "../interfaces/uni/IUniswapV2Router02.sol";
import "../interfaces/IERC20Extended.sol";

contract FusdtCurveIce is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    ICurveFi public constant curvePool = ICurveFi(address(0xa42Bd395F183726d1a8774cFA795771F8ACFD777));
    IMasterchef public constant masterchef = IMasterchef(address(0x05200cB2Cee4B6144B2B2984E246B52bB1afcBD0));
    IUniswapV2Router02 public constant router = IUniswapV2Router02(address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506));
    uint256 public constant pid = 2;
    int128 public constant curveId = 0;
    address public constant WETH = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public constant reward = address(0xf16e81dce15B08F326220742020379B855B87DF9);
    uint256 public maxSingleInvest;
    uint256 public slippageProtectionIn;
    uint8 private wantDecimals;

    constructor(address _vault, uint256 _maxSingleInvest) public BaseStrategy(_vault) {
        IERC20(reward).approve(address(router), type(uint256).max);
        IERC20(want).approve(address(curvePool), type(uint256).max);
        wantDecimals = IERC20Extended(address(want)).decimals();
        maxSingleInvest = _maxSingleInvest;
    }

    function name() external view override returns (string memory) {
        return "StrategyFusdtCurveIce";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return want.balanceOf(address(this));
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // Gets the reward from the masterchef contract
        getReward();
        swapReward();
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }

        if (_debtOutstanding >= balanceOfWant()) {
            return;
        }

        // Invest the rest of the want
        uint256 _wantToInvest =Math.min(balanceOfWant(), maxSingleInvest);
        if (_wantToInvest == 0) {
            return;
        }

        uint256 expectedOut = _wantToInvest.mul(1e18).div(virtualPriceToWant());
        uint256 maxSlip = expectedOut.mul(DENOMINATOR.sub(slippageProtectionIn)).div(DENOMINATOR);

    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // TODO: Do stuff here to free up to `_amountNeeded` from all positions back into `want`
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`

        uint256 totalAssets = want.balanceOf(address(this));
        if (_amountNeeded > totalAssets) {
            _liquidatedAmount = totalAssets;
            _loss = _amountNeeded.sub(totalAssets);
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
    }

    // returns value of total
    function curveTokenToWant(uint256 tokens) public view returns (uint256) {
        if (tokens == 0) {
            return 0;
        }

        //we want to choose lower value of virtual price and amount we really get out
        //this means we will always underestimate current assets.
        uint256 virtualOut = virtualPriceToWant().mul(tokens).div(1e18);
        uint256 realOut;
        bool hasUnderlying = true;
        if (hasUnderlying) {
            realOut = curvePool.calc_withdraw_one_coin(tokens, curveId, true);
        } else {
            realOut = curvePool.calc_withdraw_one_coin(tokens, curveId);
        }

        return Math.min(virtualOut, realOut);
    }

    //we lose some precision here. but it shouldnt matter as we are underestimating
    function virtualPriceToWant() public view returns (uint256) {
        if (wantDecimals < 18) {
            return
                curvePool.get_virtual_price().div(
                    10**(uint256(uint8(18) - wantDecimals))
                );
        } else {
            return curvePool.get_virtual_price();
        }
    }

    function swapReward() internal {
        if (balanceOfReward() == 0) {
            return;
        }

        address[] memory path = new address[](3);
        path[0] = reward;
        path[1] = WETH;
        path[2] = address(want);

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
          balanceOfReward(),
          0,
          path,
          address(this),
          now
        );
    }

    function getReward() internal {
        masterchef.deposit(pid, 0);
    }

    function balanceOfReward() public view returns (uint256) {
        return IERC20(reward).balanceOf(address(this));
    }

    function balanceOfStake() public view returns (uint256) {
        return masterchef.userInfo(pid, address(this)).amount;
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function setMaxSingleInvest(uint256 _maxSingleInvest) public onlyAuthorized {
        maxSingleInvest = _maxSingleInvest;
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}
}
